import Combine
import CoreAudio
import Foundation

struct AudioInputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let isCurrent: Bool
    var isVirtual = false
}

/// Output goes through Status Trio's CoreAudioOutputController. Input only needs
/// listing, selecting and a volume, which this small reader covers.
enum CoreAudioInputReader {
    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func currentDeviceID() -> AudioDeviceID? {
        var property = address(kAudioHardwarePropertyDefaultInputDevice)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(systemObject, &property, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else {
            return nil
        }
        return device
    }

    static func devices() -> [AudioInputDevice] {
        var property = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &property, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(systemObject, &property, 0, nil, &size, &ids) == noErr else { return [] }

        let current = currentDeviceID()
        return ids.compactMap { id -> AudioInputDevice? in
            guard hasInputStreams(id), !isHidden(id), let name = name(of: id), !SoftwareVolumeDevice.isOurs(uid: uid(of: id)) else { return nil }
            return AudioInputDevice(id: id, name: name, isCurrent: id == current, isVirtual: isVirtual(id))
        }
        .sorted { $0.isCurrent != $1.isCurrent ? $0.isCurrent : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Loopback drivers and app-made devices, as opposed to hardware.
    private static func isVirtual(_ id: AudioDeviceID) -> Bool {
        var property = address(kAudioDevicePropertyTransportType)
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &property, 0, nil, &size, &transport) == noErr else { return false }
        return [kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate].contains(transport)
    }

    private static func hasInputStreams(_ id: AudioDeviceID) -> Bool {
        var property = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &property, 0, nil, &size) == noErr
            && size >= UInt32(MemoryLayout<AudioStreamID>.size)
    }

    private static func isHidden(_ id: AudioDeviceID) -> Bool {
        var property = address(kAudioDevicePropertyIsHidden)
        guard AudioObjectHasProperty(id, &property) else { return false }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &property, 0, nil, &size, &value) == noErr && value != 0
    }

    private static func uid(of id: AudioDeviceID) -> String? {
        var property = address(kAudioDevicePropertyDeviceUID)
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &property, 0, nil, &size, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }

    private static func name(of id: AudioDeviceID) -> String? {
        var property = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &property, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    @discardableResult
    static func select(_ id: AudioDeviceID) -> Bool {
        var property = address(kAudioHardwarePropertyDefaultInputDevice)
        var device = id
        return AudioObjectSetPropertyData(systemObject, &property, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &device) == noErr
    }

    /// The main element, then the first channels, because many microphones only
    /// publish a volume per channel.
    private static func volumeElements(for id: AudioDeviceID) -> [AudioObjectPropertyElement] {
        [kAudioObjectPropertyElementMain, 1, 2].filter { element in
            var property = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: element
            )
            return AudioObjectHasProperty(id, &property)
        }
    }

    static func volume(of id: AudioDeviceID) -> Double? {
        guard let element = volumeElements(for: id).first else { return nil }
        var property = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: element
        )
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &property, 0, nil, &size, &value) == noErr else { return nil }
        return Double(value)
    }

    static func setVolume(_ value: Double, of id: AudioDeviceID) {
        var scalar = Float32(min(1, max(0, value)))
        for element in volumeElements(for: id) {
            var property = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: element
            )
            AudioObjectSetPropertyData(id, &property, 0, nil, UInt32(MemoryLayout<Float32>.size), &scalar)
        }
    }
}

@MainActor
final class AudioController: ObservableObject {
    @Published private(set) var outputs: [AudioOutputDevice] = []
    @Published private(set) var inputs: [AudioInputDevice] = []
    /// `nil` when the device has no software volume, as with most HDMI/DP audio.
    @Published private(set) var volume: Double?
    @Published private(set) var isMuted = false
    @Published private(set) var inputVolume: Double?
    /// Some app is playing through the current output.
    @Published private(set) var isOutputRunning = false
    /// The output devices that exist. Changes when one is plugged in or removed.
    @Published private(set) var outputDeviceSet: Set<String> = []
    /// Volume has no change notification that works across every driver, so
    /// whoever shows it asks for polling at the rate it needs.
    private(set) lazy var poller = IntervalPoller { [weak self] in self?.pollLevels() }

    private let output = CoreAudioOutputController()

    var currentOutput: AudioOutputDevice? { outputs.first(where: \.isCurrent) }

    init() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice] {
            var property = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectAddPropertyListenerBlock(system, &property, DispatchQueue.main) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.refreshDevices() }
            }
        }
        refreshDevices()
    }

    func refreshDevices() {
        // Our own private aggregate device shows up here too, but it is no choice to offer.
        outputs = output.outputDevices().filter { !SoftwareVolumeDevice.isOurs(uid: $0.uid) }
        inputs = CoreAudioInputReader.devices()
        let set = Set(outputs.compactMap(\.uid))
        if set != outputDeviceSet { outputDeviceSet = set }
        pollLevels()
    }

    /// Cheap property reads, called once per sampling tick.
    func pollLevels() {
        if let device = output.defaultOutputDeviceID() {
            let newVolume = output.volume(for: device)
            let newMute = output.isMuted(for: device)
            if newVolume != volume { volume = newVolume }
            if newMute != isMuted { isMuted = newMute }
            let running = Self.isRunning(device)
            if running != isOutputRunning { isOutputRunning = running }
        }
        let newInput = CoreAudioInputReader.currentDeviceID().flatMap(CoreAudioInputReader.volume(of:))
        if newInput != inputVolume { inputVolume = newInput }
    }

    private static func isRunning(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr && value != 0
    }

    func setVolume(_ value: Double) {
        output.setVolume(value)
        volume = min(1, max(0, value))
        // Dragging a muted slider up should be heard, as with the system control.
        if isMuted, value > 0 { output.toggleMute(); isMuted = false }
    }

    func toggleMute() {
        if output.toggleMute() { isMuted.toggle() }
    }

    func selectOutput(_ id: AudioDeviceID) {
        output.selectOutputDevice(id)
        refreshDevices()
    }

    func selectInput(_ id: AudioDeviceID) {
        CoreAudioInputReader.select(id)
        refreshDevices()
    }

    func setInputVolume(_ value: Double) {
        guard let device = CoreAudioInputReader.currentDeviceID() else { return }
        CoreAudioInputReader.setVolume(value, of: device)
        inputVolume = min(1, max(0, value))
    }
}
