import AppKit
import ApplicationServices
import Combine
import StatusDeckKit
import SwiftUI

/// Mos's interpolation core, hosted by StatusDeck. The adapter owns the tap and
/// timer so disabling this plugin releases every event interception immediately.
@MainActor
final class MosEngine: ObservableObject {
    @Published private(set) var active = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var permissionTimer: Timer?
    private var origin = CGPoint.zero
    private var flags: CGEventFlags = []
    private var remaining = CGPoint.zero
    private var fractionalPixels = CGPoint.zero
    private var tailEvent: CGEvent?
    private var lastFrame = 0.0
    private var targetPID: pid_t = 0
    private let marker: Int64 = 0x5354415455534D4F
    let preferences: MosPreferences
    private var transition = MosScrollOptions().frameTransition

    init(preferences: MosPreferences? = nil) {
        self.preferences = preferences ?? MosPreferences()
    }

    func start() {
        guard !connect() else { return }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, AXIsProcessTrusted(), self.connect() else { return }
                self.permissionTimer?.invalidate(); self.permissionTimer = nil
            }
        }
    }

    func stop() {
        finish()
        permissionTimer?.invalidate(); permissionTimer = nil
        if let tap { CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil; tap = nil; active = false
    }

    private func connect() -> Bool {
        guard tap == nil else { return true }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue), callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let engine = Unmanaged<MosEngine>.fromOpaque(context).takeUnretainedValue()
                return MainActor.assumeIsolated { engine.receive(type, event) }
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }
        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        active = true
        return true
    }

    func receive(_ type: CGEventType, _ event: CGEvent, canPost: () -> Bool = CGPreflightPostEventAccess) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            finish()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let original = Unmanaged.passUnretained(event)
        guard type == .scrollWheel, event.getIntegerValueField(.eventSourceUserData) != marker else {
            return original
        }
        guard event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 else {
            finish()
            return original
        }

        let pid = pid_t(clamping: event.getIntegerValueField(.eventTargetUnixProcessID))
        let app = pid > 0 ? NSRunningApplication(processIdentifier: pid) : NSWorkspace.shared.frontmostApplication
        guard let options = preferences.settings(for: app?.bundleIdentifier) else {
            finish()
            return original
        }
        let target = pid > 0 ? pid : (app?.processIdentifier ?? 0)
        if targetPID != target || event.flags != flags || hypot(event.location.x - origin.x, event.location.y - origin.y) > 12 {
            finish()
        }
        var x = WheelAxis(event, fields: Self.horizontal)
        var y = WheelAxis(event, fields: Self.vertical)
        if options.horizontalKey.isHeld(in: event.flags), !x.hasInput {
            swap(&x, &y)
        }
        let smooth = options.smooth && !options.bypassKey.isHeld(in: event.flags) && canPost()
        let boost = options.boostKey.isHeld(in: event.flags) ? 5.0 : 1.0
        guard smooth else {
            finish()
            passThrough(x, to: event, fields: Self.horizontal, reverse: options.reverseX, boost: boost)
            passThrough(y, to: event, fields: Self.vertical, reverse: options.reverseY, boost: boost)
            return original
        }

        let gain = min(MosScrollOptions.speedRange.upperBound, max(MosScrollOptions.speedRange.lowerBound, options.speed))
        let step = min(MosScrollOptions.stepRange.upperBound, max(MosScrollOptions.stepRange.lowerBound, options.minimumStep))
        let dx = x.displacement(minimumStep: step) * gain * boost * (options.reverseX ? -1 : 1)
        let dy = y.displacement(minimumStep: step) * gain * boost * (options.reverseY ? -1 : 1)
        guard dx != 0 || dy != 0 else { return original }

        targetPID = target
        origin = event.location
        flags = event.flags
        transition = options.frameTransition
        if (remaining.x + fractionalPixels.x) * dx < 0 {
            remaining.x = 0
            fractionalPixels.x = 0
        }
        if (remaining.y + fractionalPixels.y) * dy < 0 {
            remaining.y = 0
            fractionalPixels.y = 0
        }
        remaining.x += dx
        remaining.y += dy

        // Deliver the first fraction through the original event, so the wheel
        // still scrolls if macOS declines to post a later synthetic frame.
        let first = advance(fraction: transition)
        writePixels(first, to: event)
        guard remaining != .zero else {
            finish(resetRemainder: false)
            return original
        }
        tailEvent = event.copy()
        guard tailEvent != nil else { finish(); return original }
        if timer == nil {
            lastFrame = ProcessInfo.processInfo.systemUptime
            let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.frame() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        return original
    }

    private typealias AxisFields = (points: CGEventField, lines: CGEventField, fixed: CGEventField)
    private static let vertical: AxisFields = (.scrollWheelEventPointDeltaAxis1, .scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1)
    private static let horizontal: AxisFields = (.scrollWheelEventPointDeltaAxis2, .scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2)

    private struct WheelAxis {
        let points: Double
        let lines: Int64
        let fixed: Double

        init(_ event: CGEvent, fields: AxisFields) {
            points = event.getDoubleValueField(fields.points)
            lines = event.getIntegerValueField(fields.lines)
            fixed = event.getDoubleValueField(fields.fixed)
        }

        var hasInput: Bool { points != 0 || fixed != 0 || lines != 0 }

        // Mos 3.5 applies the minimum only to point deltas. Its fixed and
        // line fallbacks go directly into the same speed-gain calculation.
        func displacement(minimumStep: Double) -> Double {
            if points != 0 { return points.sign == .minus ? -max(-points, minimumStep) : max(points, minimumStep) }
            return fixed != 0 ? fixed : Double(lines)
        }
    }

    private func passThrough(_ axis: WheelAxis, to event: CGEvent, fields: AxisFields, reverse: Bool, boost: Double) {
        let factor = reverse ? -boost : boost
        let lines = min(Double(Int32.max), max(Double(Int32.min), Double(axis.lines) * factor))
        event.setIntegerValueField(fields.lines, value: Int64(lines))
        event.setDoubleValueField(fields.fixed, value: axis.fixed * factor)
        event.setDoubleValueField(fields.points, value: axis.points * factor)
    }

    private func writePixels(_ delta: CGPoint, to event: CGEvent) {
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        for (fields, pixels) in [(Self.horizontal, delta.x), (Self.vertical, delta.y)] {
            // Setting the line delta also resets the pixel delta in Quartz.
            event.setIntegerValueField(fields.lines, value: 0)
            event.setDoubleValueField(fields.fixed, value: 0)
            event.setIntegerValueField(fields.points, value: Int64(pixels))
        }
    }

    private func advance(fraction: Double) -> CGPoint {
        func next(_ pending: Double) -> Double {
            let pixels = Interpolator.lerp(src: 0, dest: pending, trans: fraction)
            return abs(pending - pixels) < 0.01 ? pending : pixels
        }
        let delta = CGPoint(x: next(remaining.x), y: next(remaining.y))
        remaining.x -= delta.x
        remaining.y -= delta.y

        // The Quartz point field is integral. Keep fractions across frames and
        // wheel notches to preserve the requested gain instead of rounding up
        // every event or silently losing fine-grained movement.
        fractionalPixels.x += delta.x
        fractionalPixels.y += delta.y
        func whole(_ value: CGFloat) -> CGFloat {
            let magnitude = min(CGFloat(Int32.max), (abs(value) + 1e-9).rounded(.down))
            return value < 0 ? -magnitude : magnitude
        }
        let pixels = CGPoint(x: whole(fractionalPixels.x), y: whole(fractionalPixels.y))
        fractionalPixels.x -= pixels.x
        fractionalPixels.y -= pixels.y
        return pixels
    }

    private func frame() {
        guard let event = tailEvent?.copy() else { finish(); return }
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.05, max(0.001, now - lastFrame))
        lastFrame = now
        let fraction = 1 - pow(1 - transition, dt * 60)
        let pixels = advance(fraction: fraction)
        if pixels != .zero {
            writePixels(pixels, to: event)
            event.timestamp = DispatchTime.now().uptimeNanoseconds
            event.setIntegerValueField(.eventSourceUserData, value: marker)
            event.post(tap: .cgSessionEventTap)
        }
        if remaining == .zero { finish(resetRemainder: false) }
    }

    private func finish(resetRemainder: Bool = true) {
        timer?.invalidate()
        timer = nil
        tailEvent = nil
        remaining = .zero
        if resetRemainder { fractionalPixels = .zero }
    }

}

