import AppKit
import AudioToolbox
import Combine
import CoreAudio
import CoreGraphics
import Foundation
import StatusDeckKit

// macOS gives HDMI and DisplayPort outputs no volume control, and many monitors
// ignore DDC volume commands too. The only way left is to change the samples: a
// Core Audio process tap captures everything the system plays and mutes the
// original, and an aggregate device plays it back to the same output, scaled.
// Public API (macOS 14.2+), no virtual driver. If this process dies the tap dies
// with it and macOS goes back to playing the original.

/// The real-time part, free of allocation and locks. Kept apart from the engine so
/// that it can be tested with ordinary buffers.
enum SoftwareVolumeMixer {
    /// The loudest sample in a buffer list.
    static func peak(of list: UnsafePointer<AudioBufferList>) -> Float {
        var peak: Float = 0
        for buffer in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list)) {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float32.self) else { continue }
            for index in 0..<(Int(buffer.mDataByteSize) / MemoryLayout<Float32>.size) {
                peak = max(peak, abs(data[index]))
            }
        }
        return peak
    }

    /// Slider position to linear gain. Loudness is logarithmic, so a straight line
    /// would put almost all of the audible change in the bottom quarter.
    static func gain(forSliderValue value: Double) -> Float {
        let clamped = Float(min(1, max(0, value)))
        return clamped * clamped
    }

    /// Writes the tap's channels to every output channel with a gain ramp from
    /// `start` to `end` across the buffer, so that moving the slider cannot click.
    ///
    /// The tap's stereo pair is always the last two input channels, because an
    /// output device with inputs of its own lists those first in the aggregate.
    static func render(
        input: UnsafePointer<AudioBufferList>,
        output: UnsafeMutablePointer<AudioBufferList>,
        from start: Float,
        to end: Float
    ) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)

        var inputChannels = 0
        for buffer in inputs { inputChannels += Int(buffer.mNumberChannels) }
        let tapChannels = min(2, inputChannels)
        let firstTapChannel = inputChannels - tapChannels

        var outputChannel = 0
        for buffer in outputs {
            guard let destination = buffer.mData?.assumingMemoryBound(to: Float32.self) else { continue }
            let channels = Int(buffer.mNumberChannels)
            guard channels > 0 else { continue }
            let frames = Int(buffer.mDataByteSize) / MemoryLayout<Float32>.size / channels

            guard tapChannels > 0 else {
                memset(destination, 0, Int(buffer.mDataByteSize))
                outputChannel += channels
                continue
            }
            let step = frames > 0 ? (end - start) / Float(frames) : 0

            for channel in 0..<channels {
                let wanted = firstTapChannel + (outputChannel + channel) % tapChannels
                var source: UnsafePointer<Float32>?
                var stride = 1
                var offset = 0
                var sourceFrames = 0
                var seen = 0
                for candidate in inputs {
                    let count = Int(candidate.mNumberChannels)
                    if count > 0, wanted < seen + count, let data = candidate.mData {
                        source = UnsafePointer(data.assumingMemoryBound(to: Float32.self))
                        stride = count
                        offset = wanted - seen
                        sourceFrames = Int(candidate.mDataByteSize) / MemoryLayout<Float32>.size / count
                        break
                    }
                    seen += count
                }
                var gain = start
                for frame in 0..<frames {
                    let sample: Float32
                    if let source, frame < sourceFrames {
                        sample = source[frame * stride + offset]
                    } else {
                        sample = 0
                    }
                    destination[frame * channels + channel] = sample * gain
                    gain += step
                }
            }
            outputChannel += channels
        }
    }
}

/// The private aggregate device is visible to this process, so it has to be told
/// apart from devices the user could actually pick.
enum SoftwareVolumeDevice {
    static let uidPrefix = "local.statusdeck.volume."

    static func isOurs(uid: String?) -> Bool {
        uid?.hasPrefix(uidPrefix) ?? false
    }
}

enum SoftwareVolumeError: Error, LocalizedError {
    case unsupportedSystem
    case system(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case .unsupportedSystem: DeckL("需要 macOS 14.2 或更高版本")
        case let .system(step, status): "\(step)失败（\(status)）"
        }
    }
}

