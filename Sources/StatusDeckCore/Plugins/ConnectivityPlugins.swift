import StatusDeckKit
import SwiftUI

// MARK: - Wi-Fi

final class WiFiPlugin: BuiltInPlugin {
    init(services: SharedServices) {
        super.init(manifest: PluginManifest(
            id: "com.statusdeck.wifi",
            name: "Wi-Fi",
            summary: "开关 Wi-Fi，查看信号、信道、速率和安全性。切换网络仍在系统设置里进行。",
            symbol: "wifi",
            category: .control,
            sortOrder: 80,
            permissions: ["显示网络名称需要“定位”权限（macOS 的要求），只在你点击时才请求，应用不读取位置。"]
        ), services: services)
    }

    override func willDeactivate() {
        services.wifi.poller.set(owner: manifest.id, interval: nil)
    }

    override func panelVisibilityChanged(_ isVisible: Bool) {
        services.wifi.poller.set(owner: manifest.id, interval: isVisible ? 5 : nil)
    }

    override var sections: [DeckSection] {
        [DeckSection(id: "wifi", title: "Wi-Fi") {
            WiFiRow(wifi: services.wifi)
        } detail: {
            WiFiDetail(wifi: services.wifi)
        }]
    }
}

func wifiSubtitle(_ wifi: WiFiState) -> String {
    guard wifi.isAvailable else { return DeckL("不可用") }
    guard wifi.isPoweredOn else { return DeckL("已关闭") }
    guard wifi.isAssociated else { return DeckL("未连接") }
    return wifi.ssid ?? DeckL("已连接")
}

private struct WiFiRow: View {
    @ObservedObject var wifi: WiFiController
    @Environment(\.openPanelDetail) private var openDetails
    var body: some View {
        let state = wifi.state
        PanelSplitTile(title: "Wi-Fi", value: wifiSubtitle(state), symbol: state.isPoweredOn ? "wifi" : "wifi.slash",
                       isActive: state.isPoweredOn, isEnabled: state.isAvailable,
                       toggleHelp: state.isPoweredOn ? DeckL("关闭 Wi-Fi", "Turn Wi-Fi off") : DeckL("开启 Wi-Fi", "Turn Wi-Fi on"),
                       onToggle: { wifi.setPower(!state.isPoweredOn) }, onDetails: { openDetails?() })
    }
}

struct WiFiDetail: View {
    @ObservedObject var wifi: WiFiController

    var body: some View {
        let state = wifi.state
        VStack(spacing: 6) {
            if let name = state.interfaceName {
                DeckCard {
                    VStack(alignment: .leading, spacing: 5) {
                        DeckTitle(DeckL("网络接口"))
                        DeckInfoRow(DeckL("BSD 名称", "BSD name"), name)
                        if let address = state.hardwareAddress {
                            DeckInfoRow(DeckL("MAC 地址", "MAC address"), address)
                        }
                    }
                }
            }
            DeckCard {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 9) {
                        DeckTitle("Wi-Fi")
                        Spacer()
                        DeckSwitch(isOn: state.isPoweredOn, isEnabled: state.isAvailable) {
                            wifi.setPower(!state.isPoweredOn)
                        }
                    }
                    DeckInfoRow(DeckL("网络"), wifiSubtitle(state))
                    if state.isAssociated {
                        if state.ssid == nil {
                            DeckTextButton(DeckL("授权定位以显示网络名称")) { wifi.requestNameAccess() }
                        }
                        if let bssid = state.bssid { DeckInfoRow("BSSID", bssid) }
                        if let standard = state.standard { DeckInfoRow(DeckL("标准"), standard) }
                        if let rate = state.transmitRate { DeckInfoRow(DeckL("传输速率"), "\(Int(rate.rounded())) Mbps") }
                        if let rssi = state.rssi { DeckInfoRow("RSSI", "\(rssi) dBm") }
                        if let noise = state.noise { DeckInfoRow(DeckL("噪声", "Noise"), "\(noise) dBm") }
                        if let snr = state.signalToNoise { DeckInfoRow("SNR", "\(snr) dB") }
                        if let channel = state.channel {
                            DeckInfoRow(DeckL("信道"), [String(channel), state.band, state.channelWidth].compactMap { $0 }.joined(separator: " · "))
                        }
                        if let security = state.security { DeckInfoRow(DeckL("安全性"), security) }
                    }
                }
            }
            if let address = state.ipv4 {
                DeckCard {
                    VStack(alignment: .leading, spacing: 5) {
                        DeckTitle("IPv4")
                        DeckInfoRow(DeckL("IP 地址", "IP address"), address)
                        if let mask = state.subnetMask { DeckInfoRow(DeckL("子网掩码", "Subnet mask"), mask) }
                        if let router = state.router { DeckInfoRow(DeckL("路由器"), router) }
                        ForEach(Array(state.dnsServers.enumerated()), id: \.offset) { index, server in
                            DeckInfoRow(state.dnsServers.count > 1 ? "DNS \(index + 1)" : "DNS", server)
                        }
                    }
                }
            }
            DeckCard {
                HStack {
                    Spacer()
                    DeckTextButton(DeckL("在系统设置中切换网络")) { SystemSettings.open(.wifi) }
                }
            }
        }
        .onAppear { wifi.refresh() }
    }
}

