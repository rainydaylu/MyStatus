import AppKit
import Combine
import CoreGraphics
import CPrivateAPI
import Foundation
import StatusDeckKit

// External displays go through MonitorControl's Arm64DDC, Apple displays through
// DisplayServices, and anything that answers neither gets a dimming shade.

struct DisplayState: Identifiable, Equatable {
    enum Kind: Equatable {
        /// Built-in and Apple displays, set through DisplayServices.
        case apple
        /// A monitor reachable over DDC/CI.
        case ddc
        /// No hardware control: a black overlay window dims the picture instead.
        case software
    }

    let id: CGDirectDisplayID
    var name: String
    var isBuiltIn: Bool
    var kind: Kind
    var brightness: Double
    var contrast: Double?
    var volume: Double?
    var isMuted = false
    /// DDC accepted no read, so this value is the last one written, not a measurement.
    var isBrightnessAssumed = false
    /// The monitor acknowledged a volume write and then did not change: its speakers
    /// or line-out cannot be driven over DDC, whatever it reports when asked.
    var ignoresVolumeWrites = false
    var modeDescription: String?

    var kindLabel: String {
        switch kind {
        case .apple: isBuiltIn ? DeckL("内建") : "Apple"
        case .ddc: "DDC"
        case .software: DeckL("软件调暗")
        }
    }
}

/// Whether a DDC write landed, judged from the value read back afterwards.
enum DDCWriteCheck {
    /// `nil` means the reading says nothing: no answer, or too small a move to tell
    /// a real change from a monitor that rounds to coarse steps.
    static func tookEffect(before: UInt16, written: UInt16, readBack: UInt16?) -> Bool? {
        guard let readBack else { return nil }
        let intended = abs(Int(written) - Int(before))
        guard intended >= 3 else { return nil }
        return abs(Int(readBack) - Int(written)) < abs(Int(readBack) - Int(before))
    }
}

/// Serial access to the DDC bus. Reads are slow and writes must not overlap, so
/// everything runs on one queue and a dragged slider only ever sends its latest value.
final class DDCWorker {
    struct Key: Hashable {
        let display: CGDirectDisplayID
        let command: UInt8
    }

    struct Reading {
        var brightness: Double?
        var contrast: Double?
        var volume: Double?
        var isMuted = false
        /// What a trial write showed, if one was asked for and told us anything.
        var volumeWorks: Bool?
    }

    private let queue = DispatchQueue(label: "statusdeck.ddc", qos: .userInitiated)
    private var services: [CGDirectDisplayID: IOAVService] = [:]
    private var maximums: [Key: UInt16] = [:]
    private struct PendingWrite {
        let fraction: Double
        let brightnessRevision: UInt64?
    }
    private var pendingWrites: [Key: PendingWrite] = [:]
    private var isFlushing = false
    private var volumeBaseline: [CGDirectDisplayID: UInt16] = [:]
    private var volumeCheck: DispatchWorkItem?
    private var brightnessChecks: [CGDirectDisplayID: DispatchWorkItem] = [:]
    private var brightnessBaseline: [CGDirectDisplayID: UInt16] = [:]

    /// nil verdict means the monitor accepted the write but cannot confirm a read.
    var onBrightnessCheck: ((CGDirectDisplayID, UInt64, Double, Double?, Bool?) -> Void)?

    /// Called on the main queue with what a volume write turned out to do.
    var onVolumeCheck: ((CGDirectDisplayID, Bool) -> Void)?