/// One running tap, aggregate device and IO callback. Created to run, destroyed to stop.
@available(macOS 14.2, *)
final class SoftwareVolumeEngine {
    static var deviceUIDPrefix: String { SoftwareVolumeDevice.uidPrefix }

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    /// [target, current], shared with the IO thread. Aligned 32-bit reads and writes
    /// do not tear, and a read that is one buffer late only delays the ramp.
    private let gain: UnsafeMutablePointer<Float>
    /// [callbacks, loudest input sample, loudest output sample]. The peaks tell the UI
    /// whether anything is really playing, since our own IO keeps the device running.
    private let stats: UnsafeMutablePointer<Float>

    init(outputUID: String, initialGain: Float, startOverride: (() throws -> Void)? = nil) throws {
        gain = .allocate(capacity: 2)
        gain[0] = initialGain
        gain[1] = initialGain
        stats = .allocate(capacity: 3)
        stats[0] = 0
        stats[1] = 0
        stats[2] = 0
        // All stored properties are initialized here. Swift calls deinit if
        // start throws, so there must be only one owner of buffer teardown.
        if let startOverride { try startOverride() } else { try start(outputUID: outputUID) }
    }

    deinit {
        stop()
        gain.deallocate()
        stats.deallocate()
    }

    var diagnostics: (callbacks: Float, inputPeak: Float, outputPeak: Float) { (stats[0], stats[1], stats[2]) }

    /// The loudest input since the last call.
    func consumeInputPeak() -> Float {
        let peak = stats[1]
        stats[1] = 0
        return peak
    }

    func resetPeaks() {
        stats[1] = 0
        stats[2] = 0
    }

    func setGain(_ value: Float) {
        gain[0] = value
    }

    private func start(outputUID: String) throws {
        // Our own output must stay out of the tap, or it would be captured, muted and replayed.
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [try Self.ownProcessObject()])
        description.uuid = UUID()
        description.name = "MyStatus Volume"
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped

        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else { throw SoftwareVolumeError.system(DeckL("创建音频捕获"), status) }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MyStatus Volume",
            kAudioAggregateDeviceUIDKey: "\(SoftwareVolumeEngine.deviceUIDPrefix)\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString
            ]]
        ]
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
        guard status == noErr else { throw SoftwareVolumeError.system(DeckL("创建音频设备"), status) }

        let gain = gain
        let stats = stats
        let queue = DispatchQueue(label: "statusdeck.softwarevolume", qos: .userInteractive)
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, input, _, output, _ in
            let target = gain[0]
            SoftwareVolumeMixer.render(input: input, output: output, from: gain[1], to: target)
            gain[1] = target
            stats[0] += 1
            stats[1] = max(stats[1], SoftwareVolumeMixer.peak(of: input))
            stats[2] = max(stats[2], SoftwareVolumeMixer.peak(of: UnsafePointer(output)))
        }
        guard status == noErr else { throw SoftwareVolumeError.system(DeckL("注册音频回调"), status) }

        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else { throw SoftwareVolumeError.system(DeckL("启动音频"), status) }
    }

    private func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    private static func ownProcessObject() throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid = getpid()
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address,
            UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object
        )
        guard status == noErr else { throw SoftwareVolumeError.system(DeckL("识别本进程音频对象"), status) }
        return object
    }
}

/// The system-audio recording permission. Core Audio exposes no status for it, so
/// this asks TCC's private calls directly. If they ever disappear the status reads
/// unknown and the request reports success, so creating the tap prompts by itself.
enum AudioCapturePermission {
    enum Status { case authorized, denied, unknown }

    private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int32
    private typealias Request = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void

    private static let service = "kTCCServiceAudioCapture" as CFString
    private static let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_LAZY)

    static var status: Status {
        guard let handle, let symbol = dlsym(handle, "TCCAccessPreflight") else { return .unknown }
        switch unsafeBitCast(symbol, to: Preflight.self)(service, nil) {
        case 0: return .authorized
        case 1: return .denied
        default: return .unknown
        }
    }

    static func request(completion: @escaping @Sendable (Bool) -> Void) {
        guard let handle, let symbol = dlsym(handle, "TCCAccessRequest") else {
            completion(true)
            return
        }
        unsafeBitCast(symbol, to: Request.self)(service, nil) { granted in completion(granted) }
    }
}

