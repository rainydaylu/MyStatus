import AppKit
import StatusDeckKit
import SwiftUI

enum PluginSettingsSelection {
    static let general = "__general__"
    static let updates = "__updates__"
}

enum SettingsWindowSize {
    static let minimum = CGSize(width: 820, height: 620)
    static let initial = CGSize(width: 900, height: 750)
}

/// Which plugins are on, and each plugin's own options.
struct SettingsRootView: View {
    @ObservedObject var manager: PluginManager
    @ObservedObject var state: PanelState
    @Binding var selection: String?
    @ObservedObject var appPreferences: AppPreferences
    @ObservedObject var authorization: SystemControlAuthorization
    var isPreview = false
    let openPanelPreview: () -> Void

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up.fill").font(.title2).foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MyStatus").font(.headline)
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(DeckL("你的桌面控制中心", "Your desktop, together")).font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 8)
                if isPreview {
                    Text(DeckL("界面预览 · 控制功能已停用", "UI preview · controls disabled"))
                        .font(.caption).foregroundStyle(.orange)
                        .padding(.horizontal, 18).padding(.bottom, 8)
                }
                List(selection: $selection) {
                    Section {
                        destination(DeckL("偏好设置", "Preferences"), symbol: "slider.horizontal.3", id: PluginSettingsSelection.general)
                    }
                    Section {
                        ForEach(manager.orderedEntries.filter { !$0.isOnPluginShelf }) { entry in
                            row(entry, reorderable: true)
                        }
                        .onMove(perform: manager.movePanelEntries(from:to:))
                    } header: {
                        Text(DeckL("栏目", "Sections"))
                    }
                    Section {
                        ForEach(manager.orderedEntries.filter(\.isOnPluginShelf)) { row($0) }
                        destination(DeckL("插件更新", "Plugin updates"), symbol: "arrow.down.circle", id: PluginSettingsSelection.updates)
                    } header: {
                        Text(DeckL("插件", "Plugins"))
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 34)
            }
            .navigationSplitViewColumnWidth(min: 272, ideal: 292, max: 330)
        } detail: {
            detail.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .frame(minWidth: 500)
                .environment(\.defaultMinListRowHeight, 38)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: SettingsWindowSize.minimum.width, idealWidth: SettingsWindowSize.initial.width, maxWidth: .infinity,
               minHeight: SettingsWindowSize.minimum.height, idealHeight: SettingsWindowSize.initial.height, maxHeight: .infinity)
    }

    private func destination(_ title: String, symbol: String, id: String) -> some View {
        Button { selection = id } label: {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.\(id)")
        .tag(id)
    }

    /// Built-in plugins can be switched right here. A third-party one goes through
    /// its page, which asks for confirmation first.
    private func row(_ entry: PluginManager.Entry, reorderable: Bool = false) -> some View {
        HStack(spacing: 10) {
            rowTitle(entry)
            Spacer(minLength: 4)
            if entry.problem != nil {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            if entry.isExternal {
                Circle()
                    .fill(entry.isActive ? Color.green : Color.secondary.opacity(0.35))
                    .frame(width: 7, height: 7)
            } else {
                Toggle("", isOn: Binding(
                    get: { entry.isEnabled },
                    set: { manager.setEnabled($0, id: entry.id) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .disabled(isPreview)
            }
            if reorderable {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    .frame(width: 22, height: 28)
                    .help(DeckL("移动栏目", "Move section"))
                    .accessibilityLabel(DeckL("移动栏目", "Move section"))
            }
        }
        .contentShape(Rectangle())
        .tag(entry.id)
    }

    private func rowTitle(_ entry: PluginManager.Entry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: entry.manifest.symbol)
                .font(.system(size: 20))
                .frame(width: 25)
                .foregroundStyle(entry.isActive ? Color.accentColor : .secondary)
            Text(DeckL(entry.manifest.name)).lineLimit(2)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if selection == PluginSettingsSelection.general || selection == nil {
            GeneralSettings(manager: manager, state: state, appPreferences: appPreferences,
                            authorization: authorization, openPanelPreview: openPanelPreview)
        } else if selection == PluginSettingsSelection.updates {
            PluginUpdatesView(service: manager.updates)
        } else if let entry = manager.entries.first(where: { $0.id == selection }) {
            PluginDetail(entry: entry, manager: manager)
                .id(entry.id)
                .disabled(isPreview)
        }
    }
}

private struct PluginDetail: View {
    let entry: PluginManager.Entry
    @ObservedObject var manager: PluginManager
    @State private var isConfirmingTrust = false
    @State private var isConfirmingSettingsTrust = false

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: entry.manifest.symbol)
                        .font(.system(size: 20))
                        .foregroundStyle(entry.isActive ? Color.accentColor : .secondary)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(DeckL(entry.manifest.name)).font(.headline)
                        Text(DeckL(entry.manifest.summary))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(entry.isExternal ? DeckLF("第三方插件 · 版本 %@", "Extension · version %@", entry.manifest.version) : DeckL("内置插件"))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Toggle(DeckL("启用"), isOn: Binding(
                    get: { entry.isEnabled },
                    set: { wantsOn in
                        if wantsOn, entry.isExternal {
                            isConfirmingTrust = true
                        } else {
                            manager.setEnabled(wantsOn, id: entry.id)
                        }
                    }
                ))
                .disabled(cannotEnable)
                if let problem = entry.problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if lightControlsFirst, let view = entry.plugin?.settingsView {
                Section(DeckL("选项")) { view }
            }
            if entry.id == "com.statusdeck.codeisland" {
                Section {
                    CodeIslandSettingsLauncher {
                        if manager.settingsWindowRequiresTrust(for: entry.id) {
                            isConfirmingSettingsTrust = true
                        } else {
                            manager.openSettingsWindow(for: entry.id)
                        }
                    }
                    .disabled(cannotEnable)
                }
            }
            if !entry.manifest.permissions.isEmpty {
                Section(DeckL("权限")) {
                    ForEach(entry.manifest.permissions, id: \.self) { note in
                        Text(DeckL(note))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !lightControlsFirst, entry.isActive, let view = entry.plugin?.settingsView {
                Section(DeckL("选项")) { view }
            }
        }
        .formStyle(.grouped)
        .alert(DeckLF("启用第三方插件“%@”？", "Enable the extension “%@”?", DeckL(entry.manifest.name)), isPresented: $isConfirmingTrust) {
            Button(DeckL("启用"), role: .destructive) { manager.setEnabled(true, id: entry.id) }
            Button(DeckL("取消"), role: .cancel) {}
        } message: {
            Text(DeckL("插件的代码会在 MyStatus 内运行，拥有和它相同的权限，包括读取剪贴板历史。只启用你信任的来源。"))
        }
        .alert(DeckL("打开 CodeIsland 设置？", "Open CodeIsland settings?"), isPresented: $isConfirmingSettingsTrust) {
            Button(DeckL("打开", "Open")) { manager.openSettingsWindow(for: entry.id, approvingTrust: true) }
            Button(DeckL("取消"), role: .cancel) {}
        } message: {
            Text(DeckL("打开原版设置需要加载 CodeIsland 插件代码。插件会保持关闭，不会启动会话监听。", "Opening the original settings loads CodeIsland's code. The plugin stays disabled and session monitoring does not start."))
        }
    }

    private var lightControlsFirst: Bool {
        entry.id == "com.statusdeck.logolight" && entry.isActive
    }

    private var cannotEnable: Bool {
        guard !entry.isEnabled, entry.problem != nil, case let .external(item) = entry.source else { return false }
        return item.problem != nil || item.file == nil
    }
}

private struct CodeIslandSettingsLauncher: View {
    let open: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(DeckL("详细设置", "Detailed settings"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(DeckL("外观、行为、会话、声音与快捷键", "Appearance, behavior, sessions, sound and shortcuts"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(isHovered ? 0.13 : 0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(isHovered ? 0.36 : 0.20), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(DeckL("打开 CodeIsland 原版完整设置面板", "Open CodeIsland’s complete original settings window"))
        .accessibilityLabel(DeckL("详细设置", "Detailed settings"))
        .accessibilityHint(DeckL("打开 CodeIsland 原版完整设置面板", "Open CodeIsland’s complete original settings window"))
        .accessibilityIdentifier("codeisland.detailed-settings")
    }
}

private struct GeneralSettings: View {
    @ObservedObject var manager: PluginManager
    @ObservedObject var state: PanelState
    @ObservedObject var appPreferences: AppPreferences
    @ObservedObject var authorization: SystemControlAuthorization
    let openPanelPreview: () -> Void
    @AppStorage("panel.showUptime") private var showUptime = true
    @AppStorage("ui.pointerGlow") private var glow: Double = 0
    @AppStorage("ui.glassStrength") private var glassStrength = 0.20
    @AppStorage(PanelBackdropDepth.key) private var backgroundDepth = PanelBackdropDepth.defaultValue
    @AppStorage(PanelBackdropBlur.key) private var backgroundBlur = PanelBackdropBlur.defaultValue
    @AppStorage("ui.language") private var language = "system"
    /// What this window is showing: the chosen mode, or what macOS is on when automatic.
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Form {
            if let notice = manager.notice {
                Section {
                    Label(notice, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(DeckL("知道了")) { manager.dismissNotice() }
                }
            }
            Section(DeckL("通用")) {
                DeckLoginItemSetting()
                Toggle(DeckL("在主面板显示开机时间", "Show uptime on the main panel"), isOn: $showUptime)
                Picker(DeckL("刷新间隔"), selection: $appPreferences.refreshInterval) {
                    Text(DeckL("1 秒")).tag(1.0)
                    Text(DeckL("2 秒")).tag(2.0)
                    Text(DeckL("5 秒")).tag(5.0)
                }
            }
            Section(DeckL("权限", "Permissions")) {
                LabeledContent(DeckL("风扇与低电量模式", "Fans and Low Power Mode")) {
                    if authorization.isAuthorized {
                        Label(DeckL("已授权", "Authorized"), systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        Button(DeckL("一次授权…", "Authorize once…")) { authorization.authorize() }
                            .disabled(authorization.isAuthorizing)
                    }
                }
                if let error = authorization.error {
                    Text(error).font(.footnote).foregroundStyle(.orange)
                }
                Text(DeckL("两项系统控制共用一次管理员授权。以下隐私权限由 macOS 单独管理，按需开启。", "Both system controls share one administrator approval. macOS manages the privacy permissions below separately; enable them as needed."))
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                permissionLink(DeckL("蓝牙设备控制", "Bluetooth device control"), pane: .bluetoothPrivacy)
                permissionLink(DeckL("定位 · Wi-Fi 名称", "Location · Wi-Fi names"), pane: .location)
                permissionLink(DeckL("辅助功能 · 媒体键", "Accessibility · media keys"), pane: .accessibility)
                permissionLink(DeckL("输入监控 · 亮度键", "Input Monitoring · brightness keys"), pane: .inputMonitoring)
                permissionLink(DeckL("系统录音 · 软件音量", "System audio recording · software volume"), pane: .systemAudioRecording)
                permissionLink(DeckL("其他隐私设置", "Other privacy settings"), pane: .privacy)
            }
            Section(DeckL("语言", "Language")) {
                Picker(DeckL("界面语言", "Interface language"), selection: $language) {
                    ForEach(DeckLanguage.allCases, id: \.rawValue) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }
            }
            Section(DeckL("外观")) {
                Toggle(DeckL("自动切换"), isOn: Binding(
                    get: { state.appearance.isAutomatic },
                    set: { state.appearance = $0 ? .system : .fixed(isDark: colorScheme == .dark) }
                ))
                Picker(DeckL("模式"), selection: Binding(
                    get: { state.appearance.isAutomatic ? PanelAppearance.fixed(isDark: colorScheme == .dark) : state.appearance },
                    set: { state.appearance = $0 }
                )) {
                    Text(DeckL("浅色")).tag(PanelAppearance.light)
                    Text(DeckL("深色")).tag(PanelAppearance.dark)
                }
                .pickerStyle(.segmented)
                .disabled(state.appearance.isAutomatic)
                Text(state.appearance.isAutomatic
                    ? DeckL("跟随 macOS 的外观。macOS 切换浅色和深色时，这里也会跟着切换。")
                    : DeckL("始终使用所选的模式，不受 macOS 影响。"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section(DeckGlass.isSupported ? DeckL("液态玻璃", "Liquid Glass") : DeckL("毛玻璃", "Frosted appearance")) {
                VStack(alignment: .leading, spacing: 14) {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                        materialSlider(DeckL("卡片透明度", "Card translucency"), value: $glassStrength, id: "glassStrength")
                        materialSlider(DeckL("背景深度", "Background depth"), value: $backgroundDepth, id: "backgroundDepth")
                        materialSlider(DeckL("背景模糊", "Background blur"), value: $backgroundBlur, id: "backgroundBlur")
                        materialSlider(DeckL("鼠标光晕", "Pointer glow"), value: $glow, id: "pointerGlow")
                    }
                    Text(DeckL("背景深度调节外侧暗部，背景模糊调节卡片内的玻璃模糊强度。", "Background depth controls the outer shade. Background blur controls the glass effect inside cards."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
                HStack(spacing: 12) {
                    Button(DeckL("预览菜单栏面板", "Preview menu bar panel"), action: openPanelPreview)
                    Spacer(minLength: 0)
                    Button(DeckL("恢复默认值", "Restore defaults")) {
                        glassStrength = 0.20
                        backgroundDepth = PanelBackdropDepth.defaultValue
                        backgroundBlur = PanelBackdropBlur.defaultValue
                        glow = 0
                    }
                }
            }
            Section(DeckL("第三方插件")) {
                Text(DeckL("把 .deckplugin 文件夹放进插件文件夹，再点“重新扫描”。新插件默认关闭，启用前会先询问。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(DeckL("打开插件文件夹")) {
                        try? FileManager.default.createDirectory(at: manager.pluginsDirectory, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(manager.pluginsDirectory)
                    }
                    Button(DeckL("重新扫描")) { manager.scanExternal() }
                }
            }
            Section {
                HStack {
                    Text(DeckL("基于 MonitorControl（MIT）与 Status Trio（Apache-2.0）"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(DeckL("退出 MyStatus")) { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func materialSlider(_ title: String, value: Binding<Double>, id: String) -> some View {
        GridRow {
            Text(title)
                .frame(minHeight: 30, alignment: .leading)
            Slider(value: value, in: 0...1) { Text(title) }
                .labelsHidden()
                .accessibilityIdentifier("settings.\(id)")
            Text(value.wrappedValue, format: .percent.precision(.fractionLength(0)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 46, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    private func permissionLink(_ title: String, pane: SystemSettings.Pane) -> some View {
        LabeledContent(title) {
            Button(DeckL("打开系统设置", "Open System Settings")) { SystemSettings.open(pane) }
        }
    }
}

@MainActor
final class AppPreferences: ObservableObject {
    @Published var refreshInterval: Double {
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval")
            onIntervalChange?(refreshInterval)
        }
    }
    var onIntervalChange: ((Double) -> Void)?

    init() {
        refreshInterval = UserDefaults.standard.object(forKey: "refreshInterval") as? Double ?? 1
    }
}
