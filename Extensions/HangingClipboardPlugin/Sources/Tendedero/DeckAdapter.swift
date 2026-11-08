import AppKit
import StatusDeckKit
import SwiftUI

@MainActor
final class HangingClipboardPlugin: DeckPlugin {
    let manifest = PluginManifest(id: "com.statusdeck.hanging-clipboard", name: "悬浮剪贴板", summary: "插件 2 · 截图与图片晾衣绳", symbol: "photo.on.rectangle.angled", category: .tools, enabledByDefault: false, sortOrder: 395)
    private var controller: AppDelegate?

    func activate(host: any DeckHost) {
        guard !host.isDryRun else { return }
        HangingPreferences.migrate()
        let controller = AppDelegate()
        self.controller = controller
        controller.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
    }

    func deactivate() { controller?.stopPlugin(); controller = nil }

    var sections: [DeckSection] {
        [DeckSection(id: "hanging-clipboard", title: "悬浮剪贴板") {
            HStack {
                DeckTitle(DeckL("悬浮剪贴板", "Hanging clipboard"))
                Spacer()
                Button(DeckL("显示晾衣绳", "Show line")) { [weak self] in self?.controller?.toggle() }
                    .buttonStyle(.borderless)
            }
        }]
    }

    var settingsView: AnyView? {
        AnyView(HangingSettings(controller: controller))
    }
}

private struct HangingSettings: View {
    let controller: AppDelegate?
    @State private var copied = ClipboardWatcher.isEnabled
    @State private var hover = AppDelegate.opensFromMenuBar
    @State private var peek = AppDelegate.peeksAtNew
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(DeckL("挂起复制的图片", "Hang copied images"), isOn: Binding(get: { copied }, set: { copied = $0; controller?.setClipboard($0) }))
            Toggle(DeckL("鼠标停在菜单栏时展开", "Reveal at the menu bar"), isOn: Binding(get: { hover }, set: { hover = $0; AppDelegate.opensFromMenuBar = $0 }))
            Toggle(DeckL("新截图短暂展开", "Reveal new screenshots briefly"), isOn: Binding(get: { peek }, set: { peek = $0; AppDelegate.peeksAtNew = $0 }))
            HStack {
                Button(DeckL("显示 / 隐藏", "Show / hide")) { controller?.toggle() }
                Text("⌃⌥T").foregroundStyle(.secondary)
            }
            Text(DeckL("保留原项目的点击复制、长按标注、双击预览与拖拽。此功能直接运行在 mystatus 内。", "Click to copy, hold to annotate, double-click to preview, and drag to share. Runs inside mystatus."))
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

@_cdecl("statusdeck_plugin_create")
public func statusdeckPluginCreate() -> UnsafeMutableRawPointer {
    DeckPluginExport.retained { HangingClipboardPlugin() }
}


enum HangingPreferences {
    static let store = UserDefaults(suiteName: "local.statusdeck.hanging-clipboard")!
    static func migrate() {
        guard !store.bool(forKey: "migration.complete") else { return }
        for domain in ["app.tendedero.Tendedero", "app.tendedero"] {
            if let previous = UserDefaults.standard.persistentDomain(forName: domain) {
                for (key, value) in previous where store.object(forKey: key) == nil { store.set(value, forKey: key) }
            }
        }
        if store.object(forKey: "clipboardEnabled") == nil { store.set(true, forKey: "clipboardEnabled") }
        store.set(true, forKey: "migration.complete")
    }
}