// MARK: - Bluetooth

final class BluetoothPlugin: BuiltInPlugin {
    init(services: SharedServices) {
        super.init(manifest: PluginManifest(
            id: "com.statusdeck.bluetooth",
            name: "蓝牙",
            summary: "开关蓝牙，连接或断开已配对设备，查看设备电量。",
            symbol: "dot.radiowaves.left.and.right",
            category: .control,
            sortOrder: 81,
            permissions: ["第一次开关蓝牙或连接设备时，macOS 会询问蓝牙权限。查看列表和电量不需要权限。"]
        ), services: services)
    }

    override func didActivate() {
        services.bluetooth.refreshIfStale()
    }

    override func willDeactivate() {
        services.bluetooth.poller.set(owner: manifest.id, interval: nil)
    }

    override func panelVisibilityChanged(_ isVisible: Bool) {
        services.bluetooth.poller.set(owner: manifest.id, interval: isVisible ? 30 : nil)
    }

    override var sections: [DeckSection] {
        [DeckSection(id: "bluetooth", title: DeckL("蓝牙")) {
            BluetoothRow(bluetooth: services.bluetooth)
        } detail: {
            DeckCard { BluetoothDetail(bluetooth: services.bluetooth) }
        }]
    }
}

private struct BluetoothRow: View {
    @ObservedObject var bluetooth: BluetoothController

    private var summary: String {
        switch bluetooth.power {
        case .on:
            switch bluetooth.connected.count {
            case 0: DeckL("已开启")
            case 1: DeckL("已连接 1 台", "1 connected")
            case let count: DeckLF("已连接 %ld 台", "%ld connected", count)
            }
        case .off: DeckL("已关闭")
        case .unavailable: DeckL("不可用")
        case .unknown: DeckL("读取中…")
        }
    }

    var body: some View {
        PanelTileLabel(title: DeckL("蓝牙"), value: summary, symbol: "dot.radiowaves.left.and.right",
                       isActive: bluetooth.power.isOn)
    }
}

/// One bar for a device with one battery; a ring per part for earbuds and their case.
private struct DeviceBattery: View {
    let device: BluetoothDeviceInfo
    @Environment(\.deckTheme) private var theme

    var body: some View {
        if device.battery != nil || (device.left == nil && device.right == nil) {
            let level = device.battery ?? device.caseLevel ?? 0
            DeckBar(value: Double(level) / 100, color: level <= 20 ? theme.negative : nil, height: 4)
                .padding(.horizontal, 9)
        } else {
            HStack(spacing: 0) {
                ring(device.left, symbol: "airpod.left")
                ring(device.caseLevel, symbol: "airpods.chargingcase.fill")
                ring(device.right, symbol: "airpod.right")
            }
        }
    }

    @ViewBuilder
    private func ring(_ level: Int?, symbol: String) -> some View {
        if let level {
            DeckRing(value: Double(level) / 100, color: level <= 20 ? theme.negative : theme.accent, lineWidth: 5) {
                VStack(spacing: 1) {
                    Text("\(level)%")
                        .font(.system(size: 13))
                        .monospacedDigit()
                    Image(systemName: symbol)
                        .font(.system(size: 13))
                }
                .foregroundStyle(theme.primary)
            }
            .frame(width: 66, height: 66)
            .frame(maxWidth: .infinity)
        }
    }
}

func batteryText(_ device: BluetoothDeviceInfo) -> String {
    if let battery = device.battery { return "\(battery)%" }
    var parts: [String] = []
    if let left = device.left { parts.append(DeckL("左", "Left") + " \(left)%") }
    if let right = device.right { parts.append(DeckL("右", "Right") + " \(right)%") }
    if let caseLevel = device.caseLevel { parts.append(DeckL("盒", "Case") + " \(caseLevel)%") }
    return parts.joined(separator: " ")
}

