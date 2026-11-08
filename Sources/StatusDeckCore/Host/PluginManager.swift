import Combine
import CryptoKit
import Foundation
import StatusDeckKit
import SwiftUI

/// The `plugin.json` inside a third-party `.deckplugin` folder. It can be read
/// without running any of the plugin's code, which is what lets the settings list a
/// plugin before the user has decided to trust it.
struct ExternalPluginFile: Codable, Equatable {
    var id: String
    var name: String
    var summary: String?
    var symbol: String?
    var version: String?
    var category: PluginCategory?
    var sortOrder: Int?
    var permissions: [String]?
    var adapterRevision: Int?
    var apiVersion: Int
    /// The dynamic library's file name, relative to the plugin folder.
    var library: String

    var manifest: PluginManifest {
        PluginManifest(
            id: id,
            name: name,
            summary: summary ?? "",
            symbol: symbol ?? "puzzlepiece.extension",
            version: version ?? "1.0",
            category: category ?? .tools,
            enabledByDefault: false,
            sortOrder: sortOrder ?? 600,
            permissions: permissions ?? []
        )
    }
}

enum ExternalPluginError: Error, Equatable {
    case unreadableManifest
    case incompatibleAPI(found: Int)
    case missingLibrary
    case cannotLoad(String)
    case missingEntryPoint
    case wrongType
    case idMismatch(String)
    case duplicateID

    var message: String {
        switch self {
        case .unreadableManifest: DeckL("plugin.json 无法读取")
        case let .incompatibleAPI(found): DeckLF("为插件接口版本 %1$@ 构建，MyStatus 需要版本 %2$@。", "Built for plug-in API %1$@. MyStatus requires %2$@.", String(found), String(DeckPluginAPI.version))
        case .missingLibrary: DeckL("找不到插件的动态库")
        case let .cannotLoad(reason): DeckLF("无法加载：%@", "Could not load: %@", reason)
        case .missingEntryPoint: DeckLF("动态库没有导出 %@", "The library does not export %@", DeckPluginAPI.entryPoint)
        case .wrongType: DeckL("动态库返回的不是 DeckPlugin")
        case let .idMismatch(found): DeckLF("代码声明的 ID（%@）与 plugin.json 不一致。", "The declared ID (%@) does not match plugin.json.", found)
        case .duplicateID: DeckL("ID 与已有插件重复")
        }
    }
}

/// Finds and loads third-party plugins.
enum ExternalPluginLoader {
    struct Discovered: Equatable {
        let folder: URL
        let file: ExternalPluginFile?
        let problem: ExternalPluginError?

        var libraryURL: URL? { file.map { folder.appendingPathComponent($0.library) } }
    }

    static func discover(in directory: URL) -> [Discovered] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return contents
            .filter { $0.pathExtension == "deckplugin" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map(read)
    }

    static func read(_ folder: URL) -> Discovered {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("plugin.json")),
              let file = try? JSONDecoder().decode(ExternalPluginFile.self, from: data) else {
            return Discovered(folder: folder, file: nil, problem: .unreadableManifest)
        }
        if file.apiVersion != DeckPluginAPI.version {
            return Discovered(folder: folder, file: file, problem: .incompatibleAPI(found: file.apiVersion))
        }
        // The name comes from a file anyone could write, so it must stay inside the folder.
        let library = folder.appendingPathComponent(file.library).standardizedFileURL
        guard library.path.hasPrefix(folder.standardizedFileURL.path + "/"),
              FileManager.default.fileExists(atPath: library.path) else {
            return Discovered(folder: folder, file: file, problem: .missingLibrary)
        }
        return Discovered(folder: folder, file: file, problem: nil)
    }

    static func fingerprint(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Runs the plugin's code for the first time. A library stays mapped for the life
    /// of the process, so "disable" means deactivated, and replacing it needs a restart.
    @MainActor
    static func load(_ discovered: Discovered) -> Result<any DeckPlugin, ExternalPluginError> {
        guard let file = discovered.file, let library = discovered.libraryURL else {
            return .failure(.unreadableManifest)
        }
        guard let handle = dlopen(library.path, RTLD_NOW | RTLD_LOCAL) else {
            return .failure(.cannotLoad(dlerror().map { String(cString: $0) } ?? DeckL("未知错误")))
        }
        guard let symbol = dlsym(handle, DeckPluginAPI.entryPoint) else {
            return .failure(.missingEntryPoint)
        }
        typealias Entry = @convention(c) () -> UnsafeMutableRawPointer
        guard let plugin = DeckPluginExport.take(unsafeBitCast(symbol, to: Entry.self)()) else {
            return .failure(.wrongType)
        }
        guard plugin.manifest.id == file.id else {
            return .failure(.idMismatch(plugin.manifest.id))
        }
        return .success(plugin)
    }
}

/// Decides which plugins run. Everything goes through here, built-in or not.
@MainActor
final class PluginManager: ObservableObject {
    struct Entry: Identifiable {
        enum Source: Equatable {
            case builtIn
            case external(ExternalPluginLoader.Discovered)
        }

