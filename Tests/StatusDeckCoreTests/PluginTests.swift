import Foundation
import StatusDeckKit
import SwiftUI
import Testing
@testable import StatusDeckCore

@MainActor
private final class FakeHost: DeckHost {
    var isPanelVisible = false
    var isDryRun = true
    func storageDirectory(for pluginID: String) -> URL { FileManager.default.temporaryDirectory }
    func showLevel(symbol: String, value: Double, title: String?) {}
    func openPanel(showing sectionID: String?) {}
    func closePanel() {}
    func openSettings(pluginID: String?) {}
    func pluginContentDidChange() {}
    func registerHotKey(_ hotKey: DeckHotKey, handler: @escaping () -> Void) -> DeckHotKeyToken? { nil }
}

@MainActor
private final class FakePlugin: DeckPlugin {
    let manifest: PluginManifest
    var activations = 0
    var deactivations = 0

    init(id: String, enabledByDefault: Bool = true, sortOrder: Int = 500) {
        manifest = PluginManifest(id: id, name: id, summary: "", symbol: "star", category: .tools, enabledByDefault: enabledByDefault, sortOrder: sortOrder)
    }

    func activate(host: any DeckHost) { activations += 1 }
    func deactivate() { deactivations += 1 }
}

private func temporaryFolder() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("statusdeck-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func isolatedDefaults() -> UserDefaults {
    UserDefaults(suiteName: "statusdeck.tests.\(UUID().uuidString)")!
}

private func writePlugin(in directory: URL, name: String = "Sample", id: String = "com.test.sample", apiVersion: Int = DeckPluginAPI.version, library: String = "lib.dylib", createLibrary: Bool = true) -> URL {
    let folder = directory.appendingPathComponent("\(name).deckplugin")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let manifest = #"{"id":"\#(id)","name":"\#(name)","apiVersion":\#(apiVersion),"library":"\#(library)"}"#
    try? Data(manifest.utf8).write(to: folder.appendingPathComponent("plugin.json"))
    if createLibrary { try? Data("not really a library".utf8).write(to: folder.appendingPathComponent(library)) }
    return folder
}

@MainActor
@Suite struct PluginLifecycleTests {
    private let host = FakeHost()

    @Test func onlyEnabledPluginsRun() {
        let on = FakePlugin(id: "on")
        let off = FakePlugin(id: "off", enabledByDefault: false)
        let manager = PluginManager(host: host, builtIns: [on, off], pluginsDirectory: temporaryFolder(), defaults: isolatedDefaults())
        manager.start()
        #expect(on.activations == 1)
        #expect(off.activations == 0, "a plugin that is off must not run any code")
        #expect(manager.activePlugins.map(\.manifest.id) == ["on"])
    }

    @Test func switchingOffDeactivatesAndIsRemembered() {
        let plugin = FakePlugin(id: "p")
        let defaults = isolatedDefaults()
        let manager = PluginManager(host: host, builtIns: [plugin], pluginsDirectory: temporaryFolder(), defaults: defaults)
        manager.start()
        manager.setEnabled(false, id: "p")
        #expect(plugin.deactivations == 1)
        #expect(manager.activePlugins.isEmpty)

        let again = FakePlugin(id: "p")
        let next = PluginManager(host: host, builtIns: [again], pluginsDirectory: temporaryFolder(), defaults: defaults)
        next.start()
        #expect(again.activations == 0)
    }

    @Test func aPluginCanBeSwitchedBackOn() {
        let plugin = FakePlugin(id: "p")
        let manager = PluginManager(host: host, builtIns: [plugin], pluginsDirectory: temporaryFolder(), defaults: isolatedDefaults())
        manager.start()
        manager.setEnabled(false, id: "p")
        manager.setEnabled(true, id: "p")
        #expect(plugin.activations == 2)
        #expect(manager.activePlugins.count == 1)
    }

