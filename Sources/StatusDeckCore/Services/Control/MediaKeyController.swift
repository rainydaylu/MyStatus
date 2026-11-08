import AppKit
import Carbon
import ApplicationServices
import Combine
import Foundation
import StatusDeckKit

/// Who gets a brightness or volume key. Anything this app cannot serve goes back to
/// macOS, so a built-in screen or ordinary speakers keep working exactly as before.
enum MediaKeyRouting {
    static func step(isFine: Bool) -> Double {
        isFine ? 1.0 / 64 : 1.0 / 16
    }

    /// macOS already handles brightness media events on Apple displays. Ordinary
    /// F1/F2 events and the app's backup shortcut need an explicit brightness write.
    static func takesBrightness(on display: DisplayState?, isMediaEvent: Bool = true) -> Bool {
        guard let display else { return false }
        return !isMediaEvent || display.kind != .apple
    }

    static func needsHardwareBrightnessListener(for displays: [DisplayState]) -> Bool {
        displays.contains { takesBrightness(on: $0) }
    }

    /// Software volume is only real while the sound plugin runs its engine. Taking the
    /// key without it would look like a working key that changes nothing.
    static func takesVolume(route: VolumeRoute, softwareEngineRuns: Bool) -> Bool {
        switch route {
        case .hardware, .unavailable: false
        case .ddc: true
        case .software, .softwareAvailable: softwareEngineRuns
        }
    }
}

/// One physical press can arrive through both IOKit and Quartz. Pair each
/// delivery once, using the event time rather than when the main queue ran it.
struct BrightnessKeyDelivery {
    enum Source { case hardware, quartz }
    private struct Receipt {
        let key: MediaKeyController.Key
        let source: Source
        let time: UInt64
    }

    private var receipts: [Receipt] = []

    mutating func consumeDuplicate(_ key: MediaKeyController.Key, source: Source, time: UInt64) -> Bool {
        receipts.removeAll { time > $0.time && time - $0.time > 250_000_000 }
        func distance(_ other: UInt64) -> UInt64 { time >= other ? time - other : other - time }
        guard let index = receipts.indices.filter({ receipts[$0].key == key && receipts[$0].source != source })
            .min(by: { distance(receipts[$0].time) < distance(receipts[$1].time) }),
              distance(receipts[index].time) <= 16_000_000 else { return false }
        receipts.remove(at: index)
        return true
    }

    mutating func record(_ key: MediaKeyController.Key, source: Source, time: UInt64) {
        receipts.append(Receipt(key: key, source: source, time: time))
    }
}

/// Lets the keyboard's brightness and volume keys reach what macOS cannot control
/// itself, the core idea of MonitorControl. Needs Accessibility access, which macOS
/// grants without telling the app, so while it is missing this keeps checking.
@MainActor
final class MediaKeyController: ObservableObject {
    enum Key: Int32, Sendable {
        case soundUp = 0
        case soundDown = 1
        case brightnessUp = 2
        case brightnessDown = 3
        case mute = 7

        var isBrightness: Bool { self == .brightnessDown || self == .brightnessUp }

        func preservesFnCombination(_ fnIsDown: @autoclosure () -> Bool) -> Bool {
            isBrightness && fnIsDown()
        }
    }

    struct Press {
        let key: Key
        let isFineStep: Bool
        let isRepeat: Bool
        let isMediaEvent: Bool
    }

    /// Returns true when the key was handled and must not reach the system.
    var handler: ((Press) -> Bool)?

    /// At least one event tap is currently enabled.
    @Published private(set) var isActive = false

    @Published private(set) var lastBrightnessKey: String?
    @Published private(set) var brightnessKeyCount = 0
    @Published private(set) var hardwareBrightnessState = BrightnessHIDMonitor.State.inactive
    var shouldObserveHardwareBrightness: (() -> Bool)?

    private let hardware = BrightnessHIDMonitor()
    private var brightnessDelivery = BrightnessKeyDelivery()
    private var lastHardwarePress: [Key: (page: UInt32, time: UInt64)] = [:]
    private var hardwareGeneration = 0
    private var quartzFnDown = false

    private var isFnDown: Bool {
        // A function-row event can set the Fn flag without a physical Fn press.
        hardware.isFnDown || quartzFnDown || CGEventSource.keyState(.hidSystemState, key: CGKeyCode(kVK_Function))
    }