/// Runs the engine for whichever output the user has switched software volume on for.
///
/// Building and tearing down the engine talks to the audio daemon, and creating its IO
/// callback blocks until the user answers the permission prompt if that is still open.
/// So all of it happens on a background queue, never on the main thread.
@MainActor
final class SoftwareVolumeController: ObservableObject {
    enum State: Equatable {
        case off
        case starting
        case running
        case failed(String)
        case permissionDenied
        /// The system's permission prompt is on screen.
        case waitingForPermission
    }

    @Published private(set) var state: State = .off
    @Published private(set) var value: Double
    @Published private(set) var isMuted = false
    /// Something is playing through the engine right now.
    @Published private(set) var isSignalPresent = false

    private let defaults = PluginDefaults(pluginID: "com.statusdeck.sound")
    private let permission: () -> AudioCapturePermission.Status
    private let engineQueue = DispatchQueue(label: "statusdeck.softwarevolume.control", qos: .userInitiated)
    private var engine: AnyObject?
    /// The output the engine should be on. Kept apart from the state so that a failed
    /// start is not retried by every unrelated change that asks to sync.
    private var desiredUID: String?
    /// Makes a start that finishes after a newer decision discard itself.
    private var generation = 0

    static var isSupported: Bool {
        if #available(macOS 14.2, *) { return true }
        return false
    }

    init(permission: @escaping () -> AudioCapturePermission.Status = { AudioCapturePermission.status }) {
        self.permission = permission
        // 100% is unity gain: switching this on does not change how loud anything is.
        value = defaults.double("softwareVolume", default: 1)
    }

    func isEnabled(forOutput uid: String?) -> Bool {
        guard let uid else { return false }
        return defaults.strings("softwareVolumeOutputs")?.contains(uid) ?? false
    }

    func setEnabled(_ enabled: Bool, forOutput uid: String) {
        var outputs = Set(defaults.strings("softwareVolumeOutputs") ?? [])
        if enabled { outputs.insert(uid) } else { outputs.remove(uid) }
        defaults.set(Array(outputs), forKey: "softwareVolumeOutputs")
        objectWillChange.send()
    }

    /// Makes the engine match the wanted output. Only a change of output does anything,
    /// so this is safe to call as often as things change. `nil` stops it, and sound
    /// returns to its normal path at once.
    func run(onOutput uid: String?) {
        guard uid != desiredUID else { return }
        desiredUID = uid
        teardown()
        if let uid { begin(uid: uid) }
    }