    @Test func panelOrderFollowsSortOrder() {
        let late = FakePlugin(id: "late", sortOrder: 900)
        let early = FakePlugin(id: "early", sortOrder: 100)
        let manager = PluginManager(host: host, builtIns: [late, early], pluginsDirectory: temporaryFolder(), defaults: isolatedDefaults())
        manager.start()
        #expect(manager.activePlugins.map(\.manifest.id) == ["early", "late"])
    }

    @Test func sidebarMovesPersistAcrossRestartAndDisabledPluginsKeepTheirPlace() {
        let defaults = isolatedDefaults()
        let directory = temporaryFolder()
        let plugins = [FakePlugin(id: "sound", sortOrder: 100),
                       FakePlugin(id: "memory", enabledByDefault: false, sortOrder: 300),
                       FakePlugin(id: "clipboard", sortOrder: 390)]
        let manager = PluginManager(host: host, builtIns: plugins, pluginsDirectory: directory, defaults: defaults)
        manager.start()
        manager.movePanelEntries(from: [2], to: 0)
        #expect(manager.activePlugins.map(\.manifest.id) == ["clipboard", "sound"])
        manager.movePanelEntries(from: [0], to: 3)
        manager.setEnabled(true, id: "memory")
        #expect(manager.activePlugins.map(\.manifest.id) == ["sound", "memory", "clipboard"])
        manager.movePanelEntries(from: [1], to: 0)
        manager.stop()
        let next = PluginManager(host: host, builtIns: plugins + [FakePlugin(id: "new", sortOrder: 50)], pluginsDirectory: directory, defaults: defaults)
        next.start()
        #expect(next.activePlugins.map(\.manifest.id) == ["memory", "sound", "clipboard", "new"])
    }

    @Test func pluginShelfStaysAfterMovableSectionsWithLegacyOrder() {
        let defaults = isolatedDefaults()
        let directory = temporaryFolder()
        let clipboard = FakePlugin(id: "com.statusdeck.clipboard", sortOrder: 390)
        _ = writePlugin(in: directory, id: "com.test.extension")
        defaults.set([clipboard.manifest.id, "com.test.extension", "first", "second"], forKey: "pluginManager.panelOrder")
        let manager = PluginManager(host: host, builtIns: [FakePlugin(id: "first"), FakePlugin(id: "second"), clipboard], pluginsDirectory: directory, defaults: defaults)
        manager.start()
        manager.movePanelEntries(from: [1], to: 0)
        #expect(manager.orderedEntries.map(\.id) == ["second", "first", clipboard.manifest.id, "com.test.extension"])
        #expect(manager.activePlugins.map(\.manifest.id) == ["second", "first", clipboard.manifest.id])
    }

    @Test func aPluginThatCrashedOnActivationStaysOffNextTime() {
        let defaults = isolatedDefaults()
        defaults.set("bad", forKey: "pluginManager.activating")
        let bad = FakePlugin(id: "bad")
        let good = FakePlugin(id: "good")
        let manager = PluginManager(host: host, builtIns: [bad, good], pluginsDirectory: temporaryFolder(), defaults: defaults)
        manager.start()
        #expect(bad.activations == 0)
        #expect(good.activations == 1)
        #expect(manager.notice != nil)
    }

    @Test func activationMarkerIsClearedAfterSuccess() {
        let defaults = isolatedDefaults()
        let manager = PluginManager(host: host, builtIns: [FakePlugin(id: "p")], pluginsDirectory: temporaryFolder(), defaults: defaults)
        manager.start()
        #expect(defaults.string(forKey: "pluginManager.activating") == nil)
    }
}

@MainActor
@Suite struct ExternalPluginTests {
    private let host = FakeHost()

    @Test func discoveryNeverEnablesANewPlugin() throws {
        let directory = temporaryFolder()
        _ = writePlugin(in: directory)
        let manager = PluginManager(host: host, builtIns: [], pluginsDirectory: directory, defaults: isolatedDefaults())
        manager.start()
        let entry = try #require(manager.entries.first)
        #expect(entry.isExternal)
        #expect(!entry.isEnabled)
        #expect(!entry.isActive)
        #expect(entry.problem == nil)
    }