    /// Calls back on the main queue with one entry per display that has a DDC service.
    func refresh(
        displayIDs: [CGDirectDisplayID],
        probeVolumeOn probed: Set<CGDirectDisplayID> = [],
        completion: @escaping ([CGDirectDisplayID: Reading]) -> Void
    ) {
        queue.async { [self] in
            services.removeAll()
            var readings: [CGDirectDisplayID: Reading] = [:]
            #if arch(arm64)
            for match in Arm64DDC.getServiceMatches(displayIDs: displayIDs) where match.service != nil && !match.dummy {
                services[match.displayID] = match.service
            }
            #endif
            for (display, service) in services {
                var reading = Reading()
                reading.brightness = read(service, display, command: Command.luminance.rawValue, attempts: 3)
                if let brightness = reading.brightness {
                    let maximum = maximums[Key(display: display, command: Command.luminance.rawValue)] ?? 100
                    brightnessBaseline[display] = UInt16((brightness * Double(maximum)).rounded())
                }
                reading.contrast = read(service, display, command: Command.contrast.rawValue, attempts: 1)
                reading.volume = read(service, display, command: Command.audioSpeakerVolume.rawValue, attempts: 1)
                if let volume = reading.volume {
                    let maximum = maximums[Key(display: display, command: Command.audioSpeakerVolume.rawValue)] ?? 100
                    volumeBaseline[display] = UInt16((volume * Double(maximum)).rounded())
                }
                if reading.volume != nil,
                   let mute = Arm64DDC.read(service: service, command: Command.audioMuteScreenBlank.rawValue, numOfRetryAttemps: 1) {
                    reading.isMuted = mute.current == 1
                }
                if reading.volume != nil, probed.contains(display) {
                    reading.volumeWorks = probeVolume(service)
                }
                readings[display] = reading
            }
            DispatchQueue.main.async { completion(readings) }
        }
    }

    /// Some monitors acknowledge a volume write and change nothing, which no read can
    /// reveal. So this moves the volume a few steps, reads it back and restores it.
    /// It runs once per monitor, as the answer is remembered.
    private func probeVolume(_ service: IOAVService) -> Bool? {
        let command = Command.audioSpeakerVolume.rawValue
        guard let before = Arm64DDC.read(service: service, command: command, numOfRetryAttemps: 2), before.max > 0 else { return nil }
        let step = max(4, before.max / 25)
        let target = before.current >= step ? before.current - step : before.current + step
        _ = Arm64DDC.write(service: service, command: command, value: target)
        usleep(400_000)
        let readBack = Arm64DDC.read(service: service, command: command, numOfRetryAttemps: 2)?.current
        _ = Arm64DDC.write(service: service, command: command, value: before.current)
        return DDCWriteCheck.tookEffect(before: before.current, written: target, readBack: readBack)
    }

    private func read(_ service: IOAVService, _ display: CGDirectDisplayID, command: UInt8, attempts: UInt8) -> Double? {
        guard let values = Arm64DDC.read(service: service, command: command, numOfRetryAttemps: attempts),
              values.max > 0 else {
            return nil
        }
        maximums[Key(display: display, command: command)] = values.max
        return min(1, Double(values.current) / Double(values.max))
    }

    func write(display: CGDirectDisplayID, command: UInt8, fraction: Double, brightnessRevision: UInt64? = nil) {
        queue.async { [self] in
            pendingWrites[Key(display: display, command: command)] = PendingWrite(fraction: fraction, brightnessRevision: brightnessRevision)
            guard !isFlushing else { return }
            isFlushing = true
            queue.async { [self] in flush() }
        }
    }

    func writeRaw(display: CGDirectDisplayID, command: UInt8, value: UInt16) {
        queue.async { [self] in
            guard let service = services[display] else { return }
            _ = Arm64DDC.write(service: service, command: command, value: value)
        }
    }

