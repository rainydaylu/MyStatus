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
    private(set) var panelController: PanelWindowController?
    @Published private(set) var hooksListening = false

    func start(host: any DeckHost) {
        self.host = host
        Self.current = self
        appState.startSessionDiscovery()
        appState.startCoworkWatcher()
        updateIsland(UserDefaults.standard.object(forKey: showsIslandKey) as? Bool ?? true)
        updateHooks(UserDefaults.standard.bool(forKey: usesHooksKey))
    }

    func stop() {
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

    func openSettings() { host?.openSettings(pluginID: pluginID) }
    func openUpdates() { host?.openSettings(pluginID: "__updates__") }

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
final class CodeIslandPlugin: DeckPlugin {
    let manifest = PluginManifest(id: pluginID, name: "CodeIsland", summary: "wxtsky/CodeIsland 原生刘海面板与会话状态", symbol: "terminal", version: "1.2", category: .tools, enabledByDefault: false, sortOrder: 399)
    private var runtime: CodeIslandRuntime?

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
