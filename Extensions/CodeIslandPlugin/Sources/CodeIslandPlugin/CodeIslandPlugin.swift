import AppKit
import CodeIslandCore
import StatusDeckKit
import SwiftUI

private let pluginID = "com.statusdeck.codeisland"
private let showsIslandKey = "plugin.com.statusdeck.codeisland.showIsland"
private let usesHooksKey = "plugin.com.statusdeck.codeisland.localHooks"

/// SwiftPM's resource bundle lives beside the loaded library, including for a
/// plugin installed by the in-app updater outside the main application bundle.
enum CodeIslandPluginResources {
    static var folder: URL? {
        var info = Dl_info()
        let entry: @convention(c) () -> UnsafeMutableRawPointer = statusdeckPluginCreate
        let address = unsafeBitCast(entry, to: UnsafeRawPointer.self)
        guard dladdr(address, &info) != 0, let name = info.dli_fname else { return nil }
        return URL(fileURLWithPath: String(cString: name)).deletingLastPathComponent()
    }
}

@MainActor
final class CodeIslandRuntime: ObservableObject {
    static weak var current: CodeIslandRuntime?
    let appState = AppState()
    private weak var host: (any DeckHost)?
    private var hookServer: HookServer?
    private var codingLight: CodingLightPublisher?
    private let hotKeyManager = GlobalHotKeyManager()
    private var localShortcutMonitor: Any?
    private(set) var panelController: PanelWindowController?
    @Published private(set) var hooksListening = false

    func start(host: any DeckHost) {
        self.host = host
        Self.current = self
        appState.applyCurrentPluginSessionMode()
        appState.startSessionDiscovery()
        appState.startCoworkWatcher()
        codingLight = CodingLightPublisher(state: appState)
        updateIsland(UserDefaults.standard.object(forKey: showsIslandKey) as? Bool ?? true)
        updateHooks(UserDefaults.standard.bool(forKey: usesHooksKey))
        setupGlobalShortcut()
        HostedCodeIslandSettingsWindow.shared.bind(appState: appState)
    }

    func stop() {
        teardownGlobalShortcut()
        HostedCodeIslandSettingsWindow.shared.close()
        codingLight?.stop()
        codingLight = nil
        updateHooks(false)
        updateIsland(false)
        appState.stopCoworkWatcher()
        appState.stopSessionDiscovery()
        appState.saveSessions()
        if Self.current === self { Self.current = nil }
        host = nil
    }

    func updateIsland(_ visible: Bool) {
        guard host != nil else { return }
        if visible, panelController == nil {
            let panel = PanelWindowController(appState: appState)
            panelController = panel
            panel.showPanel()
        } else if !visible {
            panelController?.closeHostedPanel()
            panelController = nil
        }
    }

    func hideIsland() {
        UserDefaults.standard.set(false, forKey: showsIslandKey)
        updateIsland(false)
    }

    func revealIsland() {
        UserDefaults.standard.set(true, forKey: showsIslandKey)
        updateIsland(true)
        panelController?.bringIslandIntoSight()
        if appState.surface == .collapsed { appState.surface = .sessionList }
    }

    func openSettings() {
        HostedCodeIslandSettingsWindow.shared.show(appState: appState, openUpdates: { [weak self] in self?.openUpdates() })
    }
    func openUpdates() { host?.openSettings(pluginID: "__updates__") }

