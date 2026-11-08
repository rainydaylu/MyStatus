import AppKit
import Carbon
import Foundation
import StatusDeckKit
@testable import StatusDeckCore
import Testing

@Suite("Function key regression")
@MainActor
struct FunctionKeyTests {
    @Test func aPairedHardwareDeliveryDoesNotEatTheNextBrightnessPress() {
        var delivery = BrightnessKeyDelivery()
        delivery.record(.brightnessUp, source: .hardware, time: 1_000_000_000)
        let firstIsDuplicate = delivery.consumeDuplicate(.brightnessUp, source: .quartz, time: 1_002_000_000)
        let nextIsDuplicate = delivery.consumeDuplicate(.brightnessUp, source: .quartz, time: 1_030_000_000)
        #expect(firstIsDuplicate)
        #expect(!nextIsDuplicate)
        delivery.record(.brightnessUp, source: .quartz, time: 1_030_000_000)
        let sameSourceIsDuplicate = delivery.consumeDuplicate(.brightnessUp, source: .quartz, time: 1_031_000_000)
        let lateHardwareIsDuplicate = delivery.consumeDuplicate(.brightnessUp, source: .hardware, time: 1_029_000_000)
        #expect(!sameSourceIsDuplicate)
        #expect(lateHardwareIsDuplicate)
    }

    @Test func standardFKeysDecodeAsBrightness() throws {
        let down = try #require(CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_F1), keyDown: true))
        down.flags = []
        let press = try #require(MediaKeyController.decode(down))
        #expect(press.key == .brightnessDown)
        #expect(press.isKeyDown)
        let up = try #require(CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_F2), keyDown: false))
        up.flags = []
        #expect(MediaKeyController.decode(up)?.key == .brightnessUp)
        #expect(MediaKeyController.decode(up)?.isKeyDown == false)
    }

    @Test func commandAndControlShortcutsPassThrough() {
        #expect(MediaKeyController.standardBrightnessKey(keyCode: Int64(kVK_F1), flags: .maskCommand) == nil)
        #expect(MediaKeyController.standardBrightnessKey(keyCode: Int64(kVK_F2), flags: .maskControl) == nil)
        #expect(MediaKeyController.standardBrightnessKey(keyCode: Int64(kVK_F3), flags: []) == nil)
    }

    @Test func heldFnLeavesBrightnessCombinationsToTheSystem() {
        #expect(MediaKeyController.Key.brightnessDown.preservesFnCombination(true))
        #expect(MediaKeyController.Key.brightnessUp.preservesFnCombination(true))
        #expect(!MediaKeyController.Key.brightnessDown.preservesFnCombination(false))
        #expect(!MediaKeyController.Key.brightnessUp.preservesFnCombination(false))
        #expect(!MediaKeyController.Key.soundUp.preservesFnCombination(true))
    }

    @Test func appleBrightnessMediaEventsDecodeDownUpAndRepeat() throws {
        // Real NX_SYSDEFINED data1 layout: high word = media key, low = state/repeat.
        let f1 = try #require(MediaKeyController.decodeSystemData((3 << 16) | 0x0A00))
        #expect(f1.key == .brightnessDown && f1.isKeyDown && !f1.isRepeat)
        let f2 = try #require(MediaKeyController.decodeSystemData((2 << 16) | 0x0A01, modifiers: [.option, .shift]))
        #expect(f2.key == .brightnessUp && f2.isKeyDown && f2.isRepeat && f2.isFineStep)
        let up = try #require(MediaKeyController.decodeSystemData((2 << 16) | 0x0B00))
        #expect(!up.isKeyDown)
    }