private struct BluetoothDetail: View {
    @ObservedObject var bluetooth: BluetoothController
    @State private var showsOthers = false
    @State private var pendingDisconnect: String?
    @State private var isConfirmingPowerOff = false
    @Environment(\.deckTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(bluetooth.power.isOn ? DeckL("蓝牙已开启") : DeckL("蓝牙已关闭"))
                    .font(.system(size: 13))
                    .foregroundStyle(theme.primary)
                Spacer()
                DeckSwitch(isOn: bluetooth.power.isOn, isEnabled: bluetooth.power != .unavailable) {
                    togglePower()
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 2)
            if isConfirmingPowerOff {
                confirmation(text: DeckL("键盘或鼠标可能随之断开，确定关闭蓝牙？"), confirmTitle: DeckL("关闭")) {
                    isConfirmingPowerOff = false
                    bluetooth.setPower(false)
                } onCancel: {
                    isConfirmingPowerOff = false
                }
            }
            if bluetooth.power.isOn {
                ForEach(bluetooth.connected) { device in
                    deviceRow(device)
                    if device.summaryBattery != nil || device.caseLevel != nil {
                        DeviceBattery(device: device)
                    }
                }
                if !bluetooth.notConnected.isEmpty {
                    Button {
                        showsOthers.toggle()
                    } label: {
                        HStack {
                            DeckSubheading(DeckLF("其他设备（%@）", "Other devices (%@)", String(bluetooth.notConnected.count)))
                            Spacer()
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if showsOthers {
                        ForEach(bluetooth.notConnected) { deviceRow($0) }
                    }
                }
            }
        }
    }

    private func togglePower() {
        guard bluetooth.power.isOn else {
            bluetooth.setPower(true)
            return
        }
        if bluetooth.connected.contains(where: \.isInputDevice) {
            isConfirmingPowerOff = true
        } else {
            bluetooth.setPower(false)
        }
    }

    @ViewBuilder
    private func deviceRow(_ device: BluetoothDeviceInfo) -> some View {
        DeckDeviceRow(symbol: device.symbolName, title: device.name, isSelected: device.isConnected, action: {
            // A stray click must not cut off the keyboard or mouse in use.
            if device.isConnected, device.isInputDevice {
                pendingDisconnect = device.address
            } else {
                bluetooth.toggleConnection(of: device)
            }
        }) {
            if bluetooth.busyAddress == device.address {
                Text("…").font(.system(size: 11)).foregroundStyle(theme.secondary)
            } else {
                Text(batteryText(device))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(theme.secondary)
            }
        }
        if pendingDisconnect == device.address {
            confirmation(text: DeckL("断开后可能无法再用它操作，确定？"), confirmTitle: DeckL("断开")) {
                pendingDisconnect = nil
                bluetooth.toggleConnection(of: device)
            } onCancel: {
                pendingDisconnect = nil
            }
        }
    }

    private func confirmation(text: String, confirmTitle: String, onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) -> some View {
        DeckInset {
            HStack(spacing: 10) {
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                DeckTextButton(DeckL("取消"), action: onCancel)
                DeckTextButton(confirmTitle, role: .destructive, action: onConfirm)
            }
        }
    }
}

// MARK: - Input sources

final class InputSourcePlugin: BuiltInPlugin {
    init(services: SharedServices) {
        super.init(manifest: PluginManifest(
            id: "com.statusdeck.inputsource",
            name: "输入法",
            summary: "在面板里切换已启用的输入法。",
            symbol: "character.bubble",
            category: .control,
            sortOrder: 82
        ), services: services)
    }

    override func panelVisibilityChanged(_ isVisible: Bool) {
        if isVisible { services.inputSources.refresh() }
    }

    override var sections: [DeckSection] {
        [DeckSection(id: "inputsource", title: DeckL("输入法")) {
            InputSourceRow(sources: services.inputSources)
        } detail: {
            DeckCard { InputSourceDetail(sources: services.inputSources) }
        }]
    }
}

private struct InputSourceRow: View {
    @ObservedObject var sources: InputSourceController
    var body: some View {
        PanelTileLabel(title: DeckL("输入法"), value: sources.sources.first(where: \.isCurrent)?.name,
                       symbol: "character.bubble", isActive: false)
    }
}

private struct InputSourceDetail: View {
    @ObservedObject var sources: InputSourceController
    @Environment(\.deckTheme) private var theme

    var body: some View {
        VStack(spacing: 8) {
            DeckTitle(DeckL("输入法")).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(sources.sources) { source in
                Button {
                    sources.select(source.id)
                } label: {
                    HStack(spacing: 10) {
                        Text(source.name).lineLimit(2)
                        Spacer(minLength: 4)
                        if source.isCurrent { Image(systemName: "checkmark").accessibilityHidden(true) }
                    }
                    .font(.system(size: 13, weight: source.isCurrent ? .semibold : .regular))
                    .foregroundStyle(theme.primary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .contentShape(Rectangle())
                    .deckGlass(in: RoundedRectangle(cornerRadius: 11),
                               tint: source.isCurrent ? theme.accent.opacity(0.18) : nil,
                               interactive: true, fallback: theme.inset)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
