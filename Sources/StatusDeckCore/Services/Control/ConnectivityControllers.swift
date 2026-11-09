import AppKit
import Combine
import CoreWLAN
import Foundation
import IOBluetooth
import IOKit
import StatusDeckKit
import SystemConfiguration

// MARK: - Wi-Fi

struct WiFiState: Equatable {
    var isAvailable = false
    var isPoweredOn = false
    var ssid: String?
    var bssid: String?
    var rssi: Int?
    var noise: Int?
    var transmitRate: Double?
    var channel: Int?
    var band: String?
    var channelWidth: String?
    var standard: String?
    var security: String?
    var interfaceName: String?
    var hardwareAddress: String?
    var ipv4: String?
    var subnetMask: String?
    var router: String?
    var dnsServers: [String] = []

    /// Associated with a network, which is knowable even when the name is hidden.
    var isAssociated: Bool { (rssi ?? 0) != 0 }

    var signalToNoise: Int? {
        guard let rssi, let noise, noise < 0 else { return nil }
        return rssi - noise
    }

    var bars: Int {
        guard isPoweredOn, isAssociated, let rssi else { return 0 }
        if rssi >= -60 { return 3 }
        if rssi >= -72 { return 2 }
        return 1
    }
}

@MainActor
final class WiFiController: ObservableObject {
    @Published private(set) var state = WiFiState()
    @Published private(set) var nameAccess: WiFiNameAccess = .notDetermined
    private(set) lazy var poller = IntervalPoller { [weak self] in self?.refresh() }

    private let queue = DispatchQueue(label: "statusdeck.wifi", qos: .utility)
    private let authorizer = CoreLocationWiFiNameAuthorizer()

    init() {
        authorizer.onAccessChange = { [weak self] in
            guard let self else { return }
            self.nameAccess = self.authorizer.access
            self.refresh()
        }
    }

    func refresh() {
        let includeIdentity = nameAccess == .authorized
        queue.async { [weak self] in
            let state = Self.read(includeIdentity: includeIdentity)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if self?.state != state { self?.state = state }
                }
            }
        }
    }

    func setPower(_ isOn: Bool) {
        queue.async { [weak self] in
            try? CWWiFiClient.shared().interface()?.setPower(isOn)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    /// macOS only reveals the network name to apps with Location access. Asked
    /// for on click, never on launch; a past refusal opens Settings instead.
    func requestNameAccess() {
        if authorizer.requestAccess() == .openLocationSettings {
            SystemSettings.open(.location)
        }
    }

    nonisolated private static func read(includeIdentity: Bool) -> WiFiState {
        var state = WiFiState()
        guard let interface = CWWiFiClient.shared().interface() else { return state }
        state.isAvailable = true
        state.isPoweredOn = interface.powerOn()
        state.interfaceName = interface.interfaceName
        state.hardwareAddress = interface.hardwareAddress()
        guard state.isPoweredOn else { return state }

        let rssi = interface.rssiValue()
        state.rssi = rssi == 0 ? nil : rssi
        let noise = interface.noiseMeasurement()
        state.noise = noise < 0 ? noise : nil
        let rate = interface.transmitRate()
        state.transmitRate = rate.isFinite && rate > 0 ? rate : nil
        if includeIdentity {
            state.ssid = interface.ssid()
            state.bssid = interface.bssid()
        }
        if let channel = interface.wlanChannel() {
            state.channel = channel.channelNumber
            switch channel.channelBand {
            case .band2GHz: state.band = "2.4 GHz"
            case .band5GHz: state.band = "5 GHz"
            case .band6GHz: state.band = "6 GHz"
            default: break
            }
            switch channel.channelWidth {
            case .width20MHz: state.channelWidth = "20 MHz"
            case .width40MHz: state.channelWidth = "40 MHz"
            case .width80MHz: state.channelWidth = "80 MHz"
            case .width160MHz: state.channelWidth = "160 MHz"
            default: break
            }
        }
        switch interface.activePHYMode() {
        case .mode11a: state.standard = "802.11a"
        case .mode11b: state.standard = "802.11b"
        case .mode11g: state.standard = "802.11g"
        case .mode11n: state.standard = "Wi-Fi 4 (802.11n)"
        case .mode11ac: state.standard = "Wi-Fi 5 (802.11ac)"
        case .mode11ax: state.standard = "Wi-Fi 6 (802.11ax)"
        default: break
        }
        switch interface.security() {
        case .none: state.security = DeckL("无加密")
        case .WEP, .dynamicWEP: state.security = "WEP"
        case .wpaPersonal, .wpaPersonalMixed, .wpaEnterprise, .wpaEnterpriseMixed: state.security = "WPA"
        case .wpa2Personal, .wpa2Enterprise: state.security = "WPA2"
        case .personal, .enterprise: state.security = "WPA2/3"
        case .wpa3Personal, .wpa3Enterprise, .wpa3Transition: state.security = "WPA3"
        default: break
        }
        if let name = state.interfaceName, state.isAssociated { readIPv4(for: name, into: &state) }
        return state
    }

    nonisolated private static func readIPv4(for interface: String, into state: inout WiFiState) {
        guard let store = SCDynamicStoreCreate(nil, "MyStatus Wi-Fi" as CFString, nil, nil) else { return }
        func dictionary(_ key: String) -> [String: Any]? {
            SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any]
        }
        let prefix = "State:/Network/Service/"
        let suffix = "/IPv4"
        let primary = dictionary("State:/Network/Global/IPv4")?["PrimaryService"] as? String
        let keys = SCDynamicStoreCopyKeyList(store, (prefix + "[^/]+" + suffix) as CFString) as? [String] ?? []
        let primaryKey = primary.map { prefix + $0 + suffix }
        let candidates = (primaryKey.map { [$0] } ?? []) + keys.filter { $0 != primaryKey }.sorted()
        for key in candidates {
            guard let ipv4 = dictionary(key), ipv4["InterfaceName"] as? String == interface,
                  let address = (ipv4["Addresses"] as? [String])?.first else { continue }
            state.ipv4 = address
            state.subnetMask = (ipv4["SubnetMasks"] as? [String])?.first
            state.router = ipv4["Router"] as? String
            let service = key.dropFirst(prefix.count).dropLast(suffix.count)
            state.dnsServers = dictionary(prefix + service + "/DNS")?["ServerAddresses"] as? [String]
                ?? dictionary("Setup:/Network/Service/\(service)/DNS")?["ServerAddresses"] as? [String]
                ?? []
            return
        }
    }
}

