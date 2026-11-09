import AppKit
import Carbon
import Combine
import StatusDeckKit
import SwiftUI

// MARK: - Sound

final class SoundPlugin: BuiltInPlugin {
    private lazy var signalPoller = IntervalPoller { [weak self] in self?.services.softwareVolume.pollSignal() }

    init(services: SharedServices) {
        super.init(manifest: PluginManifest(
            id: "com.statusdeck.sound",
            name: "声音",
            summary: "主音量、输出和输入设备切换。显示器音频可用 DDC 或软件音量控制。",
            symbol: "speaker.wave.2.fill",
            category: .control,
            sortOrder: 100,
            permissions: ["开启软件音量时需要“系统录音”权限：系统声音会经过本应用调整音量后再播放，不会录制或保存。"]
        ), services: services)
    }

    override func didActivate() {
        services.audio.refreshDevices()
        services.displays.refreshIfStale()
        services.sound.managesEngine = true
    }

    override func willDeactivate() {
        services.sound.managesEngine = false
        services.audio.poller.set(owner: manifest.id, interval: nil)
        signalPoller.set(owner: manifest.id, interval: nil)
    }

    override func panelVisibilityChanged(_ isVisible: Bool) {
        services.audio.poller.set(owner: manifest.id, interval: isVisible ? 1 : nil)
        signalPoller.set(owner: manifest.id, interval: isVisible ? 1 : nil)
        if isVisible { services.audio.refreshDevices() }
    }

    override var sections: [DeckSection] {
        let sound = services.sound
        return [DeckSection(id: "sound", title: DeckL("声音")) {
            SoundRow(model: sound)
        } detail: {
            SoundDetail(model: sound)
        }]
    }

    override var settingsView: AnyView? {
        AnyView(SoundSettings(model: services.sound))
    }
}

private func outputSymbol(for device: AudioOutputDevice?) -> String {
    switch device?.transport {
    case .bluetooth, .bluetoothLowEnergy: "headphones"
    case .hdmi, .displayPort, .thunderbolt: "display"
    case .airPlay: "airplayaudio"
    case .usb: "cable.connector"
    case .builtIn: device?.dataSource == .headphones ? "headphones" : "laptopcomputer"
    case .virtual, .aggregate: "waveform"
    default: "hifispeaker"
    }
}

private struct SoundRow: View {
    @ObservedObject var model: SoundModel
    @Environment(\.deckTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            PanelLevelTitle(title: DeckL("声音"), value: model.audio.currentOutput?.name ?? DeckL("没有输出设备"))
            if let volume = model.volume {
                PanelLevelControl(
                    title: DeckL("声音"), minimumSymbol: model.isMuted ? "speaker.slash.fill" : "speaker.fill",
                    maximumSymbol: "speaker.wave.3.fill", detailSymbol: "airplayaudio",
                    value: volume,
                    isDimmed: model.isMuted,
                    onMinimumTap: { model.toggleMute() },
                    onChange: { model.setVolume($0) }
                )
            } else {
                Text(DeckL("这个设备不能调节音量（需要 macOS 14.2 或更高版本）"))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondary)
            }
            SoftwareVolumeStatus(model: model)
        }
    }
}