@MainActor
final class MosPlugin: DeckPlugin {
    let manifest = PluginManifest(id: "com.statusdeck.mos", name: "Mos 平滑滚动", summary: "插件 3 · 鼠标滚轮平滑、方向与应用例外", symbol: "computermouse", version: "1.2.1", category: .tools, enabledByDefault: false, sortOrder: 397)
    let engine = MosEngine()
    private weak var host: (any DeckHost)?
    private lazy var icon = DeckMenuBarItem(image: NSImage(systemSymbolName: "computermouse", accessibilityDescription: "Mos"))

    func activate(host: any DeckHost) {
        self.host = host
        if !host.isDryRun { engine.start() }
    }

    func deactivate() {
        engine.stop()
        host = nil
    }

    var menuBarItem: DeckMenuBarItem? { engine.preferences.hidesIcon ? nil : icon }

    var settingsView: AnyView? {
        AnyView(MosSettings(engine: engine, preferences: engine.preferences, version: manifest.version,
            iconChanged: { [weak self] in self?.host?.pluginContentDidChange() },
            openUpdates: { [weak self] in self?.host?.openSettings(pluginID: "__updates__") }
        ))
    }
}

@_cdecl("statusdeck_plugin_create")
public func statusdeckPluginCreate() -> UnsafeMutableRawPointer { DeckPluginExport.retained { MosPlugin() } }
