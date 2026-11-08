#!/usr/bin/env python3
"""Keep the upstream desktop panel, but let mystatus own the app lifecycle."""
from pathlib import Path
import sys

root = Path(sys.argv[1]) / 'Sources/CodeIslandPlugin/Upstream'

def edit(name, before, after):
    path = root / name
    text = path.read_text()
    if before not in text:
        raise SystemExit(f'CodeIsland adapter needs review: {name}')
    path.write_text(text.replace(before, after))

settings = (root / 'SettingsView.swift').read_text()
logo = settings.split('struct AppLogoView: View {', 1)[1].split('// MARK: - Shortcuts Page', 1)[0]
font = settings.split('enum ContentFontSize {', 1)[1].split('private struct AppearancePage:', 1)[0]
(root / 'AppLogoView.swift').write_text('import SwiftUI\n\nstruct AppLogoView: View {' + logo + '\nenum ContentFontSize {' + font)
for name in ['CodeIslandApp.swift', 'AppDelegate.swift', 'SettingsView.swift', 'SettingsWindowController.swift', 'StatusItemController.swift', 'UpdateChecker.swift', 'DiagnosticsExporter.swift']:
    (root / name).unlink()
edit('NotchPanelView.swift', 'NSApp.delegate as? AppDelegate', 'CodeIslandRuntime.current')
edit('NotchPanelView.swift', 'SettingsWindowController.shared.show()', 'CodeIslandRuntime.current?.openSettings()')
edit('QuitConfirmation.swift', 'NSApplication.shared.terminate(nil)', '_ = Task { @MainActor in CodeIslandRuntime.current?.hideIsland() }')
edit('PanelWindowController.swift', '    deinit {\n        autoScreenPoller', '''    func closeHostedPanel() {
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel?.close()
        panel = nil
    }

    deinit {
        autoScreenPoller''')
edit('BundleExtension.swift', 'let bundleName = "CodeIsland_CodeIsland"', 'let bundleName = "CodeIslandPlugin_CodeIslandPlugin"')
edit('BundleExtension.swift', 'if let resourceURL = Bundle.main.resourceURL,', 'if let resourceURL = CodeIslandPluginResources.folder,')
edit('BundleExtension.swift', 'return Bundle.module', '''let adjacent = Bundle.main.bundleURL.appendingPathComponent("\\(bundleName).bundle")
        return Bundle(url: adjacent) ?? .main''')
edit('SessionPersistence.swift', 'return home + "/.codeisland"', 'return home + "/Library/Application Support/StatusDeck/CodeIsland"')
# The standalone process exits after stop. The plugin can be re-enabled in
# the same process, so it must close held requests and unlink only its socket.
path = root / 'HookServer.swift'
text = path.read_text()
start = text.index('    func stop() {')
end = text.index('    /// Internal tools', start)
text = text[:start] + '''    func stop() {
        for context in connectionContexts.values { context.connection?.respond(Data()) }
        connectionContexts.removeAll()
        listener?.stop()
        listener?.removeSocketFile()
        listener = nil
    }

''' + text[end:]
text = text.replace('        var responded: Bool = false', '        var responded: Bool = false\n        weak var connection: HookConnection?')
text = text.replace('        connectionContexts[connId] = context', '        context.connection = connection\n        connectionContexts[connId] = context')
path.write_text(text)

# The hosted island follows the application's language picker.
path = root / 'L10n.swift'
text = path.read_text().replace('import Combine\n', 'import Combine\nimport StatusDeckKit\n')
start = text.index('    @Published var language:')
end = text.index('    // MARK: - Translations', start)
text = text[:start] + '''    @Published private var language = DeckLanguage.current.resolved()
    private var defaultsObserver: AnyCancellable?

    init() {
        defaultsObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                let next = DeckLanguage.current.resolved()
                guard let self, self.language != next else { return }
                self.language = next
            }
    }

    var effectiveLanguage: String {
        language == .chinese ? "zh" : language.rawValue
    }

    subscript(_ key: String) -> String {
        if language == .french, let translation = hostedFrench[key] { return translation }
        return Self.strings[effectiveLanguage]?[key] ?? Self.strings["en"]?[key] ?? key
    }

''' + text[end:]
path.write_text(text)