    private func begin(uid: String) {
        switch permission() {
        case .authorized:
            launch(uid: uid)
        case .denied:
            state = .permissionDenied
        case .unknown:
            // Without this answer the tap would mute the system and capture silence.
            state = .waitingForPermission
            generation += 1
            let token = generation
            AudioCapturePermission.request { [weak self] granted in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, self.generation == token else { return }
                        if granted {
                            self.launch(uid: uid)
                        } else {
                            self.state = .permissionDenied
                        }
                    }
                }
            }
        }
    }

    private func launch(uid: String) {
        guard #available(macOS 14.2, *) else {
            state = .failed(SoftwareVolumeError.unsupportedSystem.localizedDescription)
            return
        }
        generation += 1
        let token = generation
        let gain = effectiveGain
        state = .starting
        engineQueue.async { [weak self] in
            let result = Result { try SoftwareVolumeEngine(outputUID: uid, initialGain: gain) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.generation == token else {
                        // Superseded while starting. Its teardown belongs off the main thread too.
                        self?.discard(try? result.get())
                        return
                    }
                    switch result {
                    case let .success(engine):
                        self.engine = engine
                        self.state = .running
                        // The slider may have moved while this was starting.
                        self.applyGain()
                    case let .failure(error):
                        self.state = .failed(error.localizedDescription)
                    }
                }
            }
        }
    }

    private func teardown() {
        generation += 1
        discard(engine)
        engine = nil
        state = .off
        isSignalPresent = false
    }

    private func discard(_ old: AnyObject?) {
        guard let old else { return }
        engineQueue.async { withExtendedLifetime(old) {} }
    }

    func stop() {
        run(onOutput: nil)
    }

    /// Rebuilds the audio path. An aggregate device does not survive its output going
    /// away: without this, unplugging a monitor or waking from sleep would leave the
    /// system muted by the tap with nothing playing the sound back.
    func restartIfRunning() {
        guard state == .running, let uid = desiredUID else { return }
        teardown()
        launch(uid: uid)
    }

    /// Called about once a second while someone is looking.
    func pollSignal() {
        // Permission granted in System Settings since it was refused.
        if state == .permissionDenied, permission() == .authorized, let uid = desiredUID {
            launch(uid: uid)
        }
        guard #available(macOS 14.2, *), let engine = engine as? SoftwareVolumeEngine else {
            if isSignalPresent { isSignalPresent = false }
            return
        }
        let present = engine.consumeInputPeak() > 0.0005
        if present != isSignalPresent { isSignalPresent = present }
    }

    func setValue(_ newValue: Double) {
        value = min(1, max(0, newValue))
        defaults.set(value, forKey: "softwareVolume")
        if value > 0 { isMuted = false }
        applyGain()
    }

    func toggleMute() {
        isMuted.toggle()
        applyGain()
    }

    private var effectiveGain: Float {
        isMuted ? 0 : SoftwareVolumeMixer.gain(forSliderValue: value)
    }

    private func applyGain() {
        if #available(macOS 14.2, *) {
            (engine as? SoftwareVolumeEngine)?.setGain(effectiveGain)
        }
    }
}

/// How the current output's volume can be changed.
enum VolumeRoute: Equatable {
    /// macOS can set it directly.
    case hardware
    case ddc(CGDirectDisplayID)
    case software
    /// Nothing is active yet, but software volume could be switched on.
    case softwareAvailable
    case unavailable
}

enum VolumeRoutePreference: String, CaseIterable {
    case automatic
    case ddc
    case software

    var title: String {
        switch self {
        case .automatic: DeckL("自动")
        case .ddc: DeckL("优先 DDC")
        case .software: DeckL("优先软件音量")
        }
    }
}

enum VolumeRouter {
    static func route(
        hasHardwareVolume: Bool,
        ddcDisplay: DisplayState?,
        softwareEnabled: Bool,
        softwareSupported: Bool,
        preference: VolumeRoutePreference
    ) -> VolumeRoute {
        if hasHardwareVolume { return .hardware }
        let usableDDC = ddcDisplay.flatMap { $0.volume != nil && !$0.ignoresVolumeWrites ? $0.id : nil }

        switch preference {
        case .ddc:
            if let usableDDC { return .ddc(usableDDC) }
        case .software:
            break
        case .automatic:
            // A choice the user already made wins over a DDC volume that may not work.
            if !softwareEnabled, let usableDDC { return .ddc(usableDDC) }
        }
        guard softwareSupported else { return .unavailable }
        return softwareEnabled ? .software : .softwareAvailable
    }
}

/// One volume for everything that shows or changes it, whichever way it gets there.
@MainActor
final class SoundModel: ObservableObject {
    let audio: AudioController
    let displays: DisplayController
    let software: SoftwareVolumeController

    private let defaults = PluginDefaults(pluginID: "com.statusdeck.sound")
    private var cancellables: Set<AnyCancellable> = []
    private var wakeObserver: NSObjectProtocol?
    private var restartWork: DispatchWorkItem?
    /// Software volume only runs while the sound plugin is on.
    var managesEngine = false {
        didSet { syncEngine() }
    }

