import AppKit
import Combine
import StatusDeckKit
import SwiftUI

public enum StatusDeckApp {
    @MainActor
    public static func run() {
        let arguments = CommandLine.arguments

        if arguments.contains("--diagnose-cpu") {
            Diagnostics.runCPU()
            return
        }

        if arguments.contains("--diagnose-audio") {
            Diagnostics.runAudio(write: arguments.contains("--write"))
            return
        }
        if arguments.contains("--diagnose-softvolume") {
            Diagnostics.runSoftwareVolume()
            return
        }
        if arguments.contains("--diagnose-keys") {
            Diagnostics.runKeys()
            return
        }
        // `--verify-plugin <folder>` loads a plugin the way the app would and reports.
        if let index = arguments.firstIndex(of: "--verify-plugin"), arguments.indices.contains(index + 1) {
            exit(PluginVerifier.run(folder: URL(fileURLWithPath: arguments[index + 1])))
        }
        let application = NSApplication.shared
        // `--snapshot <folder>` draws every view to PNG files with invented clipboard
        // data, which is how the interface can be checked without opening any menu.
        if let index = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(index + 1) {
            let renderer = SnapshotRenderer(folder: URL(fileURLWithPath: arguments[index + 1]))
            renderer.start()
            application.run()
            return
        }

        // A renamed upgrade must replace the old process rather than silently exit
        // and leave its old keyboard handler running. Quit gracefully so software
        // audio returns its device before the new instance starts.
        guard prepareSingleInstance(replacingRunningInstance: arguments.contains("--replace-running-instance")) else { return }

        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }

    @MainActor
    private static func prepareSingleInstance(replacingRunningInstance: Bool) -> Bool {
        guard let identifier = Bundle.main.bundleIdentifier else { return true }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .filter { $0 != NSRunningApplication.current }
        guard !others.isEmpty else { return true }
        let here = Bundle.main.bundleURL.standardizedFileURL
        let currentBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let currentBuild,
           let newer = others.first(where: { app in
               guard let url = app.bundleURL, url.standardizedFileURL != here,
                     let build = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String else { return false }
               return build.compare(currentBuild, options: .numeric) == .orderedDescending
           }) {
            newer.activate(options: [.activateIgnoringOtherApps])
            return false
        }
        if !replacingRunningInstance,
           let sameCopy = others.first(where: { $0.bundleURL?.standardizedFileURL == here }) {
            sameCopy.activate(options: [.activateIgnoringOtherApps])
            return false
        }
        for previous in others { _ = previous.terminate() }
        let deadline = Date().addingTimeInterval(4)
        while others.contains(where: { !$0.isTerminated }), Date() < deadline {
            RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(0.05)))
        }
        guard others.allSatisfy(\.isTerminated) else {
            let alert = NSAlert()
            alert.messageText = DeckL("请先退出旧版本", "Please quit the previous version")
            alert.informativeText = DeckL("旧版本尚未退出。请退出 StatusDeck 或旧的 MyStatus，然后重新打开此版本。", "The previous version is still running. Quit StatusDeck or the older MyStatus, then open this version again.")
            alert.addButton(withTitle: DeckL("知道了", "OK"))
            alert.runModal()
            return false
        }
        return true
    }
}

/// The host: what plugins see as `DeckHost`, and the owner of everything around them.
@MainActor
final class HostController: DeckHost {
    let services: SharedServices
    let state = PanelState()
    let appPreferences = AppPreferences()
    let isDryRun: Bool

