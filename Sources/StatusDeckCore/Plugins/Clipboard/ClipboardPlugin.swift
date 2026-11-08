import AppKit
import Carbon
import Combine
import StatusDeckKit
import SwiftUI
import UniformTypeIdentifiers

/// The state both clipboard views share. Disk work happens off the main thread.
@MainActor
final class ClipboardModel: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var totalCount = 0
    @Published private(set) var totalBytes = 0
    @Published private(set) var access: ClipboardAccess = .allowed
    @Published private(set) var isDryRun = false
    @Published var query = "" { didSet { reload() } }
    @Published var filter: ClipFilter = .all { didSet { reload() } }
    @Published private(set) var sources: [ClipboardSource] = []
    @Published var sourceFilter: String? { didSet { reload() } }
    @Published var selectedID: Int64?
    @Published var isPaused: Bool { didSet { defaults.set(isPaused, forKey: "paused"); pushOptions() } }
    @Published var retentionDays: Int { didSet { defaults.set(retentionDays, forKey: "retentionDays"); pushOptions() } }
    @Published var maximumItems: Int { didSet { defaults.set(maximumItems, forKey: "maximumItems"); pushOptions() } }
    @Published var blockedApps: [String] { didSet { defaults.set(blockedApps, forKey: "blockedApps"); pushOptions() } }

    private let defaults = PluginDefaults(pluginID: "com.statusdeck.clipboard")
    private var store: ClipboardStore?
    private var capture: ClipboardCapture?
    private let ioQueue = DispatchQueue(label: "statusdeck.clipboard.model", qos: .userInitiated)

    /// Called after an entry has been put back on the clipboard.
    var onCopied: (() -> Void)?

    init() {
        isPaused = defaults.bool("paused", default: false)
        retentionDays = defaults.int("retentionDays", default: 30)
        maximumItems = defaults.int("maximumItems", default: 1000)
        blockedApps = defaults.strings("blockedApps") ?? ClipboardPrivacy.defaultBlockedApps
    }

    func start(host: any DeckHost, pluginID: String) {
        isDryRun = host.isDryRun
        // `--sample-clipboard` checks the real windows without showing real history.
        let usesSamples = host.isDryRun || CommandLine.arguments.contains("--sample-clipboard")
        let directory = usesSamples
            ? FileManager.default.temporaryDirectory.appendingPathComponent("statusdeck-sample-\(UUID().uuidString)")
            : host.storageDirectory(for: pluginID)
        guard let store = try? ClipboardStore(directory: directory) else { return }
        self.store = store

        if usesSamples {
            // Screenshots show invented entries, never what is really on this clipboard.
            ClipboardSamples.insert(into: store)
        } else {
            let capture = ClipboardCapture(pasteboard: .general, store: store)
            capture.onChange = { [weak self] in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.reload() }
                }
            }
            self.capture = capture
            pushOptions()
            capture.start()
        }
        reload()
    }

    func stop() {
        capture?.stop()
        capture = nil
        store = nil
        items = []
    }

    func refreshAccess() {
        access = isDryRun ? .allowed : ClipboardAccess.current(for: .general)
    }

    private var retentionAge: TimeInterval? {
        retentionDays > 0 ? TimeInterval(retentionDays) * 86400 : nil
    }

    private func pushOptions() {
        capture?.setOptions(ClipboardCapture.Options(
            isPaused: isPaused,
            blockedApps: Set(blockedApps),
            maximumItems: maximumItems,
            maximumAge: retentionAge
        ))
    }

    func reload() {
        guard let store else { return }
        let query = query
        let filter = filter
        let source = sourceFilter
        ioQueue.async { [weak self] in
            let items = store.fetch(query: query, filter: filter, source: source)
            let sources = store.sources()
            let count = store.count()
            let bytes = store.totalBytes()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.store === store, self.query == query,
                          self.filter == filter, self.sourceFilter == source else { return }
                    self.items = items
                    self.sources = sources
                    self.totalCount = count
                    self.totalBytes = bytes
                    if self.selectedID == nil || !items.contains(where: { $0.id == self.selectedID }) {
                        self.selectedID = items.first?.id
                    }
                }
            }
        }
    }

    func copy(_ item: ClipboardItem, afterCopy: (() -> Void)? = nil) {
        guard let capture else {
            onCopied?()
            return
        }
        ioQueue.async { [weak self] in
            let restored = capture.restore(item.id)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.capture === capture, restored else { return }
                    self.onCopied?()
                    afterCopy?()
                    self.reload()
                }
            }
        }
    }

    func dragProvider(for item: ClipboardItem) -> NSItemProvider {
        guard !isDryRun, let store else { return NSItemProvider() }
        if item.kind == .file, let path = item.text?.split(separator: "\n").first {
            return NSItemProvider(object: URL(fileURLWithPath: String(path)) as NSURL)
        }
        let provider = NSItemProvider()
        provider.suggestedName = item.kind == .image ? "Clipboard Image" : nil
        for type in store.firstItemTypes(of: item.id) where UTType(type) != nil {
            provider.registerDataRepresentation(forTypeIdentifier: type, visibility: .all) { [ioQueue] complete in
                ioQueue.async {
                    let data = store.representations(of: item.id).first { $0.itemIndex == 0 && $0.type == type }?.data
                    complete(data, data == nil ? CocoaError(.fileNoSuchFile) : nil)
                }
                return nil
            }
        }
        return provider
    }

    func importDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !isDryRun, let store else { return false }
        let accepted = [.fileURL, .url, .png, .jpeg, .tiff, .utf8PlainText] as [UTType]
        let selected = providers.prefix(32).compactMap { provider in
            accepted.first { provider.hasItemConformingToTypeIdentifier($0.identifier) }.map { (provider, $0) }
        }
        guard !selected.isEmpty else { return false }
        let maximumItems = maximumItems
        let maximumAge = retentionAge
        for (provider, type) in selected {
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { [weak self, ioQueue] data, _ in
                guard let data else { return }
                ioQueue.async {
                    let flavors = type == .url
                        ? [(UTType.utf8PlainText.identifier, data), (type.identifier, data)]
                        : [(type.identifier, data)]
                    guard let payload = ClipboardPayload.make(items: [flavors], maxBytes: 32 * 1024 * 1024) else { return }
                    store.insert(payload, sourceBundleID: nil, sourceName: nil)
                    store.purge(maximumItems: maximumItems, maximumAge: maximumAge)
                    DispatchQueue.main.async { self?.reload() }
                }
            }
        }
        return true
    }

    func togglePin(_ item: ClipboardItem) {
        guard let store else { return }
        ioQueue.async { [weak self] in
            store.setPinned(item.id, !item.isPinned)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.reload() }
            }
        }
    }

    func delete(_ item: ClipboardItem) {
        guard let store else { return }
        ioQueue.async { [weak self] in
            store.delete(item.id)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.reload() }
            }
        }
    }

    func clearHistory(keepingPinned: Bool) {
        guard let store else { return }
        ioQueue.async { [weak self] in
            store.deleteAll(keepingPinned: keepingPinned)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.reload() }
            }
        }
    }

    // MARK: - Keyboard browsing

    func moveSelection(by offset: Int) {
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selectedID } ?? 0
        selectedID = items[max(0, min(items.count - 1, current + offset))].id
    }

    var selectedItem: ClipboardItem? {
        items.first { $0.id == selectedID }
    }
}