    /// Runs once a drag has settled. Monitors need a moment before a read reflects a write.
    private func scheduleVolumeCheck(display: CGDirectDisplayID, written: UInt16) {
        volumeCheck?.cancel()
        let work = DispatchWorkItem { [self] in
            guard let service = services[display], let before = volumeBaseline[display] else { return }
            let readBack = Arm64DDC.read(service: service, command: Command.audioSpeakerVolume.rawValue, numOfRetryAttemps: 2)?.current
            guard let result = DDCWriteCheck.tookEffect(before: before, written: written, readBack: readBack) else { return }
            if result, let readBack { volumeBaseline[display] = readBack }
            DispatchQueue.main.async { [onVolumeCheck] in onVolumeCheck?(display, result) }
        }
        volumeCheck = work
        queue.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func reportBrightness(_ display: CGDirectDisplayID, revision: UInt64, fraction: Double, readBack: Double?, works: Bool?) {
        DispatchQueue.main.async { [onBrightnessCheck] in onBrightnessCheck?(display, revision, fraction, readBack, works) }
    }

    private func scheduleBrightnessCheck(display: CGDirectDisplayID, revision: UInt64, fraction: Double, written: UInt16, maximum: UInt16) {
        let work = DispatchWorkItem { [self] in
            guard let service = services[display] else {
                reportBrightness(display, revision: revision, fraction: fraction, readBack: nil, works: false)
                return
            }
            let readBack = Arm64DDC.read(service: service, command: Command.luminance.rawValue, numOfRetryAttemps: 2)?.current
            let works = brightnessBaseline[display].flatMap {
                DDCWriteCheck.tookEffect(before: $0, written: written, readBack: readBack)
            }
            if let readBack { brightnessBaseline[display] = readBack }
            reportBrightness(display, revision: revision, fraction: fraction, readBack: readBack.map { Double($0) / Double(maximum) }, works: works)
        }
        brightnessChecks[display] = work
        queue.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    private func flush() {
        // Runs until nothing new arrived while the previous batch was on the wire.
        let batch = pendingWrites
        pendingWrites.removeAll()
        for (key, write) in batch {
            let fraction = write.fraction
            if write.brightnessRevision != nil { brightnessChecks[key.display]?.cancel() }
            guard let service = services[key.display] else {
                if let revision = write.brightnessRevision {
                    reportBrightness(key.display, revision: revision, fraction: fraction, readBack: nil, works: false)
                }
                continue
            }
            let maximum = maximums[key] ?? 100
            let value = UInt16((min(1, max(0, fraction)) * Double(maximum)).rounded())
            let accepted = Arm64DDC.write(service: service, command: key.command, value: value)
            if let revision = write.brightnessRevision {
                if accepted {
                    scheduleBrightnessCheck(display: key.display, revision: revision, fraction: fraction, written: value, maximum: maximum)
                } else {
                    reportBrightness(key.display, revision: revision, fraction: fraction, readBack: nil, works: false)
                }
            }
            if key.command == Command.audioSpeakerVolume.rawValue {
                scheduleVolumeCheck(display: key.display, written: value)
            }
        }
        if pendingWrites.isEmpty {
            isFlushing = false
        } else {
            queue.async { [self] in flush() }
        }
    }
}

enum DisplayServicesAPI {
    private typealias Get = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Set = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let getSymbol: Get? = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: Get.self) }
    private static let setSymbol: Set? = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: Set.self) }

    static func brightness(of display: CGDirectDisplayID) -> Double? {
        var value: Float = -1
        guard let getSymbol, getSymbol(display, &value) == 0, value >= 0 else { return nil }
        return Double(value)
    }

    static func setBrightness(_ value: Double, of display: CGDirectDisplayID) -> Bool {
        setSymbol?(display, Float(min(1, max(0, value)))) == 0
    }
}

@MainActor
final class DisplayController: ObservableObject {
    @Published private(set) var displays: [DisplayState] = []
    @Published private(set) var isReading = false
    @Published private(set) var brightnessStatus: String?
    /// Keeps the built-in slider honest when the keyboard or Control Center changes it.
    private(set) lazy var poller = IntervalPoller { [weak self] in self?.pollAppleBrightness() }

    private let worker = DDCWorker()
    private var shades: [CGDirectDisplayID: NSWindow] = [:]
    private var observers: [NSObjectProtocol] = []
    private var lastRead = Date.distantPast
    private var reloadWork: DispatchWorkItem?
    private var reloadID = UUID()
    private var ddcBrightnessFailures = Set<CGDirectDisplayID>()
    private var brightnessChanges: [CGDirectDisplayID: UInt64] = [:]
    private var pendingBrightness: [CGDirectDisplayID: UInt64] = [:]

    /// A shade never goes fully black, so the screen stays readable enough to undo it.
    private static let maximumShade = 0.9