        var id: String { manifest.id }
        let manifest: PluginManifest
        let source: Source
        var plugin: (any DeckPlugin)?
        var isEnabled: Bool
        var isActive = false
        var problem: String?

        var isExternal: Bool {
            if case .external = source { return true }
            return false
        }

        var isOnPluginShelf: Bool { isExternal || id == "com.statusdeck.clipboard" }
    }

    @Published private(set) var entries: [Entry] = []
    /// Bumped when the panel's content may need rebuilding.
    @Published private(set) var contentVersion = 0
    /// What the last launch's crash recovery did, shown once in settings.
    @Published private(set) var notice: String?

    let pluginsDirectory: URL
    private let defaults: UserDefaults
    private weak var host: (any DeckHost)?

    @Published private var panelOrder: [String]
    private static let panelOrderKey = "pluginManager.panelOrder"
    private static let activatingKey = "pluginManager.activating"
    private static let initialFitKey = "panel.didChooseInitialModules"

    init(host: any DeckHost, builtIns: [any DeckPlugin], pluginsDirectory: URL, defaults: UserDefaults = .standard) {
        self.host = host
        self.pluginsDirectory = pluginsDirectory
        self.defaults = defaults
        panelOrder = defaults.stringArray(forKey: Self.panelOrderKey) ?? []
        entries = builtIns.map { plugin in
            Entry(
                manifest: plugin.manifest,
                source: .builtIn,
                plugin: plugin,
                isEnabled: defaults.object(forKey: enabledKey(plugin.manifest.id)) as? Bool ?? plugin.manifest.enabledByDefault
            )
        }
    }

    private func enabledKey(_ id: String) -> String { "plugin.enabled.\(id)" }
    private func fingerprintKey(_ id: String) -> String { "plugin.approvedFingerprint.\(id)" }