    init(audio: AudioController, displays: DisplayController, software: SoftwareVolumeController) {
        self.audio = audio
        self.displays = displays
        self.software = software
        for publisher in [
            audio.objectWillChange.eraseToAnyPublisher(),
            displays.objectWillChange.eraseToAnyPublisher(),
            software.objectWillChange.eraseToAnyPublisher()
        ] {
            publisher
                .sink { [weak self] in
                    self?.objectWillChange.send()
                    // Published values change just after this fires.
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { self?.syncEngine() }
                    }
                }
                .store(in: &cancellables)
        }
        audio.$outputDeviceSet
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.scheduleEngineRestart() }
            .store(in: &cancellables)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleEngineRestart() }
        }
    }

    /// Devices settle over a second or so after a change.
    private func scheduleEngineRestart() {
        restartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.software.restartIfRunning() }
        }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    var preference: VolumeRoutePreference {
        get { VolumeRoutePreference(rawValue: defaults.string("volumeRoute") ?? "") ?? .automatic }
        set {
            defaults.set(newValue.rawValue, forKey: "volumeRoute")
            objectWillChange.send()
            syncEngine()
        }
    }

    var currentOutputDisplay: DisplayState? {
        displays.display(matchingAudioDevice: audio.currentOutput?.name)
    }

    var route: VolumeRoute {
        VolumeRouter.route(
            hasHardwareVolume: audio.volume != nil,
            ddcDisplay: currentOutputDisplay,
            softwareEnabled: software.isEnabled(forOutput: audio.currentOutput?.uid),
            softwareSupported: SoftwareVolumeController.isSupported,
            preference: preference
        )
    }

    /// The monitor said yes to a volume command and then did nothing.
    var displayIgnoredDDC: Bool { currentOutputDisplay?.ignoresVolumeWrites ?? false }

    /// What the slider shows. Software volume is offered by showing its slider: moving
    /// it is what switches it on, with nothing to find or read first.
    var volume: Double? {
        switch route {
        case .hardware: return audio.volume
        case let .ddc(id): return displays.displays.first { $0.id == id }?.volume
        case .software, .softwareAvailable: return software.value
        case .unavailable: return nil
        }
    }

    /// Whether sound is coming out. With software volume our own IO keeps the device
    /// "running" all the time, so that case looks at the audio itself.
    var isPlaying: Bool {
        route == .software && software.state == .running ? software.isSignalPresent : audio.isOutputRunning
    }

    var isMuted: Bool {
        switch route {
        case .hardware: audio.isMuted
        case let .ddc(id): displays.displays.first { $0.id == id }?.isMuted ?? false
        case .software: software.isMuted
        case .softwareAvailable, .unavailable: false
        }
    }

    /// Software volume is available but has not been switched on for this output.
    var isSoftwareVolumeOffered: Bool { route == .softwareAvailable }

    func setVolume(_ value: Double) {
        switch route {
        case .hardware: audio.setVolume(value)
        case let .ddc(id): displays.setVolume(value, for: id)
        case .software: software.setValue(value)
        case .softwareAvailable:
            software.setValue(value)
            enableSoftwareVolumeForCurrentOutput()
        case .unavailable: break
        }
    }

    func toggleMute() {
        switch route {
        case .hardware: audio.toggleMute()
        case let .ddc(id): displays.toggleMute(for: id)
        case .software: software.toggleMute()
        case .softwareAvailable:
            software.toggleMute()
            enableSoftwareVolumeForCurrentOutput()
        case .unavailable: break
        }
    }

    func enableSoftwareVolumeForCurrentOutput() {
        guard let uid = audio.currentOutput?.uid else { return }
        software.setEnabled(true, forOutput: uid)
        syncEngine()
    }

    func disableSoftwareVolumeForCurrentOutput() {
        guard let uid = audio.currentOutput?.uid else { return }
        software.setEnabled(false, forOutput: uid)
        syncEngine()
    }

    /// Scrolling over a menu bar icon, or a volume key.
    func nudge(by delta: Double) -> Double? {
        guard let current = volume else { return nil }
        let next = min(1, max(0, current + delta))
        setVolume(next)
        return next
    }

    private func syncEngine() {
        let wanted = managesEngine && route == .software ? audio.currentOutput?.uid : nil
        software.run(onOutput: wanted)
    }
}