    init() {
        worker.onBrightnessCheck = { [weak self] id, revision, requested, readBack, works in
            MainActor.assumeIsolated { self?.recordBrightnessCheck(id, revision: revision, requested: requested, readBack: readBack, works: works) }
        }
        worker.onVolumeCheck = { [weak self] display, tookEffect in
            MainActor.assumeIsolated { self?.recordVolumeCheck(display, tookEffect: tookEffect) }
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleReload(after: 1.5) }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // The AV services behind DDC are recreated across sleep and take a moment to return.
            MainActor.assumeIsolated { self?.scheduleReload(after: 3) }
        })
    }

    private func scheduleReload(after delay: TimeInterval) {
        reloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.reload() }
        }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Removes dimming overlays, as nothing would be left to lift them.
    func removeShades() {
        for window in shades.values { window.orderOut(nil) }
        shades.removeAll()
    }

    /// Re-reads monitors the panel is about to show, unless that just happened.
    func refreshIfStale(maximumAge: TimeInterval = 60) {
        if Date().timeIntervalSince(lastRead) > maximumAge { reload() }
    }

    func reload() {
        lastRead = Date()
        let reloadID = UUID()
        self.reloadID = reloadID
        let screens = NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, NSScreen)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (CGDirectDisplayID(number.uint32Value), screen)
        }

        var next = screens.map { id, screen -> DisplayState in
            let previous = displays.first { $0.id == id }
            let isApple = Self.isAppleDisplay(id)
            return DisplayState(
                id: id,
                name: screen.localizedName,
                isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                kind: isApple ? .apple : (previous?.kind ?? .ddc),
                brightness: isApple ? (DisplayServicesAPI.brightness(of: id) ?? 1) : (previous?.brightness ?? savedBrightness(id) ?? 1),
                contrast: previous?.contrast,
                volume: previous?.volume,
                isMuted: previous?.isMuted ?? false,
                isBrightnessAssumed: previous?.isBrightnessAssumed ?? false,
                modeDescription: Self.modeDescription(id)
            )
        }
        next.sort { lhs, rhs in lhs.isBuiltIn != rhs.isBuiltIn ? lhs.isBuiltIn : lhs.name < rhs.name }
        displays = next
        ddcBrightnessFailures.formIntersection(next.map(\.id))
        pendingBrightness = pendingBrightness.filter { id, _ in next.contains { $0.id == id && $0.kind == .ddc } }

        // Windows on a monitor that has gone away would otherwise linger.
        for id in shades.keys where !next.contains(where: { $0.id == id }) {
            shades.removeValue(forKey: id)?.orderOut(nil)
        }

        let external = next.filter { $0.kind != .apple }.map(\.id)
        isReading = !external.isEmpty
        guard !external.isEmpty else { return }
        let before = brightnessChanges
        let writing = Set(pendingBrightness.keys)
        let unprobed = Set(external.filter { UserDefaults.standard.object(forKey: volumeIgnoredKey($0)) == nil })
        worker.refresh(displayIDs: external, probeVolumeOn: unprobed) { [weak self] readings in
            MainActor.assumeIsolated {
                guard let self, self.reloadID == reloadID else { return }
                self.apply(readings, external: external, before: before, writing: writing)
            }
        }
    }

    private func apply(_ readings: [CGDirectDisplayID: DDCWorker.Reading], external: [CGDirectDisplayID],
                       before: [CGDirectDisplayID: UInt64], writing: Set<CGDirectDisplayID>) {
        isReading = false
        displays = displays.map { display in
            guard external.contains(display.id) else { return display }
            var updated = display
            let reading = readings[display.id]
            updated.contrast = reading?.contrast
            if let works = reading?.volumeWorks {
                UserDefaults.standard.set(!works, forKey: volumeIgnoredKey(display.id))
            }
            updated.ignoresVolumeWrites = volumeIsIgnored(display.id)
            updated.volume = updated.ignoresVolumeWrites ? nil : reading?.volume
            updated.isMuted = reading?.isMuted ?? false
            let preserveBrightness = writing.contains(display.id) || brightnessChanges[display.id] != before[display.id]
            if softwarePreferred(for: display.id) || ddcBrightnessFailures.contains(display.id) || reading == nil {
                updated.kind = .software
                updated.isBrightnessAssumed = false
                if !preserveBrightness { updated.brightness = savedBrightness(display.id) ?? 1 }
                applyShade(for: display.id, brightness: updated.brightness)
            } else {
                shades.removeValue(forKey: display.id)?.orderOut(nil)
                updated.kind = .ddc
                updated.isBrightnessAssumed = reading?.brightness == nil
                if !preserveBrightness { updated.brightness = reading?.brightness ?? savedBrightness(display.id) ?? display.brightness }
            }
            return updated
        }
    }

    func softwarePreferred(for id: CGDirectDisplayID) -> Bool {
        UserDefaults.standard.bool(forKey: brightnessKey(id) + ".preferSoftware")
    }

    func setSoftwarePreferred(_ enabled: Bool, for id: CGDirectDisplayID) {
        guard let index = displays.firstIndex(where: { $0.id == id }), displays[index].kind != .apple else { return }
        UserDefaults.standard.set(enabled, forKey: brightnessKey(id) + ".preferSoftware")
        ddcBrightnessFailures.remove(id)
        if enabled {
            displays[index].kind = .software
            displays[index].isBrightnessAssumed = false
            applyShade(for: id, brightness: displays[index].brightness)
        }
        reload()
    }

    func retryBrightnessHardware() {
        ddcBrightnessFailures.removeAll()
        reload()
    }

    private func recordBrightnessCheck(_ id: CGDirectDisplayID, revision: UInt64, requested: Double, readBack: Double?, works: Bool?) {
        guard pendingBrightness[id] == revision else { return }
        pendingBrightness.removeValue(forKey: id)
        guard let index = displays.firstIndex(where: { $0.id == id }), displays[index].kind == .ddc else { return }
        if works == false {
            // A bus write may succeed even when DDC/CI is disabled in the monitor.
            // Use the existing dimming path instead of moving a powerless slider.
            ddcBrightnessFailures.insert(id)
            displays[index].kind = .software
            displays[index].isBrightnessAssumed = false
            applyShade(for: id, brightness: requested)
            brightnessStatus = DeckL("显示器未响应 DDC，已改用软件调暗。", "The display did not respond to DDC; using software dimming.")
        } else if let readBack {
            displays[index].brightness = min(1, max(0, readBack))
            displays[index].isBrightnessAssumed = false
            brightnessStatus = DeckL("显示器已确认亮度变化。", "The display confirmed the brightness level.")
        } else {
            displays[index].isBrightnessAssumed = true
            brightnessStatus = DeckL("DDC 指令已发送，显示器没有返回读数。", "DDC command sent; the display returned no reading.")
        }
    }

    private func recordVolumeCheck(_ id: CGDirectDisplayID, tookEffect: Bool) {
        UserDefaults.standard.set(!tookEffect, forKey: volumeIgnoredKey(id))
        guard let index = displays.firstIndex(where: { $0.id == id }) else { return }
        displays[index].ignoresVolumeWrites = !tookEffect
        if !tookEffect { displays[index].volume = nil }
    }

    /// Forgets a verdict, for a monitor whose firmware or connection has changed.
    func resetVolumeCheck() {
        for display in displays { UserDefaults.standard.removeObject(forKey: volumeIgnoredKey(display.id)) }
        lastRead = .distantPast
        reload()
    }

    private func volumeIgnoredKey(_ id: CGDirectDisplayID) -> String {
        "ddcVolumeIgnored.\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
    }

    private func volumeIsIgnored(_ id: CGDirectDisplayID) -> Bool {
        UserDefaults.standard.bool(forKey: volumeIgnoredKey(id))
    }

    func pollAppleBrightness() {
        for index in displays.indices where displays[index].kind == .apple {
            if let value = DisplayServicesAPI.brightness(of: displays[index].id),
               abs(value - displays[index].brightness) > 0.005 {
                displays[index].brightness = value
            }
        }
    }

    func brightnessKeyTarget() -> DisplayState? {
        let pointer = displayUnderPointer()
        let preferExternal = UserDefaults.standard.object(forKey: "keys.preferExternal") as? Bool ?? true
        if !preferExternal { return pointer }
        if let pointer, pointer.kind != .apple { return pointer }
        return displays.first { !$0.isBuiltIn && $0.kind != .apple } ?? pointer
    }

    @discardableResult
    func setBrightness(_ value: Double, for id: CGDirectDisplayID) -> Bool {
        guard let index = displays.firstIndex(where: { $0.id == id }) else { return false }
        let clamped = min(1, max(0, value))
        let revision = (brightnessChanges[id] ?? 0) &+ 1
        brightnessChanges[id] = revision
        let previous = displays[index].brightness
        displays[index].brightness = clamped
        switch displays[index].kind {
        case .apple:
            if DisplayServicesAPI.setBrightness(clamped, of: id) {
                brightnessStatus = DeckL("通过系统调整亮度。", "Brightness adjusted through macOS.")
            } else {
                displays[index].brightness = DisplayServicesAPI.brightness(of: id) ?? previous
                brightnessStatus = DeckL("系统拒绝了这次亮度调整。", "macOS rejected this brightness change.")
                return false
            }
        case .ddc:
            brightnessStatus = DeckL("正在等待显示器确认…", "Waiting for the display…")
            pendingBrightness[id] = revision
            worker.write(display: id, command: Command.luminance.rawValue, fraction: clamped, brightnessRevision: revision)
            saveBrightness(clamped, for: id)
        case .software:
            brightnessStatus = DeckL("正在使用软件调暗。", "Using software dimming.")
            applyShade(for: id, brightness: clamped)
            saveBrightness(clamped, for: id)
        }
        return true
    }

    func setContrast(_ value: Double, for id: CGDirectDisplayID) {
        guard let index = displays.firstIndex(where: { $0.id == id }) else { return }
        let clamped = min(1, max(0, value))
        displays[index].contrast = clamped
        worker.write(display: id, command: Command.contrast.rawValue, fraction: clamped)
    }

    func setVolume(_ value: Double, for id: CGDirectDisplayID) {
        guard let index = displays.firstIndex(where: { $0.id == id }) else { return }
        let clamped = min(1, max(0, value))
        displays[index].volume = clamped
        worker.write(display: id, command: Command.audioSpeakerVolume.rawValue, fraction: clamped)
    }

    func toggleMute(for id: CGDirectDisplayID) {
        guard let index = displays.firstIndex(where: { $0.id == id }) else { return }
        displays[index].isMuted.toggle()
        // VCP 0x8D: 1 mutes, 2 unmutes.
        worker.writeRaw(display: id, command: Command.audioMuteScreenBlank.rawValue, value: displays[index].isMuted ? 1 : 2)
    }

    /// The display the keyboard's brightness keys should act on: the one under the pointer.
    /// Nil when the screen is not in the list yet, as just after a monitor was plugged
    /// in or removed. Guessing could send a key meant for the built-in screen elsewhere.
    func displayUnderPointer() -> DisplayState? {
        let location = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) } ?? NSScreen.main
        guard let number = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return displays.first { $0.id == CGDirectDisplayID(number.uint32Value) }
    }

    /// MonitorControl matches a display's speakers to a CoreAudio device by name.
    func display(matchingAudioDevice name: String?) -> DisplayState? {
        guard let name else { return nil }
        let wanted = Self.normalized(name)
        return displays.first { Self.normalized($0.name) == wanted }
    }

    nonisolated static func normalized(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    // MARK: - Shade

    private func applyShade(for id: CGDirectDisplayID, brightness: Double) {
        let alpha = (1 - brightness) * Self.maximumShade
        guard alpha > 0.001 else {
            shades.removeValue(forKey: id)?.orderOut(nil)
            return
        }
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }) else { return }

        let window = shades[id] ?? {
            let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.backgroundColor = .black
            window.isOpaque = false
            window.ignoresMouseEvents = true
            window.hasShadow = false
            window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            window.collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
            shades[id] = window
            return window
        }()
        window.setFrame(screen.frame, display: false)
        window.alphaValue = alpha
        window.orderFrontRegardless()
    }

    // MARK: - Persistence

    private func brightnessKey(_ id: CGDirectDisplayID) -> String {
        "brightness.\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
    }

    private func savedBrightness(_ id: CGDirectDisplayID) -> Double? {
        UserDefaults.standard.object(forKey: brightnessKey(id)) as? Double
    }

    private func saveBrightness(_ value: Double, for id: CGDirectDisplayID) {
        UserDefaults.standard.set(value, forKey: brightnessKey(id))
    }

    // MARK: - Facts

    /// 1552 is Apple's EDID vendor ID. DisplayServices alone is not enough: on
    /// recent macOS it also answers for third-party monitors with HDR switched on.
    private static func isAppleDisplay(_ id: CGDirectDisplayID) -> Bool {
        CGDisplayIsBuiltin(id) != 0 || CGDisplayVendorNumber(id) == 1552
    }

    private static func modeDescription(_ id: CGDirectDisplayID) -> String? {
        guard let mode = CGDisplayCopyDisplayMode(id) else { return nil }
        let rate = mode.refreshRate > 0 ? String(format: " @ %.0f Hz", mode.refreshRate) : ""
        return "\(mode.width) × \(mode.height)\(rate)"
    }
}