    func setupGlobalShortcut() {
        teardownGlobalShortcut()

        // Collect all enabled shortcut bindings, skip duplicates (first wins)
        var bindings: [(keyCode: UInt16, mods: NSEvent.ModifierFlags, action: ShortcutAction)] = []
        var seen: Set<String> = []
        for action in ShortcutAction.allCases {
            guard action.isEnabled else { continue }
            let b = action.binding
            let key = "\(b.keyCode)-\(b.modifiers.rawValue)"
            guard seen.insert(key).inserted else { continue }
            bindings.append((b.keyCode, b.modifiers, action))
        }
        guard !bindings.isEmpty else { return }

        // Global path: Carbon RegisterEventHotKey fires from any frontmost app
        // and — unlike an NSEvent global keyboard monitor — needs no
        // Accessibility permission. This is the primary handler. See #217.
        for b in bindings {
            hotKeyManager.register(keyCode: b.keyCode, modifiers: b.mods) { [weak self] in
                Task { @MainActor in self?.executeShortcut(b.action) }
            }
        }

        // Local monitor: same-app fallback so the shortcut still works (and is
        // swallowed) while CodeIsland's own panel/settings window is focused.
        let localHandler: (NSEvent) -> Bool = { [weak self] event in
            let eventMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            for b in bindings where event.keyCode == b.keyCode && eventMods == b.mods {
                Task { @MainActor in self?.executeShortcut(b.action) }
                return true
            }
            return false
        }
        localShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            localHandler(event) ? nil : event
        }
    }

    private func teardownGlobalShortcut() {
        hotKeyManager.unregisterAll()
        if let m = localShortcutMonitor { NSEvent.removeMonitor(m) }
        localShortcutMonitor = nil
    }

    private func executeShortcut(_ action: ShortcutAction) {
        switch action {
        // Whatever the press opens comes to the user: onto the display they
        // work on, and up over a fullscreen app Hide in Fullscreen hid it
        // behind (#384).
        case .togglePanel:
            let away = panelController?.isIslandAwayFromUser ?? false
            if appState.togglePanelFromShortcut(islandAway: away) != .collapsed {
                panelController?.bringIslandIntoSight()
            }
        // Card shortcuts act only on the card on screen (#308); with the
        // request hidden they open its card instead of acting unseen.
        case .approve, .approveAlways, .deny, .skipQuestion:
            let onScreen = panelController?.isIslandOnScreen ?? true
            if case .opened = appState.performCardShortcut(action, islandOnScreen: onScreen) {
                panelController?.bringIslandIntoSight()
            }
        case .jumpToTerminal:
            if let id = appState.activeSessionId, let session = appState.sessions[id] {
                TerminalActivator.activate(session: session, sessionId: id)
            }
        }
    }

    func updateHooks(_ enabled: Bool) {
        if !enabled {
            hookServer?.stop()
            hookServer = nil
            hooksListening = false
        } else if host != nil, hookServer == nil {
            let server = HookServer(appState: appState, autoApproveTools: [])
            if server.start() {
                hookServer = server
                hooksListening = true
            }
        }
    }
}

@MainActor
final class CodeIslandPlugin: DeckPlugin, DeckPluginSettingsWindow {
    let manifest = PluginManifest(id: pluginID, name: "CodeIsland", summary: "wxtsky/CodeIsland 原生刘海面板与会话状态", symbol: "terminal", version: "1.2.2", category: .tools, enabledByDefault: false, sortOrder: 399)
    private var runtime: CodeIslandRuntime?

    func openSettingsWindow(host: any DeckHost) {
        HostedCodeIslandSettingsWindow.shared.show(appState: runtime?.appState, openUpdates: { [weak host] in
            host?.openSettings(pluginID: "__updates__")
        })
    }

    func activate(host: any DeckHost) {
        guard !host.isDryRun else { _ = Bundle.appModule; return }
        let runtime = CodeIslandRuntime()
        self.runtime = runtime
        runtime.start(host: host)
    }

    func deactivate() {
        runtime?.stop()
        runtime = nil
    }

    var sections: [DeckSection] {
        [DeckSection(id: "codeisland", title: "CodeIsland") {
            DeckTitleRow("CodeIsland", value: DeckL("刘海面板", "Notch panel"))
        } detail: {
            DeckCard {
                Button(DeckL("打开 CodeIsland", "Open CodeIsland")) { self.runtime?.revealIsland() }
            }
        }]
    }

    var settingsView: AnyView? {
        guard let runtime else { return nil }
        return AnyView(HostedIslandSettings(runtime: runtime))
    }
}

private struct HostedIslandSettings: View {
    @ObservedObject var runtime: CodeIslandRuntime
    @AppStorage(showsIslandKey) private var showsIsland = true
    @AppStorage(usesHooksKey) private var usesHooks = false

    var body: some View {
        Toggle(DeckL("显示 CodeIsland 刘海面板", "Show CodeIsland notch panel"), isOn: $showsIsland)
            .onChange(of: showsIsland) { _, visible in runtime.updateIsland(visible) }
        Toggle(DeckL("接收本机 CodeIsland Hook", "Receive local CodeIsland hooks"), isOn: $usesHooks)
            .onChange(of: usesHooks) { _, enabled in runtime.updateHooks(enabled) }
        if usesHooks {
            Text(runtime.hooksListening ? DeckL("正在接收已配置的本机 Hook。", "Listening for configured local hooks.")
                 : DeckL("无法启动本机 Hook。检查是否已有 CodeIsland 实例。", "Local hook listener unavailable. Check for an existing CodeIsland instance."))
                .font(.footnote).foregroundStyle(.secondary)
        }
        Button(DeckL("打开刘海面板", "Open notch panel")) { runtime.revealIsland() }
        Button(DeckL("检查插件更新", "Check plugin updates")) { runtime.openUpdates() }
        Link("wxtsky/CodeIsland", destination: URL(string: "https://github.com/wxtsky/CodeIsland")!)
    }
}

@_cdecl("statusdeck_plugin_create")
public func statusdeckPluginCreate() -> UnsafeMutableRawPointer { DeckPluginExport.retained { CodeIslandPlugin() } }
