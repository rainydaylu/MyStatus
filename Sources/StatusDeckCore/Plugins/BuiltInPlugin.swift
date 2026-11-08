import StatusDeckKit
import SwiftUI

/// Built-in plugins use the same `DeckPlugin` protocol as third-party ones. The
/// only extra is access to `SharedServices`, which is not part of the public API.
@MainActor
class BuiltInPlugin: DeckPlugin {
    let manifest: PluginManifest
    let services: SharedServices
    private(set) weak var host: (any DeckHost)?

    init(manifest: PluginManifest, services: SharedServices) {
        self.manifest = manifest
        self.services = services
    }

    final func activate(host: any DeckHost) {
        self.host = host
        didActivate()
    }

    final func deactivate() {
        willDeactivate()
        host = nil
    }

    func didActivate() {}
    func willDeactivate() {}

    func panelVisibilityChanged(_ isVisible: Bool) {}
    var sections: [DeckSection] { [] }
    var settingsView: AnyView? { nil }
    var menuBarItem: DeckMenuBarItem? { nil }
}

enum BuiltInPlugins {
    @MainActor
    static func all(services: SharedServices) -> [any DeckPlugin] {
        [
            SoundPlugin(services: services),
            DisplayPlugin(services: services),
            ClipboardPlugin(services: services),
            CPUPlugin(services: services),
            MemoryPlugin(services: services),
            DiskPlugin(services: services),
            NetworkPlugin(services: services),
            SensorsPlugin(services: services),
            BatteryPlugin(services: services),
            WiFiPlugin(services: services),
            BluetoothPlugin(services: services),
            InputSourcePlugin(services: services),
            MediaKeysPlugin(services: services),
            TrioIconPlugin(services: services),
            StatsPillPlugin(services: services)
        ]
    }
}