    /// The settings sidebar and main panel share this order, including positions
    /// reserved for disabled plugins.
    var orderedEntries: [Entry] {
        let positions = Dictionary(panelOrder.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return entries.sorted { lhs, rhs in
            if lhs.isOnPluginShelf != rhs.isOnPluginShelf { return !lhs.isOnPluginShelf }
            let left = lhs.isOnPluginShelf ? Int.max : positions[lhs.id] ?? Int.max
            let right = rhs.isOnPluginShelf ? Int.max : positions[rhs.id] ?? Int.max
            if left != right { return left < right }
            if lhs.manifest.sortOrder != rhs.manifest.sortOrder { return lhs.manifest.sortOrder < rhs.manifest.sortOrder }
            return lhs.id < rhs.id
        }
    }

    var activePlugins: [any DeckPlugin] {
        orderedEntries.filter(\.isActive).compactMap(\.plugin)
    }

    func movePanelEntries(from offsets: IndexSet, to destination: Int) {
        var ids = orderedEntries.filter { !$0.isOnPluginShelf }.map(\.id)
        guard !offsets.isEmpty, offsets.allSatisfy(ids.indices.contains), (0...ids.count).contains(destination) else { return }
        ids.move(fromOffsets: offsets, toOffset: destination)
        panelOrder = ids
        defaults.set(ids, forKey: Self.panelOrderKey)
    }

    func fitFirstRunPanel(to screenHeight: CGFloat) {
        guard screenHeight > 0, !defaults.bool(forKey: Self.initialFitKey) else { return }
        defaults.set(true, forKey: Self.initialFitKey)
        // Older versions set this marker on every regular launch.
        guard defaults.object(forKey: "updates.pendingRestart") == nil,
              !entries.contains(where: { defaults.object(forKey: enabledKey($0.id)) != nil }) else { return }
        let hidden = PanelTileLayout.initialHiddenModules(orderedEntries.filter(\.isEnabled).map(\.id), screenHeight: screenHeight)
        for index in entries.indices where hidden.contains(entries[index].id) {
            entries[index].isEnabled = false
            defaults.set(false, forKey: enabledKey(entries[index].id))
        }
    }

    /// Discovers third-party plugins and activates whatever is on.
    func start() {
        recoverFromCrash()
        scanExternal()
        for index in entries.indices where entries[index].isEnabled {
            activate(at: index)
        }
        contentVersion += 1
    }

    func stop() {
        for index in entries.indices where entries[index].isActive {
            entries[index].plugin?.deactivate()
            entries[index].isActive = false
        }
    }

    /// If the app died while activating a plugin last time, that plugin is the prime
    /// suspect. Leaving it on would mean crashing again on every launch.
    private func recoverFromCrash() {
        guard let id = defaults.string(forKey: Self.activatingKey) else { return }
        defaults.removeObject(forKey: Self.activatingKey)
        defaults.set(false, forKey: enabledKey(id))
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].isEnabled = false
        }
        notice = DeckLF("上次启动时，插件“%@”导致应用退出，已自动关闭。", "The plug-in “%@” was disabled after it caused the app to quit at launch.", id)
    }

    /// Picks up new folders. A plugin that is already running keeps running.
    lazy var updates = PluginUpdateService(pluginDirectory: pluginsDirectory)

    func scanExternal() {
        var discovered = ExternalPluginLoader.discover(in: pluginsDirectory)
        if let bundledDirectory = Bundle.main.resourceURL?.appendingPathComponent("BundledPlugins") {
            let bundled = ExternalPluginLoader.discover(in: bundledDirectory)
            // A rebuilt upstream update must use an adapter at least as recent as
            // the bundled one. Keep older files on disk for the update UI.
            discovered.removeAll { installed in
                guard let file = installed.file else { return false }
                return bundled.contains { candidate in
                    candidate.problem == nil && candidate.file?.id == file.id &&
                    (candidate.file?.adapterRevision ?? 0) > (file.adapterRevision ?? 0)
                }
            }
            let installedIDs = Set(discovered.compactMap { $0.file?.id })
            discovered += bundled.filter { item in
                item.file.map { !installedIDs.contains($0.id) } ?? true
            }
        }
        entries.removeAll { $0.isExternal && !$0.isActive && $0.plugin == nil }

        for item in discovered {
            guard let file = item.file else {
                entries.append(Entry(
                    manifest: PluginManifest(id: "invalid.\(item.folder.lastPathComponent)", name: item.folder.lastPathComponent, summary: "", symbol: "exclamationmark.triangle", category: .tools, enabledByDefault: false),
                    source: .external(item),
                    isEnabled: false,
                    problem: item.problem?.message
                ))
                continue
            }
            if entries.contains(where: { $0.id == file.id }) {
                // Either already loaded, or claiming an ID that belongs to something else.
                if !entries.contains(where: { $0.id == file.id && $0.isExternal }) {
                    entries.append(Entry(
                        manifest: PluginManifest(id: "duplicate.\(file.id)", name: file.name, summary: file.summary ?? "", symbol: "exclamationmark.triangle", category: .tools, enabledByDefault: false),
                        source: .external(item),
                        isEnabled: false,
                        problem: ExternalPluginError.duplicateID.message
                    ))
                }
                continue
            }
            var entry = Entry(
                manifest: file.manifest,
                source: .external(item),
                isEnabled: defaults.bool(forKey: enabledKey(file.id)),
                problem: item.problem?.message
            )
            if item.problem != nil { entry.isEnabled = false }
            // Trust is given to these exact bytes: a library that changed since the
            // user approved it stays off until they approve it again.
            if entry.isEnabled, let library = item.libraryURL,
               ExternalPluginLoader.fingerprint(of: library) != defaults.string(forKey: fingerprintKey(file.id)) {
                entry.isEnabled = false
                entry.problem = DeckL("文件在你启用后发生了变化，需要重新确认才能运行。")
                defaults.set(false, forKey: enabledKey(file.id))
            }
            entries.append(entry)
        }
    }

    func setEnabled(_ enabled: Bool, id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        guard entries[index].problem == nil || !enabled || isTrustProblem(entries[index]) else { return }

        if enabled, case let .external(item) = entries[index].source, let library = item.libraryURL {
            defaults.set(ExternalPluginLoader.fingerprint(of: library), forKey: fingerprintKey(id))
            entries[index].problem = nil
        }
        defaults.set(enabled, forKey: enabledKey(id))
        entries[index].isEnabled = enabled

        if enabled {
            activate(at: index)
        } else if entries[index].isActive {
            entries[index].plugin?.deactivate()
            entries[index].isActive = false
        }
        contentVersion += 1
    }

    private func isTrustProblem(_ entry: Entry) -> Bool {
        guard case let .external(item) = entry.source else { return false }
        return item.problem == nil
    }

    private func activate(at index: Int) {
        guard !entries[index].isActive, let host else { return }

        if entries[index].plugin == nil, case let .external(item) = entries[index].source {
            // Between here and the end of activate() is where a bad plugin would crash.
            defaults.set(entries[index].id, forKey: Self.activatingKey)
            defaults.synchronize()
            switch ExternalPluginLoader.load(item) {
            case let .success(plugin):
                entries[index].plugin = plugin
            case let .failure(error):
                defaults.removeObject(forKey: Self.activatingKey)
                entries[index].problem = error.message
                entries[index].isEnabled = false
                defaults.set(false, forKey: enabledKey(entries[index].id))
                return
            }
        } else {
            defaults.set(entries[index].id, forKey: Self.activatingKey)
            defaults.synchronize()
        }

        entries[index].plugin?.activate(host: host)
        entries[index].isActive = true
        defaults.removeObject(forKey: Self.activatingKey)
    }

    func dismissNotice() {
        notice = nil
    }

    func pluginContentDidChange() {
        contentVersion += 1
    }

    func panelVisibilityChanged(_ isVisible: Bool) {
        for plugin in activePlugins { plugin.panelVisibilityChanged(isVisible) }
    }
}