    func handleBrightnessShortcut(_ key: Key) {
        let handled = handler?(Press(key: key, isFineStep: false, isRepeat: false, isMediaEvent: false)) ?? false
        reportBrightness(key, handled: handled, source: "Shortcut")
    }

    private func handleHardwarePress(_ key: Key, page: UInt32, time: UInt64) {
        guard !key.preservesFnCombination(isFnDown) else { return }
        let isFunctionKey = page == 0x07
        let flags = NSEvent.modifierFlags
        guard !isFunctionKey || (Self.handlesStandardKeys && flags.intersection([.command, .control]).isEmpty) else { return }
        // A keyboard may report the same press on both its consumer and vendor collections.
        if let last = lastHardwarePress[key], page != last.page, time >= last.time, time - last.time <= 4_000_000 { return }
        lastHardwarePress[key] = (page, time)
        let generation = hardwareGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.020) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.hardwareGeneration == generation, self.hardwareBrightnessState == .listening,
                      self.shouldObserveHardwareBrightness?() == true else { return }
                guard !self.brightnessDelivery.consumeDuplicate(key, source: .hardware, time: time) else { return }
                let fine = flags.isSuperset(of: [.option, .shift])
                let handled = self.handler?(Press(key: key, isFineStep: fine, isRepeat: false, isMediaEvent: true)) ?? false
                if handled {
                    self.brightnessDelivery.record(key, source: .hardware, time: time)
                }
                self.reportBrightness(key, handled: handled, source: isFunctionKey ? "HID F-key" : "HID Media")
            }
        }
    }

    private func syncHardwareBrightness() {
        let enabled = shouldObserveHardwareBrightness?() == true
        let next = hardware.sync(enabled: enabled, allowFunctionKeys: Self.handlesStandardKeys)
        if next != hardwareBrightnessState { hardwareBrightnessState = next }
    }

    private func reportBrightness(_ key: Key, handled: Bool, source: String) {
        guard key.isBrightness else { return }
        let name = key == .brightnessDown ? "F1" : "F2"
        brightnessKeyCount += 1
        let result = handled ? DeckL("已接管", "Handled") : DeckL("交由系统处理", "Passed to macOS")
        lastBrightnessKey = "\(name) · \(source) · \(result) · #\(brightnessKeyCount)"
    }

    private var taps: [CFMachPort] = []
    private var sources: [CFRunLoopSource] = []
    private var lastHandledEvent: (key: Key, down: Bool, timestamp: CGEventTimestamp)?
    private var trustTimer: Timer?
    private var handledKeys = Set<Int32>()

    init() {
        hardware.onPress = { [weak self] in self?.handleHardwarePress($0, page: $1, time: $2) }
    }

    nonisolated static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system's own "grant Accessibility" prompt.
    static func requestTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Starts now if macOS allows it. Otherwise asks once and starts by itself as soon
    /// as access is granted, with no need to restart the app.
    func start() {
        stop()
        if !Self.isTrusted { Self.requestTrust() }
        restoreTaps()
        syncHardwareBrightness()
        // Permission can be granted or revoked while running. Taps can also be
        // disabled during sleep or a long UI render, so recovery must stay active.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.restoreTaps()
                self?.syncHardwareBrightness()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        trustTimer = timer
    }

    func stop() {
        trustTimer?.invalidate()
        trustTimer = nil
        hardwareGeneration += 1
        hardware.stop()
        hardwareBrightnessState = .inactive
        brightnessDelivery = BrightnessKeyDelivery()
        lastHardwarePress.removeAll()
        removeTaps()
    }

    private func removeTaps() {
        for tap in taps {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        for source in sources { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        taps.removeAll()
        sources.removeAll()
        isActive = false
        handledKeys.removeAll()
        lastHandledEvent = nil
        quartzFnDown = false
    }

    private func restoreTaps() {
        guard Self.isTrusted else {
            if !taps.isEmpty { removeTaps() }
            return
        }
        if taps.contains(where: { !CFMachPortIsValid($0) }) { removeTaps() }
        if taps.isEmpty {
            // Capture ordinary F keys before system shortcuts, and keep a session
            // tap for media events generated later by the keyboard driver. A handled
            // event is consumed at its first tap, so it cannot change the level twice.
            for location in [CGEventTapLocation.cghidEventTap, .cgSessionEventTap] {
                createTap(at: location)
            }
        }
        for tap in taps where !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
        isActive = taps.contains { CGEvent.tapIsEnabled(tap: $0) }
    }

    private func createTap(at location: CGEventTapLocation) {
        let mask = CGEventMask(1 << 14) | CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue) | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: location,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<MediaKeyController>.fromOpaque(context).takeUnretainedValue()
                return MainActor.assumeIsolated { controller.handle(type: type, event: event) }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        taps.append(port)
        sources.append(source)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS switches a tap off if it ever runs slow, and it must be turned back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            quartzFnDown = false
            restoreTaps()
            return Unmanaged.passUnretained(event)
        }
        if type == .flagsChanged {
            if event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_Function) {
                quartzFnDown = event.flags.contains(.maskSecondaryFn)
            }
            return Unmanaged.passUnretained(event)
        }
        guard let press = Self.decode(event) else {
            return Unmanaged.passUnretained(event)
        }
        // A driver may expose the same timestamp at both event stages.
        if let last = lastHandledEvent, last.timestamp == event.timestamp,
           last.key == press.key, last.down == press.isKeyDown { return nil }
        // Key-up carries no action, but must be swallowed together with its key-down.
        if press.isKeyDown {
            if press.key.preservesFnCombination(isFnDown) {
                if !press.isRepeat { handledKeys.remove(press.key.rawValue) }
                return Unmanaged.passUnretained(event)
            }
            if press.key.isBrightness, brightnessDelivery.consumeDuplicate(press.key, source: .quartz, time: event.timestamp) {
                handledKeys.insert(press.key.rawValue)
                lastHandledEvent = (press.key, true, event.timestamp)
                return nil
            }
            let handled = handler?(Press(key: press.key, isFineStep: press.isFineStep, isRepeat: press.isRepeat,
                                         isMediaEvent: type != .keyDown)) ?? false
            if handled {
                if press.key.isBrightness {
                    brightnessDelivery.record(press.key, source: .quartz, time: event.timestamp)
                }
                handledKeys.insert(press.key.rawValue)
                lastHandledEvent = (press.key, true, event.timestamp)
            } else { handledKeys.remove(press.key.rawValue) }
            reportBrightness(press.key, handled: handled, source: type == .keyDown ? "F-key" : "Media")
            return handled ? nil : Unmanaged.passUnretained(event)
        }
        if handledKeys.remove(press.key.rawValue) != nil {
            lastHandledEvent = (press.key, false, event.timestamp)
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    private static var handlesStandardKeys: Bool {
        UserDefaults.standard.object(forKey: "keys.standardFKeys") as? Bool ?? true
    }

    static func standardBrightnessKey(keyCode: Int64, flags: CGEventFlags) -> Key? {
        guard handlesStandardKeys, flags.intersection([.maskCommand, .maskControl]).isEmpty else { return nil }
        switch Int(keyCode) {
        case kVK_F1: return .brightnessDown
        case kVK_F2: return .brightnessUp
        default: return nil
        }
    }

    static func decode(_ event: CGEvent) -> (key: Key, isKeyDown: Bool, isRepeat: Bool, isFineStep: Bool)? {
        if event.type == .keyDown || event.type == .keyUp {
            guard let key = standardBrightnessKey(keyCode: event.getIntegerValueField(.keyboardEventKeycode), flags: event.flags) else { return nil }
            return (key, event.type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) != 0, event.flags.contains([.maskAlternate, .maskShift]))
        }
        guard let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 else { return nil }
        return decodeSystemData(nsEvent.data1, modifiers: nsEvent.modifierFlags)
    }

    static func decodeSystemData(_ data: Int, modifiers: NSEvent.ModifierFlags = []) -> (key: Key, isKeyDown: Bool, isRepeat: Bool, isFineStep: Bool)? {
        let state = (data & 0x0000_FF00) >> 8
        guard state == 0x0A || state == 0x0B,
              let key = Key(rawValue: Int32((data & 0xFFFF_0000) >> 16)) else { return nil }
        return (key, state == 0x0A, (data & 0x1) == 1, modifiers.isSuperset(of: [.option, .shift]))
    }
}