final class ClipboardPlugin: BuiltInPlugin {
    private let model = ClipboardModel()
    private var browser: ClipboardBrowserController?
    private var hotKeyToken: DeckHotKeyToken?
    private let defaults = PluginDefaults(pluginID: "com.statusdeck.clipboard")
    private let hotKeyModel = HotKeyModel()

    static let defaultHotKey = DeckHotKey(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | optionKey), label: "⌃⌥V")

    init(services: SharedServices) {
        super.init(manifest: PluginManifest(
            id: "com.statusdeck.clipboard",
            name: "侧边栏剪贴板",
            summary: "插件 1 · 剪贴板侧边栏。记录复制过的文本、链接、颜色、图片和文件，可搜索、置顶，按快捷键随时调出。全部只保存在这台 Mac 上。",
            symbol: "doc.on.clipboard",
            category: .tools,
            sortOrder: 390,
            permissions: [
                "macOS 可能在读取剪贴板时询问是否允许，可以在“隐私与安全性”里设为始终允许。",
                "不记录密码管理器标记为保密的内容，也不记录屏蔽名单里的应用。"
            ]
        ), services: services)
        hotKeyModel.hotKey = storedHotKey
    }

    private var storedHotKey: DeckHotKey {
        defaults.data("hotKey").flatMap { try? JSONDecoder().decode(DeckHotKey.self, from: $0) } ?? Self.defaultHotKey
    }

    override func didActivate() {
        guard let host else { return }
        model.onCopied = { [weak self] in
            self?.browser?.close()
            self?.host?.closePanel()
        }
        model.start(host: host, pluginID: manifest.id)
        model.refreshAccess()
        guard !host.isDryRun else { return }
        browser = ClipboardBrowserController(model: model)
        registerHotKey()
    }

    override func willDeactivate() {
        hotKeyToken = nil
        browser?.close()
        browser = nil
        model.stop()
    }

    override func panelVisibilityChanged(_ isVisible: Bool) {
        if isVisible {
            model.refreshAccess()
            model.reload()
        }
    }

    func showBrowser() {
        browser?.show()
    }

    private func registerHotKey() {
        hotKeyToken = nil
        let hotKey = storedHotKey
        hotKeyToken = host?.registerHotKey(hotKey) { [weak self] in
            self?.browser?.toggle()
        }
        hotKeyModel.hotKey = hotKey
        hotKeyModel.failed = hotKeyToken == nil
    }

    override var sections: [DeckSection] {
        [DeckSection(id: "clipboard", title: DeckL("剪贴板")) {
            ClipboardRow(model: model)
        } detail: {
            DeckCard {
                ClipboardPanelSection(model: model, hotKey: hotKeyModel) { [weak self] in
                    self?.host?.closePanel()
                    self?.browser?.show()
                }
            }
        }]
    }

    override var settingsView: AnyView? {
        AnyView(ClipboardSettings(model: model, hotKey: hotKeyModel) { [weak self] newHotKey in
            guard let self else { return }
            self.defaults.set(try? JSONEncoder().encode(newHotKey), forKey: "hotKey")
            self.registerHotKey()
        })
    }
}