    private(set) var manager: PluginManager!
    private(set) var panel: PanelController!
    private var statusBar: StatusBarController?
    private let hud = HUDController()
    private let hotKeys = HotKeyCenter()
    private var settingsWindow: NSWindow?
    private var settingsSelection = SettingsSelectionModel()
    private var appearanceCancellable: AnyCancellable?

    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StatusDeck", isDirectory: true)
    }

    init(isDryRun: Bool = false) {
        self.isDryRun = isDryRun
        services = SharedServices(isDryRun: isDryRun)
        manager = PluginManager(
            host: self,
            builtIns: BuiltInPlugins.all(services: services),
            pluginsDirectory: Self.supportDirectory.appendingPathComponent("Plugins", isDirectory: true)
        )
        panel = PanelController(
            manager: manager,
            store: services.store,
            state: state,
            onOpenSettings: { [weak self] selection in self?.openSettings(pluginID: selection) },
            onVisibilityChange: { [weak self] visible in
                self?.services.store.setPanelVisible(visible)
                self?.manager.panelVisibilityChanged(visible)
            }
        )
        appPreferences.onIntervalChange = { [weak self] interval in
            self?.services.store.sampler.setInterval(interval)
        }
        services.store.sampler.setInterval(appPreferences.refreshInterval)
        // The uptime in the panel's header, whichever plugins are on.
        services.store.sampler.setInterest(owner: "host.panel", whilePanelVisible: [.system])
        appearanceCancellable = state.$appearance.sink { [weak self] appearance in
            MainActor.assumeIsolated {
                FloatingPanel.sharedAppearance = appearance.nsAppearance
                self?.settingsWindow?.appearance = appearance.nsAppearance
            }
        }
    }

    func start() {
        if !isDryRun { DeckLoginItemController.shared.applyDefaultIfNeeded() }
        statusBar = StatusBarController(manager: manager, panel: panel) { [weak self] in
            self?.openSettings(pluginID: nil)
        }
        if !isDryRun, let screen = NSScreen.main {
            manager.fitFirstRunPanel(to: screen.visibleFrame.height)
        }
        manager.start()
        UserDefaults.standard.set(false, forKey: "updates.pendingRestart")
    }

    func stop() {
        manager.stop()
    }

    // MARK: - DeckHost

    var isPanelVisible: Bool { panel.isOpen }

    func storageDirectory(for pluginID: String) -> URL {
        let url = Self.supportDirectory
            .appendingPathComponent("PluginData", isDirectory: true)
            .appendingPathComponent(pluginID, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// With the panel open the slider itself shows the change, and the HUD would sit
    /// on top of it.
    func showLevel(symbol: String, value: Double, title: String?) {
        guard !panel.isOpen else { return }
        hud.show(symbol: symbol, value: value, title: title)
    }

    func openPanel(showing sectionID: String?) {
        panel.open(from: statusBar?.primaryButton, showing: sectionID)
    }

    func closePanel() {
        panel.close()
    }

    func openSettings(pluginID: String?) {
        panel.close()
        settingsSelection.value = pluginID ?? settingsSelection.value ?? PluginSettingsSelection.general
        if settingsWindow == nil {
            let root = SettingsContainer(manager: manager, state: state, selection: settingsSelection,
                                         appPreferences: appPreferences, authorization: services.systemControls, isPreview: isDryRun,
                                         openPanelPreview: { [weak self] in self?.openPanel(showing: nil) })
            let window = NSWindow(contentViewController: NSHostingController(rootView: root))
            window.title = isDryRun ? "MyStatus — 界面预览" : "MyStatus"
            window.setContentSize(SettingsWindowSize.initial)
            window.minSize = SettingsWindowSize.minimum
            // Full-size content lets the sidebar float as glass over the window.
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.appearance = state.appearance.nsAppearance
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func pluginContentDidChange() {
        manager.pluginContentDidChange()
    }

    func showClipboardBrowser() {
        manager.activePlugins.compactMap { $0 as? ClipboardPlugin }.first?.showBrowser()
    }

    func registerHotKey(_ hotKey: DeckHotKey, handler: @escaping () -> Void) -> DeckHotKeyToken? {
        hotKeys.register(hotKey, handler: handler)
    }
}

@MainActor
final class SettingsSelectionModel: ObservableObject {
    @Published var value: String?
}

private struct SettingsContainer: View {
    @ObservedObject var manager: PluginManager
    @ObservedObject var state: PanelState
    @ObservedObject var selection: SettingsSelectionModel
    @ObservedObject var appPreferences: AppPreferences
    @ObservedObject var authorization: SystemControlAuthorization
    let isPreview: Bool
    let openPanelPreview: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        DeckThemeRoot {
            SettingsRootView(manager: manager, state: state, selection: $selection.value, appPreferences: appPreferences,
                             authorization: authorization, isPreview: isPreview, openPanelPreview: openPanelPreview)
        }
        .environment(\.colorScheme, state.appearance.colorScheme(following: colorScheme))
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let isPreview = Bundle.main.object(forInfoDictionaryKey: "StatusDeckPreview") as? Bool ?? false
    private lazy var host = HostController(isDryRun: isPreview)

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isPreview {
            for entry in host.manager.entries { host.manager.setEnabled(false, id: entry.id) }
        }
        host.start()
        // For checking the interface without reaching for the menu bar.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [host, self] in
            MainActor.assumeIsolated {
                let arguments = CommandLine.arguments
                if arguments.contains("--open-panel") {
                    let index = arguments.firstIndex(of: "--open-flyout")
                    host.openPanel(showing: index.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil })
                }
                if arguments.contains("--open-settings") || self.isPreview { host.openSettings(pluginID: nil) }
                if arguments.contains("--open-clipboard") { host.showClipboardBrowser() }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        host.openSettings(pluginID: nil)
        return false
    }

    /// Software volume has to hand the audio path back before the process goes.
    func applicationWillTerminate(_ notification: Notification) {
        host.stop()
    }
}

/// Loads a plugin the way the app would, for plugin authors and for testing.
@MainActor
enum PluginVerifier {
    static func run(folder: URL) -> Int32 {
        let discovered = ExternalPluginLoader.read(folder)
        if let problem = discovered.problem {
            print("FAILED manifest: \(problem.message)")
            return 1
        }
        print("manifest ok: \(discovered.file?.id ?? "?") \(discovered.file?.version ?? "")")
        switch ExternalPluginLoader.load(discovered) {
        case let .failure(error):
            print("FAILED load: \(error.message)")
            return 1
        case let .success(plugin):
            let host = PluginVerificationHost()
            plugin.activate(host: host)
            print("activated: sections=\(plugin.sections.map(\.title)) settings=\(plugin.settingsView != nil) menuBar=\(plugin.menuBarItem != nil)")
            plugin.deactivate()
            print("deactivated: ok")
            return 0
        }
    }
}

/// Verification is a command-line operation and must not connect to WindowServer.
/// In-app source updates use this too, before replacing the installed library.
@MainActor
private final class PluginVerificationHost: DeckHost {
    let isPanelVisible = false
    let isDryRun = true
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StatusDeck-verify-" + UUID().uuidString)
    func storageDirectory(for pluginID: String) -> URL {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    func showLevel(symbol: String, value: Double, title: String?) {}
    func openPanel(showing sectionID: String?) {}
    func closePanel() {}
    func openSettings(pluginID: String?) {}
    func pluginContentDidChange() {}
    func registerHotKey(_ hotKey: DeckHotKey, handler: @escaping () -> Void) -> DeckHotKeyToken? { nil }
    deinit { try? FileManager.default.removeItem(at: directory) }
}

/// Draws the real views, fed by real samples, into PNG files.
@MainActor
final class SnapshotRenderer {
    private let folder: URL
    private let host = HostController(isDryRun: true)

    init(folder: URL) { self.folder = folder }

    func start() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for entry in host.manager.entries where entry.plugin != nil {
            // Everything on, whatever this Mac's settings say, without saving that.
            entry.plugin?.activate(host: host)
        }
        host.services.store.setPanelVisible(true)
        for entry in host.manager.entries { entry.plugin?.panelVisibilityChanged(true) }
        // Rate and residency readings need a few intervals, and DDC reads need time.
        DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [self] in
            MainActor.assumeIsolated {
                renderAll()
                for entry in host.manager.entries { entry.plugin?.deactivate() }
                NSApp.terminate(nil)
            }
        }
    }

    private func renderAll() {
        let plugins = host.manager.entries.compactMap(\.plugin).sorted { $0.manifest.sortOrder < $1.manifest.sortOrder }
        let sections = plugins.flatMap(\.sections)
        for (scheme, label) in [(ColorScheme.dark, "dark"), (ColorScheme.light, "light")] {
            if let clipboard = plugins.compactMap({ $0 as? ClipboardPlugin }).first {
                render(clipboard.browserSnapshot.frame(width: 400, height: 850), scheme: scheme, name: "\(label)-clipboard-shelf")
            }
            var transfer = TransferHistory()
            for index in 0..<60 {
                let phase = Double(index)
                transfer.append(120_000 + 108_000 * abs(sin(phase * 0.23)),
                                3_500_000 + 3_600_000 * abs(cos(phase * 0.17)), at: phase)
            }
            render(TransferActivityCard(title: DeckL("网速历史", "Speed history"), firstLabel: DeckL("上传"),
                                        secondLabel: DeckL("下载"), first: 228_000, second: 7_100_000,
                                        history: transfer, floor: 64_000, expanded: true)
                .padding(12).frame(width: DeckTheme.flyoutWidth + 24), scheme: scheme, name: "\(label)-transfer-scales")
            let rows = PanelTileGrid(sections: sections, store: host.services.store, hover: PanelHoverModel(),
                                     onOpenSettings: {}, onOpenDetail: { _ in })
            render(rows.padding(12).frame(width: DeckTheme.panelWidth + 24), scheme: scheme, name: "\(label)-panel")
            for section in sections {
                guard let detail = section.detail else { continue }
                render(detail.padding(12).frame(width: DeckTheme.flyoutWidth + 24), scheme: scheme, name: "\(label)-\(section.id)")
            }
        }
        renderMenuBarImages(plugins: plugins)
        print("sections:", sections.map(\.title))
        print("plugins:", plugins.map { "\($0.manifest.name)" })
    }

    private func render<Content: View>(_ view: Content, scheme: ColorScheme, name: String) {
        let themed = DeckThemeRoot { view }
            .environment(\.colorScheme, scheme)
            .environment(\.deckUsesGlass, false)
            .background(scheme == .dark ? Color(white: 0.32) : Color(white: 0.84))
        let renderer = ImageRenderer(content: themed)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: folder.appendingPathComponent("\(name).png"))
        }
    }

    private func renderMenuBarImages(plugins: [any DeckPlugin]) {
        for plugin in plugins {
            guard let image = plugin.menuBarItem?.image else { continue }
            let scale: CGFloat = 4
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSColor.white.setFill()
            NSRect(origin: .zero, size: size).fill()
            image.draw(in: NSRect(origin: .zero, size: size))
            NSGraphicsContext.restoreGraphicsState()
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: folder.appendingPathComponent("menubar-\(plugin.manifest.id).png"))
            }
        }
    }
}