private struct PanelLevelTitle: View {
    let title: String
    let value: String?
    @Environment(\.deckTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.primary)
                .layoutPriority(1)
            Spacer(minLength: 0)
            if let value {
                Text(value)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(theme.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct PanelLevelControl: View {
    let title: String
    let minimumSymbol: String
    let maximumSymbol: String
    let detailSymbol: String
    let value: Double
    var isDimmed = false
    var onMinimumTap: (() -> Void)? = nil
    let onChange: (Double) -> Void
    @Environment(\.deckTheme) private var theme
    @Environment(\.openPanelDetail) private var openPanelDetail

    var body: some View {
        HStack(spacing: 7) {
            if let onMinimumTap {
                Button(action: onMinimumTap) { endpoint(minimumSymbol).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isDimmed ? DeckL("取消静音", "Unmute") : DeckL("静音", "Mute"))
            } else {
                endpoint(minimumSymbol).accessibilityHidden(true)
            }
            DeckRailSlider(value: value, isDimmed: isDimmed, onChange: onChange)
                .accessibilityLabel(title)
            endpoint(maximumSymbol).accessibilityHidden(true)
            if let openPanelDetail {
                Button(action: openPanelDetail) {
                    Image(systemName: detailSymbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.primary)
                        .frame(width: 27, height: 27)
                        .background(theme.roundFill, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
            }
        }
    }

    private func endpoint(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(theme.secondary)
            .frame(width: 17, height: 24)
    }
}

/// What software volume needs from the user, shown only when it needs something.
private struct SoftwareVolumeStatus: View {
    @ObservedObject var model: SoundModel
    @Environment(\.deckTheme) private var theme

    var body: some View {
        if model.isSoftwareVolumeOffered {
            caption(DeckL("拖动滑块即可调节。第一次会询问“系统录音”权限：声音只是经过 MyStatus 调整音量，不会被录制或保存。"))
        } else if model.route == .software {
            switch model.software.state {
            case .waitingForPermission:
                caption(DeckL("请在系统弹窗中允许录制系统音频。"))
            case .permissionDenied:
                DeckInset {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(DeckL("需要允许 MyStatus 录制系统音频才能调节这个设备的音量。声音不会被录制或保存。"))
                            .font(.system(size: 11))
                            .foregroundStyle(theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 12) {
                            Spacer()
                            DeckTextButton(DeckL("不用了")) { model.disableSoftwareVolumeForCurrentOutput() }
                            DeckTextButton(DeckL("打开隐私设置")) { SystemSettings.open(.systemAudioRecording) }
                        }
                    }
                }
            case let .failed(message):
                DeckInset {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(DeckLF("软件音量没有启动：%@", "Software volume did not start: %@", message))
                            .font(.system(size: 11))
                            .foregroundStyle(theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Spacer()
                            DeckTextButton(DeckL("不用了")) { model.disableSoftwareVolumeForCurrentOutput() }
                        }
                    }
                }
            case .running, .starting, .off:
                EmptyView()
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(theme.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 2)
    }
}

private struct SoundDetail: View {
    @ObservedObject var model: SoundModel

    var body: some View {
        VStack(spacing: DeckTheme.cardSpacing) {
            DeckCard {
                VStack(alignment: .leading, spacing: 5) {
                    DeckTitle(DeckL("输出"))
                    OutputSection(model: model)
                }
            }
            DeckCard {
                VStack(alignment: .leading, spacing: 5) {
                    DeckTitle(DeckL("输入"))
                    InputSection(audio: model.audio)
                }
            }
        }
    }
}

/// Loopback drivers can outnumber real devices, so they fold away until needed.
private struct VirtualDevicesDisclosure<Content: View>: View {
    let count: Int
    @Binding var isOpen: Bool
    @ViewBuilder var content: () -> Content
    var body: some View {
        if count > 0 {
            Button {
                isOpen.toggle()
            } label: {
                HStack {
                    DeckSubheading(DeckLF("虚拟设备（%@）", "Virtual devices (%@)", String(count)))
                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen { content() }
        }
    }
}

private struct OutputSection: View {
    @ObservedObject var model: SoundModel
    @State private var showsVirtual = false
    @Environment(\.deckTheme) private var theme

    private func isVirtual(_ device: AudioOutputDevice) -> Bool {
        device.transport == .virtual || device.transport == .aggregate
    }

    var body: some View {
        let outputs = model.audio.outputs
        let folded = outputs.filter { isVirtual($0) && !$0.isCurrent }
        VStack(alignment: .leading, spacing: 4) {
            ForEach(outputs.filter { !isVirtual($0) || $0.isCurrent }) { row($0) }
            VirtualDevicesDisclosure(count: folded.count, isOpen: $showsVirtual) {
                ForEach(folded) { row($0) }
            }
        }
    }

    @ViewBuilder
    private func row(_ device: AudioOutputDevice) -> some View {
        DeckDeviceRow(
            symbol: outputSymbol(for: device),
            title: device.name ?? DeckL("未知设备"),
            subtitle: device.isCurrent ? routeLabel : nil,
            isSelected: device.isCurrent,
            action: { model.audio.selectOutput(device.id) }
        )
        if device.isCurrent {
            if let volume = model.volume {
                DeckSubSlider(value: volume, isDimmed: model.isMuted) { model.setVolume($0) }
                    .padding(.leading, 39)
                    .padding(.trailing, 4)
            }
            softwareStatus
        }
    }

    private var routeLabel: String? {
        switch model.route {
        case .hardware: return nil
        case .ddc: return DeckL("DDC 音量")
        case .software: return DeckL("软件音量")
        case .softwareAvailable: return DeckL("拖动滑块开启软件音量")
        case .unavailable: return DeckL("不能调节音量")
        }
    }

    /// Problems show in the panel's sound row, where the slider is.
    @ViewBuilder
    private var softwareStatus: some View {
        if model.route == .software {
            HStack {
                Spacer()
                DeckTextButton(DeckL("关闭软件音量")) { model.disableSoftwareVolumeForCurrentOutput() }
            }
            .padding(.trailing, 4)
        }
    }
}

private struct InputSection: View {
    @ObservedObject var audio: AudioController
    @State private var showsVirtual = false

    var body: some View {
        let folded = audio.inputs.filter { $0.isVirtual && !$0.isCurrent }
        VStack(alignment: .leading, spacing: 4) {
            ForEach(audio.inputs.filter { !$0.isVirtual || $0.isCurrent }) { row($0) }
            VirtualDevicesDisclosure(count: folded.count, isOpen: $showsVirtual) {
                ForEach(folded) { row($0) }
            }
        }
    }

    @ViewBuilder
    private func row(_ device: AudioInputDevice) -> some View {
        DeckDeviceRow(symbol: "mic.fill", title: device.name, isSelected: device.isCurrent) {
            audio.selectInput(device.id)
        }
        if device.isCurrent, let volume = audio.inputVolume {
            DeckSubSlider(value: volume) { audio.setInputVolume($0) }
                .padding(.leading, 39)
                .padding(.trailing, 4)
        }
    }
}

private struct SoundSettings: View {
    @ObservedObject var model: SoundModel

    var body: some View {
        Picker(DeckL("显示器音量方式"), selection: Binding(get: { model.preference }, set: { model.preference = $0 })) {
            ForEach(VolumeRoutePreference.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        Text(DeckL("“自动”会先试 DDC。如果显示器没有响应，就改用软件音量。"))
            .font(.footnote)
            .foregroundStyle(.secondary)
        Button(DeckL("重新检测显示器的 DDC 音量")) { model.displays.resetVolumeCheck() }
    }
}

// MARK: - Display

final class DisplayPlugin: BuiltInPlugin {
    init(services: SharedServices) {
        super.init(manifest: PluginManifest(
            id: "com.statusdeck.display",
            name: "显示器",
            summary: "外接显示器的亮度和对比度（DDC/CI），内建屏亮度，无 DDC 时用软件调暗。",
            symbol: "display",
            category: .control,
            sortOrder: 90
        ), services: services)
    }

    override func didActivate() {
        services.displays.reload()
    }

    override func willDeactivate() {
        services.displays.poller.set(owner: manifest.id, interval: nil)
        services.displays.removeShades()
    }

    override func panelVisibilityChanged(_ isVisible: Bool) {
        services.displays.poller.set(owner: manifest.id, interval: isVisible ? 2 : nil)
        if isVisible { services.displays.refreshIfStale() }
    }

    override var settingsView: AnyView? {
        AnyView(DisplayBrightnessSettings(displays: services.displays))
    }

    override var sections: [DeckSection] {
        [DeckSection(id: "display", title: DeckL("显示器")) {
            DisplayRow(displays: services.displays)
        } detail: {
            DisplayDetail(displays: services.displays)
        }]
    }
}

private struct DisplayBrightnessSettings: View {
    @ObservedObject var displays: DisplayController

    var body: some View {
        ForEach(displays.displays.filter { $0.kind != .apple }) { display in
            Picker(display.name, selection: Binding(get: { displays.softwarePreferred(for: display.id) },
                                                     set: { displays.setSoftwarePreferred($0, for: display.id) })) {
                Text(DeckL("自动（优先硬件 DDC）", "Automatic (prefer hardware DDC)")).tag(false)
                Text(DeckL("软件调暗", "Software dimming")).tag(true)
            }
            Text(display.kindLabel).font(.caption).foregroundStyle(.secondary)
        }
        Button(DeckL("重新检测亮度硬件", "Retry brightness hardware")) { displays.retryBrightnessHardware() }
            .disabled(displays.isReading)
        if let status = displays.brightnessStatus { Text(status).font(.footnote).foregroundStyle(.secondary) }
    }
}

private struct DisplayRow: View {
    @ObservedObject var displays: DisplayController

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            PanelLevelTitle(title: DeckL("显示器"), value: displays.displays.count == 1 ? displays.displays.first?.name : DeckLF("%ld 台", "%ld displays", displays.displays.count))
            // With several monitors the master moves them together, keeping their offsets.
            if let first = displays.displays.first {
                PanelLevelControl(title: DeckL("亮度", "Brightness"), minimumSymbol: "sun.min", maximumSymbol: "sun.max.fill",
                                  detailSymbol: "display", value: first.brightness) { value in
                    let delta = value - first.brightness
                    for display in displays.displays {
                        displays.setBrightness(display.id == first.id ? value : display.brightness + delta, for: display.id)
                    }
                }
            }
        }
    }
}

private struct DisplayDetail: View {
    @ObservedObject var displays: DisplayController
    @Environment(\.deckTheme) private var theme

    var body: some View {
        VStack(spacing: DeckTheme.cardSpacing) {
            if displays.displays.isEmpty {
                DeckCard {
                    Text(DeckL("没有检测到显示器")).font(.system(size: 13)).foregroundStyle(theme.secondary)
                }
            }
            ForEach(displays.displays) { display in
                DeckCard {
                    VStack(alignment: .leading, spacing: 6) {
                        DeckTitleRow(display.name, value: display.kindLabel)
                        DeckSubSlider(symbol: "sun.max.fill", value: display.brightness) {
                            displays.setBrightness($0, for: display.id)
                        }
                        if let contrast = display.contrast {
                            DeckSubSlider(symbol: "circle.lefthalf.filled", value: contrast) {
                                displays.setContrast($0, for: display.id)
                            }
                        }
                        if let volume = display.volume, !display.ignoresVolumeWrites {
                            DeckSubSlider(symbol: display.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", value: volume, isDimmed: display.isMuted) {
                                displays.setVolume($0, for: display.id)
                            }
                        }
                        if let mode = display.modeDescription { DeckInfoRow(DeckL("分辨率"), mode) }
                        if display.ignoresVolumeWrites {
                            note(DeckL("这台显示器不响应 DDC 音量命令，音量由软件调节。"))
                        }
                        if display.isBrightnessAssumed {
                            note(DeckL("这台显示器不返回当前亮度，这里显示的是上次设定值。"))
                        }
                    }
                }
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(theme.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Media keys

final class MediaKeysPlugin: BuiltInPlugin {
    private let keys = MediaKeyController()
    private var activeCancellable: AnyCancellable?
    private var brightnessHotKeys: [any DeckHotKeyToken] = []

    init(services: SharedServices) {
        super.init(manifest: PluginManifest(
            id: "com.statusdeck.mediakeys",
            name: "键盘亮度和音量键",
            summary: "F1、F2 调外接显示器亮度，F10、F11、F12 调显示器音量。内建屏和普通扬声器仍由系统处理，没有外接显示器时不受影响。",
            symbol: "keyboard",
            category: .control,
            sortOrder: 120,
            permissions: ["需要“辅助功能”权限才能接收按键。如果 MonitorControl 也在运行，请先退出它，否则一次按键会被处理两次。"]
        ), services: services)
    }

    override func didActivate() {
        guard host?.isDryRun != true else { return }
        keys.handler = { [weak self] press in
            MainActor.assumeIsolated { self?.handle(press) ?? false }
        }
        keys.shouldObserveHardwareBrightness = { [weak self] in
            guard let self else { return false }
            return MediaKeyRouting.needsHardwareBrightnessListener(for: self.services.displays.displays)
        }
        activeCancellable = keys.$isActive
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.host?.pluginContentDidChange() }
            }
        keys.start()
        if UserDefaults.standard.bool(forKey: "keys.backupBrightness") { _ = setBackupKeys(true) }
        services.audio.refreshDevices()
        services.displays.refreshIfStale()
    }

    override func willDeactivate() {
        activeCancellable = nil
        brightnessHotKeys.removeAll()
        keys.stop()
        keys.handler = nil
    }

    /// Only there while something is missing, right below the sliders the keys drive.
    override var sections: [DeckSection] {
        guard !keys.isActive else { return [] }
        return [DeckSection(id: "mediakeys", title: DeckL("键盘按键")) {
            MediaKeysNotice()
        }]
    }

    override var settingsView: AnyView? {
        AnyView(MediaKeysSettings(keys: keys, displays: services.displays, backupAvailable: brightnessHotKeys.count == 2,
                                  setBackupKeys: { [weak self] in self?.setBackupKeys($0) ?? false },
                                  reconnect: { [weak self] in self?.keys.start() }))
    }

    private func setBackupKeys(_ enabled: Bool) -> Bool {
        brightnessHotKeys.removeAll()
        if enabled {
            brightnessHotKeys = registerBrightnessKeys(down: kVK_DownArrow, up: kVK_UpArrow, modifiers: UInt32(controlKey | optionKey))
        }
        return !enabled || brightnessHotKeys.count == 2
    }

    private func registerBrightnessKeys(down: Int, up: Int, modifiers: UInt32) -> [any DeckHotKeyToken] {
        guard let host, !host.isDryRun else { return [] }
        var tokens: [any DeckHotKeyToken] = []
        let bindings: [(Int, MediaKeyController.Key)] = [(down, .brightnessDown), (up, .brightnessUp)]
        for (code, key) in bindings {
            let label = key == .brightnessDown ? "F1" : "F2"
            let hotKey = DeckHotKey(keyCode: UInt32(code), modifiers: modifiers, label: label)
            guard let token = host.registerHotKey(hotKey, handler: { [weak self] in
                self?.keys.handleBrightnessShortcut(key)
            }) else { return [] }
            tokens.append(token)
        }
        return tokens
    }

    /// False hands the key back to macOS.
    private func handle(_ press: MediaKeyController.Press) -> Bool {
        let step = MediaKeyRouting.step(isFine: press.isFineStep)
        switch press.key {
        case .brightnessUp, .brightnessDown:
            let target = services.displays.brightnessKeyTarget()
            guard MediaKeyRouting.takesBrightness(on: target, isMediaEvent: press.isMediaEvent), let display = target else { return false }
            let current = display.kind == .apple ? (DisplayServicesAPI.brightness(of: display.id) ?? display.brightness) : display.brightness
            let next = min(1, max(0, current + (press.key == .brightnessUp ? step : -step)))
            guard services.displays.setBrightness(next, for: display.id) else { return false }
            DispatchQueue.main.async { [weak self] in
                self?.host?.showLevel(symbol: "sun.max.fill", value: next, title: display.name)
            }
            return true
        case .soundUp, .soundDown:
            let sound = services.sound
            guard MediaKeyRouting.takesVolume(route: sound.route, softwareEngineRuns: sound.managesEngine) else { return false }
            // As on any Mac, changing the volume also ends a mute.
            if sound.isMuted { sound.toggleMute() }
            guard let next = sound.nudge(by: press.key == .soundUp ? step : -step) else { return false }
            showVolume(next)
            return true
        case .mute:
            let sound = services.sound
            guard MediaKeyRouting.takesVolume(route: sound.route, softwareEngineRuns: sound.managesEngine),
                  let volume = sound.volume else { return false }
            if !press.isRepeat { sound.toggleMute() }
            showVolume(sound.isMuted ? 0 : volume)
            return true
        }
    }

    private func showVolume(_ value: Double) {
        host?.showLevel(
            symbol: value == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill",
            value: value,
            title: services.audio.currentOutput?.name
        )
    }
}

private struct MediaKeysNotice: View {
    @Environment(\.deckTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DeckTitle(DeckL("键盘按键"))
            Text(DeckL("要用 F1、F2 和 F10–F12 控制显示器，请在“辅助功能”里打开 MyStatus。打开后马上生效。"))
                .font(.system(size: 12))
                .foregroundStyle(theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                DeckTextButton(DeckL("打开系统设置"), role: .prominent) { SystemSettings.open(.accessibility) }
            }
        }
    }
}

private struct MediaKeysSettings: View {
    @ObservedObject var keys: MediaKeyController
    @ObservedObject var displays: DisplayController
    let backupAvailable: Bool
    let setBackupKeys: (Bool) -> Bool
    let reconnect: () -> Void
    @State private var backupResult: Bool?
    @AppStorage("keys.backupBrightness") private var backupBrightness = false
    @AppStorage("keys.standardFKeys") private var standardFKeys = true
    @AppStorage("keys.preferExternal") private var preferExternal = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(DeckL("单按 F1 / F2 调节亮度", "Adjust brightness with F1 / F2"), isOn: $standardFKeys)
                .onChange(of: standardFKeys) { _ in reconnect() }
            Text(DeckL("按住 Fn 时，F1 / F2 保留系统或应用的原有功能。", "With Fn held, F1 / F2 keep their usual system or app actions."))
                .font(.footnote).foregroundStyle(.secondary)
            switch keys.hardwareBrightnessState {
            case .listening:
                Text(DeckL("外接屏硬件亮度键监听已启用。", "Hardware brightness key listener is active."))
                    .font(.footnote).foregroundStyle(.secondary)
            case .permissionNeeded:
                Text(DeckL("监听外接屏的硬件亮度键需要「输入监控」。", "Hardware brightness keys for external displays need Input Monitoring."))
                    .font(.footnote).foregroundStyle(.secondary)
                Button(DeckL("打开输入监控", "Open Input Monitoring")) {
                    BrightnessHIDMonitor.requestAccess()
                    SystemSettings.open(.inputMonitoring)
                }
            case .unavailable(let code):
                Text(DeckL("无法启动硬件亮度键监听。", "Could not start the hardware brightness key listener.")
                     + (code.map { String(format: " (0x%08X)", UInt32(bitPattern: $0)) } ?? ""))
                    .font(.footnote).foregroundStyle(.orange)
            case .inactive:
                EmptyView()
            }
            Toggle(DeckL("备用亮度键 ⌃⌥↓ / ⌃⌥↑", "Backup brightness shortcuts ⌃⌥↓ / ⌃⌥↑"), isOn: $backupBrightness)
                .onChange(of: backupBrightness) { enabled in backupResult = setBackupKeys(enabled) }
            if backupBrightness && !(backupResult ?? backupAvailable) {
                Text(DeckL("备用按键被其他应用占用。", "Another app is using the backup shortcuts."))
                    .font(.footnote).foregroundStyle(.orange)
            }
            Toggle(DeckL("优先调整外接显示器", "Prefer an external display"), isOn: $preferExternal)
            Text(DeckL("鼠标在外接屏时调该屏；在内建屏时调第一台外接屏。关闭此项则始终跟随鼠标。", "Adjust the external display under the pointer, or the first external display when the pointer is on the built-in screen. Turn this off to always follow the pointer."))
                .font(.footnote).foregroundStyle(.secondary)
            HStack {
                Text(keys.isActive ? DeckL("按键监听已启用", "Key listener enabled") : DeckL("需要辅助功能权限", "Accessibility permission required"))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(DeckL("重新连接按键", "Reconnect keys"), action: reconnect)
                if !keys.isActive {
                    Button(DeckL("打开系统设置")) { SystemSettings.open(.accessibility) }
                }
            }
            if let last = keys.lastBrightnessKey {
                Text(DeckL("最近亮度按键：", "Last brightness key: ") + last)
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let target = displays.brightnessKeyTarget() {
                LabeledContent(DeckL("当前目标", "Current display"), value: target.name + " · " + target.kindLabel)
                HStack {
                    Button(DeckL("测试调暗", "Test dimming")) { nudge(-1.0 / 16) }
                    Button(DeckL("测试调亮", "Test brightening")) { nudge(1.0 / 16) }
                    Button(DeckL("重新检测显示器", "Detect displays again")) { displays.reload() }
                }
            }
            if let status = displays.brightnessStatus {
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }
            Text(DeckL("按住 ⌥⇧ 再按键，可以小幅调节。"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func nudge(_ amount: Double) {
        guard let display = displays.brightnessKeyTarget() else { return }
        displays.setBrightness(display.brightness + amount, for: display.id)
    }
}