    @Test func wrongAPIVersionIsRefusedWithoutLoading() {
        let folder = writePlugin(in: temporaryFolder(), apiVersion: DeckPluginAPI.version + 1)
        #expect(ExternalPluginLoader.read(folder).problem == .incompatibleAPI(found: DeckPluginAPI.version + 1))
    }

    @Test func missingManifestIsReported() {
        let folder = temporaryFolder().appendingPathComponent("Empty.deckplugin")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(ExternalPluginLoader.read(folder).problem == .unreadableManifest)
    }

    @Test func missingLibraryIsReported() {
        let folder = writePlugin(in: temporaryFolder(), createLibrary: false)
        #expect(ExternalPluginLoader.read(folder).problem == .missingLibrary)
    }

    @Test func libraryPathCannotEscapeThePluginFolder() throws {
        let directory = temporaryFolder()
        try Data("x".utf8).write(to: directory.appendingPathComponent("outside.dylib"))
        let folder = writePlugin(in: directory, library: "../outside.dylib", createLibrary: false)
        #expect(ExternalPluginLoader.read(folder).problem == .missingLibrary)
    }

    @Test func aFileThatIsNotALibraryFailsCleanly() {
        let folder = writePlugin(in: temporaryFolder())
        let discovered = ExternalPluginLoader.read(folder)
        guard case .failure(.cannotLoad) = ExternalPluginLoader.load(discovered) else {
            Issue.record("expected cannotLoad")
            return
        }
    }

    @Test func aFailedLoadSwitchesThePluginOffAndExplains() throws {
        let directory = temporaryFolder()
        _ = writePlugin(in: directory)
        let manager = PluginManager(host: host, builtIns: [], pluginsDirectory: directory, defaults: isolatedDefaults())
        manager.start()
        manager.setEnabled(true, id: "com.test.sample")
        let entry = try #require(manager.entries.first)
        #expect(!entry.isActive)
        #expect(!entry.isEnabled)
        #expect(entry.problem != nil)
    }

    @Test func aLibraryChangedSinceApprovalStaysOff() throws {
        let directory = temporaryFolder()
        let folder = writePlugin(in: directory)
        let defaults = isolatedDefaults()
        let library = folder.appendingPathComponent("lib.dylib")
        defaults.set(true, forKey: "plugin.enabled.com.test.sample")
        defaults.set(ExternalPluginLoader.fingerprint(of: library), forKey: "plugin.approvedFingerprint.com.test.sample")
        try Data("tampered".utf8).write(to: library)

        let manager = PluginManager(host: host, builtIns: [], pluginsDirectory: directory, defaults: defaults)
        manager.start()
        let entry = try #require(manager.entries.first)
        #expect(!entry.isEnabled)
        #expect(!entry.isActive)
        #expect(entry.problem != nil)
    }

    @Test func aPluginCannotTakeOverABuiltInID() throws {
        let directory = temporaryFolder()
        _ = writePlugin(in: directory, id: "com.statusdeck.sound")
        let builtIn = FakePlugin(id: "com.statusdeck.sound")
        let manager = PluginManager(host: host, builtIns: [builtIn], pluginsDirectory: directory, defaults: isolatedDefaults())
        manager.start()
        #expect(manager.activePlugins.first === builtIn)
        let impostor = try #require(manager.entries.first { $0.isExternal })
        #expect(impostor.problem != nil)
        #expect(!impostor.isEnabled)
    }

    @Test func manifestDefaultsApply() {
        let file = ExternalPluginFile(id: "x", name: "X", apiVersion: 1, library: "x.dylib")
        #expect(file.manifest.enabledByDefault == false, "third-party plugins always start off")
        #expect(file.manifest.category == .tools)
    }
}