/// Observable wrapper, so that the panel and the settings show the same shortcut.
@MainActor
final class HotKeyModel: ObservableObject {
    @Published var hotKey = ClipboardPlugin.defaultHotKey
    @Published var failed = false
}

/// Invented entries for `--snapshot`.
enum ClipboardSamples {
    static func insert(into store: ClipboardStore) {
        func flavor(_ text: String) -> [[(type: String, data: Data)]] {
            [[(PasteboardType.plainText, Data(text.utf8))]]
        }
        let now = Date()
        let samples: [(String, String, String, TimeInterval)] = [
            (DeckL("会议纪要：周五前把第三版方案发给大家，附上预算表。"), DeckL("备忘录"), "com.apple.Notes", 60),
            ("https://example.com/articles/plugin-architecture", "Safari", "com.apple.Safari", 600),
            ("#2B7DF6", "Figma", "com.figma.Desktop", 3000),
            ("func greet(name: String) -> String {\n    let text = \"Hello, \\(name)\"\n    return text;\n}", "Xcode", "com.apple.dt.Xcode", 9000)
        ]
        for (text, name, bundle, age) in samples.reversed() {
            if let payload = ClipboardPayload.make(items: flavor(text), maxBytes: 1 << 20) {
                store.insert(payload, sourceBundleID: bundle, sourceName: name, now: now.addingTimeInterval(-age))
            }
        }
        let file = [[(type: PasteboardType.fileURL, data: Data("file:///Users/example/Documents/%E6%8A%A5%E5%91%8A.pdf".utf8))]]
        if let payload = ClipboardPayload.make(items: file, maxBytes: 1 << 20),
           let row = store.insert(payload, sourceBundleID: "com.apple.finder", sourceName: DeckL("访达"), now: now.addingTimeInterval(-90000)) {
            store.setPinned(row.id, true)
        }
    }
}