// MARK: - Bluetooth

struct BluetoothDeviceInfo: Identifiable, Equatable {
    var id: String { address }
    let address: String
    let name: String
    let minorType: String?
    var isConnected: Bool
    var battery: Int?
    var left: Int?
    var right: Int?
    var caseLevel: Int?

    /// Disconnecting one of these can leave the Mac with no way to click "connect" again.
    var isInputDevice: Bool {
        guard let minorType = minorType?.lowercased() else { return false }
        return ["keyboard", "mouse", "trackpad", "gamepad"].contains { minorType.contains($0) }
    }

    var symbolName: String {
        switch minorType?.lowercased() ?? "" {
        case let type where type.contains("keyboard"): "keyboard"
        case let type where type.contains("mouse"): "computermouse"
        case let type where type.contains("trackpad"): "rectangle.and.hand.point.up.left"
        case let type where type.contains("gamepad"): "gamecontroller"
        case let type where type.contains("headphone") || type.contains("headset"): "headphones"
        case let type where type.contains("speaker"): "hifispeaker"
        default: "dot.radiowaves.left.and.right"
        }
    }

    /// The level a one-line row shows. Earbuds report per bud, so the lower bud
    /// stands in for the pair: it is the one that dies first.
    var summaryBattery: Int? {
        battery ?? [left, right].compactMap { $0 }.min()
    }
}

/// Parses `system_profiler -json SPBluetoothDataType`, the source Status Trio also
/// relies on because it is the only one reporting a device's current name.
enum BluetoothReport {
    struct Parsed: Equatable {
        var devices: [BluetoothDeviceInfo] = []
        var isControllerOn: Bool?
    }