    @Test func hardwareFallbackOnlyMatchesDisplayBrightnessUsages() {
        #expect(BrightnessHIDMonitor.key(page: 0x0C, usage: 0x6F) == .brightnessUp)
        #expect(BrightnessHIDMonitor.key(page: 0x0C, usage: 0x70) == .brightnessDown)
        #expect(BrightnessHIDMonitor.key(page: 0xFF01, usage: 0x20) == .brightnessUp)
        #expect(BrightnessHIDMonitor.key(page: 0x00FF, usage: 0x05) == .brightnessDown)
        #expect(BrightnessHIDMonitor.key(page: 0x0C, usage: 0x79) == nil)
        #expect(BrightnessHIDMonitor.key(page: 7, usage: 0x3A) == nil)
        #expect(BrightnessHIDMonitor.key(page: 7, usage: 0x3A, allowFunctionKeys: true) == .brightnessDown)
        #expect(BrightnessHIDMonitor.key(page: 7, usage: 0x3B, allowFunctionKeys: true) == .brightnessUp)
        #expect(BrightnessHIDMonitor.key(page: 7, usage: 0x3C, allowFunctionKeys: true) == nil)
    }

    @Test func unrelatedSystemEventsCannotBecomeBrightnessReleases() {
        #expect(MediaKeyController.decodeSystemData((2 << 16) | 0x0800) == nil)
        #expect(MediaKeyController.decodeSystemData((20 << 16) | 0x0A00) == nil)
    }
}

final class OfflineGitHub: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}

@Suite("Plugin update preservation")
struct PluginUpdateTests {
    @MainActor
    @Test func downloadedPathsCannotEscapeStaging() {
        #expect(!PluginUpdateService.safePath("../Package.swift"))
        #expect(!PluginUpdateService.safePath("Sources/../../Package.swift"))
        #expect(!PluginUpdateService.safePath("/tmp/Library.swift"))
        #expect(!PluginUpdateService.safePath("..\\Library.swift"))
        #expect(PluginUpdateService.safePath("Sources/MosPlugin/Interpolator.swift"))
        #expect(!PluginUpdateService.validSHA("main; rm -rf ~"))
        #expect(PluginUpdateService.validSHA(String(repeating: "a", count: 40)))
    }

    @MainActor
    @Test func failedDownloadPreservesInstalledPlugin() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let template = root.appendingPathComponent("Templates/MosPlugin")
        let installed = root.appendingPathComponent("Installed/MosPlugin.deckplugin")
        let kit = root.appendingPathComponent("Kit")
        for directory in [template, installed, kit] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        let source = UpstreamDescriptor(repository: "Caldis/Mos", commit: String(repeating: "a", count: 40), adapter: "mos", files: ["Mos/Interpolator.swift": "Sources/Interpolator.swift"])
        let encoder = JSONEncoder()
        try encoder.encode(source).write(to: template.appendingPathComponent("upstream.json"))
        try encoder.encode(source).write(to: installed.appendingPathComponent("upstream.json"))
        let manifest = ExternalPluginFile(id: "com.statusdeck.mos", name: "Mos", apiVersion: DeckPluginAPI.version, library: "libMosPlugin.dylib")
        try encoder.encode(manifest).write(to: template.appendingPathComponent("plugin.json"))
        let bytes = Data("working installed plugin".utf8)
        try bytes.write(to: installed.appendingPathComponent("libMosPlugin.dylib"))
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [OfflineGitHub.self]
        let service = PluginUpdateService(pluginDirectory: installed.deletingLastPathComponent(), templates: template.deletingLastPathComponent(), kit: kit, session: URLSession(configuration: config))
        await service.install("MosPlugin")
        #expect(try Data(contentsOf: installed.appendingPathComponent("libMosPlugin.dylib")) == bytes)
        #expect(service.rows.first?.error != nil)
        #expect(!service.rows[0].isBusy)
    }
}


@Suite("Software volume startup failure")
struct SoftwareVolumeFailureTests {
    private struct StartupFailure: Error {}
    @Test func failedStartReleasesBuffersExactlyOnce() {
        if #available(macOS 14.2, *) {
            for _ in 0..<32 {
                #expect(throws: StartupFailure.self) {
                    _ = try SoftwareVolumeEngine(outputUID: "test-only", initialGain: 1, startOverride: { throw StartupFailure() })
                }
            }
        }
    }
}
