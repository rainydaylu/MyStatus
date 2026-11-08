import AppKit
import SwiftUI

/// Every feature of StatusDeck, built-in or third-party, is a `DeckPlugin`.
///
/// The host decides when a plugin runs. A plugin that is off is never activated,
/// so it costs nothing: no timers, no permission prompts, no menu bar item.
public enum DeckPluginAPI {
    /// Raised whenever this module changes in a way that breaks compiled plugins.
    /// The host refuses to load a plugin built for a different version.
    public static let version = 2

    /// The symbol a third-party plugin exports. See `DeckPluginExport`.
    public static let entryPoint = "statusdeck_plugin_create"
}

public enum PluginCategory: String, Codable, CaseIterable, Sendable {
    case control
    case monitor
    case tools
    case menuBar

    public var title: String {
        switch self {
        case .control: DeckL("控制")
        case .monitor: DeckL("监控")
        case .tools: DeckL("工具")
        case .menuBar: DeckL("菜单栏")
        }
    }
}

public struct PluginManifest: Codable, Equatable, Identifiable, Sendable {
    /// Reverse-DNS and stable: settings and stored data are keyed by it.
    public var id: String
    public var name: String
    public var summary: String
    /// An SF Symbol name.
    public var symbol: String
    public var version: String
    public var category: PluginCategory
    public var enabledByDefault: Bool
    /// Position of its sections in the panel; lower comes first.
    public var sortOrder: Int
    /// Plain-language notes on the access it needs, shown before it is switched on.
    public var permissions: [String]

    public init(
        id: String,
        name: String,
        summary: String,
        symbol: String,
        version: String = "1.0",
        category: PluginCategory,
        enabledByDefault: Bool = true,
        sortOrder: Int = 500,
        permissions: [String] = []
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.symbol = symbol
        self.version = version
        self.category = category
        self.enabledByDefault = enabledByDefault
        self.sortOrder = sortOrder
        self.permissions = permissions
    }
}

/// One row of the panel, with an optional window of detail that opens beside the
/// panel while the pointer rests on the row.
public struct DeckSection: Identifiable {
    public let id: String
    public let title: String
    /// Always on show. Start it with a `DeckTitleRow` to match the built-in rows.
    public let row: AnyView
    /// Created when the window opens and released when it closes, so `onAppear` and
    /// `onDisappear` can start and stop whatever only it needs.
    public let detail: AnyView?

    public init<Row: View, Detail: View>(
        id: String,
        title: String,
        @ViewBuilder row: () -> Row,
        @ViewBuilder detail: () -> Detail
    ) {
        self.id = id
        self.title = title
        self.row = AnyView(row())
        self.detail = AnyView(detail())
    }

    /// A row with nothing further to show.
    public init<Row: View>(id: String, title: String, @ViewBuilder row: () -> Row) {
        self.id = id
        self.title = title
        self.row = AnyView(row())
        self.detail = nil
    }
}

/// A menu bar icon owned by a plugin. Clicking it opens the panel.
@MainActor
public final class DeckMenuBarItem: ObservableObject {
    @Published public var image: NSImage?
    /// Scrolling over the icon; the argument is a fraction of the full range.
    public var onScroll: ((Double) -> Void)?

    public init(image: NSImage? = nil) {
        self.image = image
    }
}

/// A global keyboard shortcut. `label` is what the settings show, for example "⌃⌥V".
public struct DeckHotKey: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    /// Carbon modifier flags, as `RegisterEventHotKey` takes them.
    public var modifiers: UInt32
    public var label: String

    public init(keyCode: UInt32, modifiers: UInt32, label: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.label = label
    }
}

/// Unregisters its shortcut when released.
@MainActor
public protocol DeckHotKeyToken: AnyObject {}

/// What the host offers a running plugin.
@MainActor
public protocol DeckHost: AnyObject {
    var isPanelVisible: Bool { get }
    /// True while drawing screenshots: a plugin must not touch real user data then.
    var isDryRun: Bool { get }
    /// A private folder that survives restarts, created on demand.
    func storageDirectory(for pluginID: String) -> URL
    /// The on-screen level indicator, for changes with no control in view. `title`
    /// says what is changing, such as the name of a monitor.
    func showLevel(symbol: String, value: Double, title: String?)
    /// Opens the panel, and the detail window of a section if one is named.
    func openPanel(showing sectionID: String?)
    func closePanel()
    func openSettings(pluginID: String?)
    /// Call when `sections` or `menuBarItem` return something new.
    func pluginContentDidChange()
    /// Nil when macOS refuses the shortcut, usually because another app holds it.
    func registerHotKey(_ hotKey: DeckHotKey, handler: @escaping () -> Void) -> DeckHotKeyToken?
}

/// Everything except `manifest`, `activate` and `deactivate` is optional.
@MainActor
public protocol DeckPlugin: AnyObject {
    var manifest: PluginManifest { get }

    /// Start working. Only called while the user has the plugin switched on.
    func activate(host: any DeckHost)
    /// Stop everything and release system resources. The plugin may be activated again.
    func deactivate()

    /// The panel opened or closed. Stop panel-only work while it is closed.
    func panelVisibilityChanged(_ isVisible: Bool)

    var sections: [DeckSection] { get }
    /// Shown under this plugin in the settings window.
    var settingsView: AnyView? { get }
    var menuBarItem: DeckMenuBarItem? { get }
}

public extension DeckPlugin {
    func panelVisibilityChanged(_ isVisible: Bool) {}
    var sections: [DeckSection] { [] }
    var settingsView: AnyView? { nil }
    var menuBarItem: DeckMenuBarItem? { nil }
}

/// For the single C function a third-party plugin exports:
///
///     @_cdecl("statusdeck_plugin_create")
///     public func statusdeckPluginCreate() -> UnsafeMutableRawPointer {
///         DeckPluginExport.retained { MyPlugin() }
///     }
public enum DeckPluginExport {
    public static func retained(_ make: @MainActor () -> any DeckPlugin) -> UnsafeMutableRawPointer {
        MainActor.assumeIsolated {
            Unmanaged.passRetained(make() as AnyObject).toOpaque()
        }
    }

    /// The host's side of `retained`.
    public static func take(_ pointer: UnsafeMutableRawPointer) -> (any DeckPlugin)? {
        Unmanaged<AnyObject>.fromOpaque(pointer).takeRetainedValue() as? any DeckPlugin
    }
}

/// Settings namespaced by plugin, so that two plugins can never collide.
public struct PluginDefaults {
    private let prefix: String
    private let store: UserDefaults

    public init(pluginID: String, store: UserDefaults = .standard) {
        prefix = "plugin.\(pluginID)."
        self.store = store
    }

    public func bool(_ key: String, default fallback: Bool) -> Bool {
        store.object(forKey: prefix + key) as? Bool ?? fallback
    }

    public func double(_ key: String, default fallback: Double) -> Double {
        store.object(forKey: prefix + key) as? Double ?? fallback
    }

    public func int(_ key: String, default fallback: Int) -> Int {
        store.object(forKey: prefix + key) as? Int ?? fallback
    }

    public func string(_ key: String) -> String? {
        store.string(forKey: prefix + key)
    }

    public func strings(_ key: String) -> [String]? {
        store.stringArray(forKey: prefix + key)
    }

    public func data(_ key: String) -> Data? {
        store.data(forKey: prefix + key)
    }

    public func set(_ value: Any?, forKey key: String) {
        store.set(value, forKey: prefix + key)
    }
}