    static func parse(_ data: Data) -> Parsed? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let section = (root["SPBluetoothDataType"] as? [[String: Any]])?.first else {
            return nil
        }
        var parsed = Parsed()
        if let state = (section["controller_properties"] as? [String: Any])?["controller_state"] as? String {
            parsed.isControllerOn = state == "attrib_on"
        }
        for (key, connected) in [("device_connected", true), ("device_not_connected", false)] {
            for group in section[key] as? [[String: Any]] ?? [] {
                for (name, value) in group {
                    guard let fields = value as? [String: Any], let address = fields["device_address"] as? String else { continue }
                    parsed.devices.append(BluetoothDeviceInfo(
                        address: address,
                        name: name.replacingOccurrences(of: "\u{a0}", with: " "),
                        minorType: fields["device_minorType"] as? String,
                        isConnected: connected,
                        battery: percent(fields["device_batteryLevelMain"]),
                        left: percent(fields["device_batteryLevelLeft"]),
                        right: percent(fields["device_batteryLevelRight"]),
                        caseLevel: percent(fields["device_batteryLevelCase"])
                    ))
                }
            }
        }
        return parsed
    }

    static func percent(_ value: Any?) -> Int? {
        guard let text = value as? String else { return nil }
        return Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "% ")))
    }

    static func normalizedAddress(_ address: String) -> String {
        address.lowercased().filter(\.isHexDigit)
    }
}

@MainActor
final class BluetoothController: ObservableObject {
    @Published private(set) var power: BluetoothRadioPower = .unknown
    @Published private(set) var devices: [BluetoothDeviceInfo] = []
    @Published private(set) var busyAddress: String?
    private(set) lazy var poller = IntervalPoller { [weak self] in self?.refreshIfStale(maximumAge: 45) }

    private let backend = IOBluetoothRadioPowerBackend()
    private let queue = DispatchQueue(label: "statusdeck.bluetooth", qos: .utility)
    private var isRefreshing = false
    private var lastRefresh = Date.distantPast

    var connected: [BluetoothDeviceInfo] { devices.filter(\.isConnected) }
    var notConnected: [BluetoothDeviceInfo] { devices.filter { !$0.isConnected } }

    init() {}

    /// `system_profiler` costs a process launch, so it is throttled however often
    /// the panel is reopened.
    func refreshIfStale(maximumAge: TimeInterval = 20) {
        guard Date().timeIntervalSince(lastRefresh) > maximumAge else { return }
        refresh()
    }

    /// Reads radio state and devices from the profiler. IOBluetooth's own power
    /// query needs the Bluetooth permission, and opening a monitoring panel is not
    /// a reason to show that prompt.
    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastRefresh = Date()
        queue.async { [weak self] in
            let report = Self.readReport()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isRefreshing = false
                    guard let report else { return }
                    if report.devices != self.devices { self.devices = report.devices }
                    if let isOn = report.isControllerOn {
                        let power: BluetoothRadioPower = isOn ? .on : .off
                        if power != self.power { self.power = power }
                    }
                }
            }
        }
    }

    /// The first toggle is what shows the macOS Bluetooth permission prompt.
    func setPower(_ isOn: Bool) {
        Task { [weak self] in
            guard let self else { return }
            guard await self.backend.setPower(isOn) else { return }
            // The controller takes a moment to change, and the profiler reports the old state until it has.
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            self.refresh()
        }
    }

    func toggleConnection(of device: BluetoothDeviceInfo) {
        guard busyAddress == nil else { return }
        busyAddress = device.address
        let wanted = BluetoothReport.normalizedAddress(device.address)
        let shouldConnect = !device.isConnected
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // The first use of IOBluetooth here is what shows the macOS permission
            // prompt, so it only happens when the user asks for a connection change.
            let target = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice])?
                .first { BluetoothReport.normalizedAddress($0.addressString ?? "") == wanted }
            _ = shouldConnect ? target?.openConnection() : target?.closeConnection()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.busyAddress = nil
                    self?.refresh()
                }
            }
        }
    }

    nonisolated private static func readReport() -> BluetoothReport.Parsed? {
        guard let data = Subprocess.output("/usr/sbin/system_profiler", ["-json", "SPBluetoothDataType"], timeout: 15),
              var report = BluetoothReport.parse(data) else {
            return nil
        }

        // Apple's own accessories report through the HID registry, others through
        // the power manager; the profiler itself only knows about some of them.
        let hidLevels = readHIDBatteryLevels()
        let accessoryLevels = Subprocess.output("/usr/bin/pmset", ["-g", "accps", "-xml"], timeout: 4)
            .flatMap { String(data: $0, encoding: .utf8) }
            .map(BluetoothAccessoryBatteryReader.parse(xml:)) ?? []
        let names = report.devices.map(\.name)
        for index in report.devices.indices where report.devices[index].summaryBattery == nil {
            if let level = hidLevels[BluetoothReport.normalizedAddress(report.devices[index].address)] {
                report.devices[index].battery = level
                continue
            }
            let name = report.devices[index].name
            let matches = accessoryLevels.filter { $0.name == name && $0.part == nil }
            // Two devices can share a name; a level only counts if it is unambiguous.
            if matches.count == 1, names.filter({ $0 == name }).count == 1 {
                report.devices[index].battery = matches[0].percentage
            }
        }
        report.devices.sort { lhs, rhs in
            lhs.isConnected != rhs.isConnected ? lhs.isConnected : lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        return report
    }

    nonisolated private static func readHIDBatteryLevels() -> [String: Int] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator) == KERN_SUCCESS else {
            return [:]
        }
        defer { IOObjectRelease(iterator) }
        var levels: [String: Int] = [:]
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let percent = IORegistryEntryCreateCFProperty(entry, "BatteryPercent" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Int,
                  let address = IORegistryEntryCreateCFProperty(entry, "DeviceAddress" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String else {
                continue
            }
            levels[BluetoothReport.normalizedAddress(address)] = percent
        }
        return levels
    }
}

// MARK: - Input sources

struct InputSourceItem: Identifiable, Equatable {
    let id: String
    let name: String
    let isCurrent: Bool
}

@MainActor
final class InputSourceController: ObservableObject {
    @Published private(set) var sources: [InputSourceItem] = []

    private let reader = SystemInputSourceReader()
    private let switcher = SystemInputSourceSwitcher()
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = DistributedNotificationCenter.default()
        for name in [InputSourceNotifications.selectedSourceChanged, InputSourceNotifications.enabledSourcesChanged] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        refresh()
    }

    func refresh() {
        let current = reader.currentKeyboardInputSourceID()
        let next = reader.keyboardInputSources()
            .filter { $0.isEnabled && $0.isSelectCapable && Self.isUserFacing($0.id) }
            .map { InputSourceItem(id: $0.id, name: $0.localizedName, isCurrent: $0.id == current) }
        if next != sources { sources = next }
    }

    func select(_ id: String) {
        if case .selected = switcher.select(id: id) { refresh() }
    }

    /// The category also holds system helpers the Input menu never lists.
    nonisolated static func isUserFacing(_ id: String) -> Bool {
        !["com.apple.PressAndHold", "com.apple.CharacterPaletteIM", "com.apple.KeyboardViewer", "com.apple.inputmethod.EmojiFunctionRowItem"]
            .contains(where: id.hasPrefix)
    }
}

// MARK: - Power

@MainActor
final class PowerController: ObservableObject {
    @Published private(set) var isApplying = false
    @Published private(set) var lastError: String?

    private let authorization: SystemControlAuthorization

    init(authorization: SystemControlAuthorization) { self.authorization = authorization }

    /// Reuse the same narrow administrator authorization as fan control.
    func setLowPowerMode(_ isOn: Bool, completion: @escaping () -> Void) {
        guard !isApplying else { return }
        isApplying = true
        lastError = nil
        authorization.authorize { [weak self] authorized in
            guard let self else { return }
            guard authorized else {
                self.isApplying = false
                self.lastError = self.authorization.error
                completion()
                return
            }
            let path = self.authorization.helperPath
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let succeeded = SystemControlAuthorization.run(path, ["power", isOn ? "1" : "0"], timeout: 8) != nil
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.isApplying = false
                        if !succeeded { self?.lastError = DeckL("macOS 未能切换低电量模式。", "macOS could not change Low Power Mode.") }
                        completion()
                    }
                }
            }
        }
    }
}

// MARK: - Settings links

enum SystemSettings {
    enum Pane: String {
        case wifi = "x-apple.systempreferences:com.apple.wifi-settings-extension"
        case bluetooth = "x-apple.systempreferences:com.apple.BluetoothSettings"
        case sound = "x-apple.systempreferences:com.apple.Sound-Settings.extension"
        case displays = "x-apple.systempreferences:com.apple.Displays-Settings.extension"
        case battery = "x-apple.systempreferences:com.apple.Battery-Settings.extension"
        case keyboard = "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
        case location = "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
        case systemAudioRecording = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case privacy = "x-apple.systempreferences:com.apple.preference.security"
        case bluetoothPrivacy = "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"
        case accessibility = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case inputMonitoring = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
    }

    static func open(_ pane: Pane) {
        if let url = URL(string: pane.rawValue) { NSWorkspace.shared.open(url) }
    }
}
