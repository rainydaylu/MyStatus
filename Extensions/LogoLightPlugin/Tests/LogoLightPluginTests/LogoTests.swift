import AppKit
import Foundation
import LogoLightCore
import StatusDeckKit
import SwiftUI
import Testing
@testable import LogoLightHost

@Suite struct LogoBehaviorTests {
    @Test func lidQueriesAreSharedAcrossAnimationFramesAndInvalidatedOnResume() {
        var cache = LogoLidCache()
        var reads = 0
        var closed = false
        for tick in 0..<100 {
            #expect(!cache.read(at: Double(tick) / 100) { reads += 1; return closed })
        }
        #expect(reads == 4)
        closed = true
        cache.invalidate()
        #expect(cache.read(at: 0.99) { reads += 1; return closed })
        #expect(reads == 5)
        cache.invalidate()
        #expect(cache.read(at: 1) { nil }, "An unreadable lid must fail closed")
    }
    @Test func legacySettingsKeepTheirValuesWhenMorseIsAdded() throws {
        var p = LogoPreferences(); p.mode = .music; p.brightness = 0.31; p.musicGain = 1.7; p.keepClosed = true
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any])
        json.removeValue(forKey: "morseText")
        let decoded = try JSONDecoder().decode(LogoPreferences.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.mode == .music && decoded.brightness == 0.31 && decoded.musicGain == 1.7)
        #expect(decoded.keepClosed)
        #expect(decoded.morseText == "SOS")
    }

    @Test func morsePreviewMatchesTheTransmittedTextAndNormalizesOneLine() {
        #expect(LogoMorse.notation("sos") == "... --- ...")
        #expect(LogoMorse.transmittedText("你好") == "NI HAO")
        #expect(LogoMorse.notation("你好") == MorseCode.notation("NI HAO"))
        #expect(LogoMorse.notation("🙂").isEmpty)
        #expect(LogoMorse.unsupported("SOS🙂") == "🙂")
        var p = LogoPreferences(); p.morseText = "HELLO\nWORLD"
        #expect(p.normalized().morseText == "HELLO WORLD")
        p.morseText = String(repeating: "A", count: 500)
        #expect(p.normalized().morseText.count == MorseCode.maxLength)
    }

    @Test func lockingAndUserSwitchingWinOverClosedLidContinuation() {
        for reason in [LogoPauseReason.locked, .sessionInactive, .systemSleep] {
            #expect(LogoLifecycle.pausesOutput(reasons: [reason], closedSessionAllowed: true))
        }
        #expect(!LogoLifecycle.pausesOutput(reasons: [.screenSleep], closedSessionAllowed: true))
        #expect(LogoLifecycle.pausesOutput(reasons: [.screenSleep], closedSessionAllowed: false))
    }
    @Test func powerOffWinsOverEverySignal() {
        var p = LogoPreferences(); p.enabled = false
        var signal = LogoSignals(); signal.charging = true; signal.pluggedIn = true
        signal.music = 1; signal.contacts = 5; signal.recentlyTyped = true; signal.agent = .attention
        for mode in LogoMode.allCases {
            p.mode = mode
            for t in stride(from: 0.0, through: 20, by: 0.1) { signal.seconds = t; #expect(signal.output(for: p) == 0) }
        }
    }

    @Test func batteryModeUsesChargeInsteadOfManualBrightness() {
        var p = LogoPreferences(); p.mode = .battery
        var signal = LogoSignals(); signal.battery = 0.43
        for manual in [0.0, 0.2, 1.0] { p.brightness = manual; #expect(signal.output(for: p) == 0.43) }
        signal.pluggedIn = true; signal.charging = false
        #expect(signal.output(for: p) == 1)
        signal.battery = 1; signal.charging = true
        #expect(signal.output(for: p) == 1)
    }

    @Test func chargingAndBreatheRespectTheSelectedFloor() {
        var p = LogoPreferences(); p.mode = .battery; p.dimFloor = 0.25
        var signal = LogoSignals(); signal.battery = 0.4; signal.pluggedIn = true; signal.charging = true
        var values: [Double] = []
        for t in stride(from: 0.0, through: 6, by: 0.05) { signal.seconds = t; values.append(signal.output(for: p)) }
        #expect(abs(values.min()! - 0.25) < 0.001)
        #expect(abs(values.max()! - 1) < 0.001)
        p.mode = .breathing; p.brightness = 0.6
        #expect(signal.output(for: p) <= 0.6)
    }

    @Test func inputModesRespondOnlyToTheirOwnSignals() {
        var p = LogoPreferences(); p.mode = .trackpad
        var s = LogoSignals(); s.recentlyTyped = true
        #expect(s.output(for: p) == 0)
        s.contacts = 1; #expect(s.output(for: p) == p.brightness)
        p.clickFlash = true; s.clicked = true; #expect(s.output(for: p) == 0)
        p.mode = .typing; s.recentlyTyped = false; #expect(s.output(for: p) == 0)
        s.recentlyTyped = true; #expect(s.output(for: p) == p.brightness)
    }

    @Test func invalidValuesStayFiniteAndBounded() {
        for mode in LogoMode.allCases {
            for x in [-10.0, 0, 1, 100, .nan, .infinity] {
                var p = LogoPreferences(); p.mode = mode; p.brightness = x; p.musicGain = x; p.cycleSeconds = x; p.dimFloor = x
                var s = LogoSignals(); s.seconds = x; s.battery = x; s.music = x; s.agent = .working
                #expect(s.output(for: p).isFinite)
                #expect((0...1).contains(s.output(for: p)))
            }
        }
        var p = LogoPreferences(); p.closedMinutes = 500
        #expect(p.normalized().closedMinutes == 30)
    }

    @Test func contactLedgerExcludesHoverAndTracksDevicesIndependently() {
        var ledger = LogoTouchLedger()
        ledger.accept(device: 1, path: 4, state: 2); #expect(ledger.count == 0)
        ledger.accept(device: 1, path: 4, state: 3)
        ledger.accept(device: 2, path: 4, state: 4); #expect(ledger.count == 2)
        ledger.accept(device: 1, path: 4, state: 5); #expect(ledger.count == 1)
        ledger.accept(device: 2, path: 4, state: 7); #expect(ledger.count == 0)
    }

    @Test func recoveryRecordSurvivesRoundTripAndRejectsSymlinks() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("logo-journal-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let note = LogoRecoveryNote(token: UUID(), owner: getpid(), originalOn: false, closedOverride: true, deadline: Date(timeIntervalSince1970: 1000))
        try note.save(to: folder)
        #expect(try LogoRecoveryNote.load(from: folder) == note)
        let record = folder.appendingPathComponent("session.json")
        let renamed = folder.appendingPathComponent("original.json")
        try FileManager.default.moveItem(at: record, to: renamed)
        try FileManager.default.createSymbolicLink(at: record, withDestinationURL: renamed)
        #expect(throws: (any Error).self) { try LogoRecoveryNote.load(from: folder) }
    }
}

@MainActor private final class FixtureHost: DeckHost {
    var isDryRun = true
    let isPanelVisible = false
    var requests = 0
    func storageDirectory(for pluginID: String) -> URL { FileManager.default.temporaryDirectory }
    func showLevel(symbol: String, value: Double, title: String?) {}
    func openPanel(showing sectionID: String?) { requests += 1 }
    func closePanel() {}
    func openSettings(pluginID: String?) { requests += 1 }
    func pluginContentDidChange() {}
    func registerHotKey(_ hotKey: DeckHotKey, handler: @escaping () -> Void) -> DeckHotKeyToken? { requests += 1; return nil }
}

@MainActor private final class FixtureDevice: LogoOutputDevice {
    var supported = true
    var hasRecovery = false
    var closed = false
    var onFailure: ((String) -> Void)?
    var started = 0; var stopped = 0
    var levels: [Double] = []
    var pauses = 0; var resumes = 0
    var closedRequests: [Bool] = []
    var morse: String?
    func begin() async throws { started += 1 }
    func output(_ level: Double, response: Double) { levels.append(level) }
    func playMorse(_ text: String?) { morse = text }
    func pause() { pauses += 1; morse = nil }
    func resume() { resumes += 1 }
    func allowClosed(_ enabled: Bool, until deadline: Date?) throws { closedRequests.append(enabled) }
    func end() { stopped += 1 }
    func recover() async throws { hasRecovery = false }
}

@MainActor private final class FixtureSound: SoundLevelSource {
    var starts = 0; var stops = 0
    var loudness = 0.6
    var shouldFail = false
    func start() throws {
        starts += 1
        if shouldFail { throw CocoaError(.featureUnsupported) }
    }
    func stop() { stops += 1 }
}

@MainActor @Suite struct LogoPluginContractTests {
    @Test func inactiveAnimationUsesTheSlowTimerAndAudioRetryRestoresResponsiveness() async {
        let domain = "logo.tests." + UUID().uuidString
        let store = UserDefaults(suiteName: domain)!
        defer { store.removePersistentDomain(forName: domain) }
        let device = FixtureDevice(), sound = FixtureSound(), host = FixtureHost()
        host.isDryRun = false
        sound.shouldFail = true
        let runtime = LogoRuntime(device: device, store: store, sound: sound, observesSystemEvents: false)
        runtime.settings.mode = .music
        runtime.start(host: host)
        for _ in 0..<100 where !runtime.active { await Task.yield() }
        #expect(runtime.pollingInterval == 1)
        sound.shouldFail = false
        runtime.retryAudio()
        #expect(runtime.pollingInterval == 0.05)
        runtime.setPaused(true, reason: .locked)
        #expect(runtime.pollingInterval == 1)
        #expect(device.pauses == 1)
        runtime.setPaused(false, reason: .locked)
        #expect(runtime.pollingInterval == 0.05)
        runtime.settings.mode = .morse
        #expect(runtime.pollingInterval == 1)
        #expect(device.morse == "SOS")
        runtime.stop()
    }
    @Test func screenSleepBeforeLidEventKeepsLoopButLockAlwaysStopsIt() async {
        let domain = "logo.tests." + UUID().uuidString
        let store = UserDefaults(suiteName: domain)!
        defer { store.removePersistentDomain(forName: domain) }
        let device = FixtureDevice(), host = FixtureHost(); host.isDryRun = false
        var safePower = true
        let runtime = LogoRuntime(device: device, store: store, observesSystemEvents: false, powerAllowsClosed: { safePower })
        runtime.settings.keepClosed = true; runtime.settings.mode = .morse
        runtime.start(host: host)
        for _ in 0..<100 where !runtime.active { await Task.yield() }
        #expect(device.morse == "SOS")
        runtime.setPaused(true, reason: .screenSleep)
        device.closed = true; runtime.pump()
        #expect(device.pauses == 0 && device.closedRequests.last == true)
        runtime.setPaused(true, reason: .locked)
        #expect(device.pauses == 1 && device.closedRequests.last == false && device.morse == nil)
        runtime.setPaused(true, reason: .sessionInactive)
        runtime.setPaused(false, reason: .locked)
        #expect(device.resumes == 0)
        runtime.setPaused(false, reason: .sessionInactive)
        #expect(device.morse == "SOS" && device.resumes == 1)
        safePower = false; runtime.pump()
        #expect(device.closedRequests.last == false && device.morse == nil)
        safePower = true; runtime.pump()
        #expect(device.morse == "SOS")
        runtime.settings.morseText = ""
        #expect(device.morse == nil && device.levels.last == 0)
        runtime.settings.morseText = "HI"
        #expect(device.morse == "HI")
        runtime.settings.enabled = false
        #expect(device.morse == nil)
        runtime.stop()
    }
    @Test func verifierHasSettingsButCreatesNoRuntimeOrStandaloneSurface() {
        let plugin = LogoPlugin(), host = FixtureHost()
        plugin.activate(host: host)
        #expect(!plugin.manifest.enabledByDefault)
        #expect(plugin.runtime == nil)
        #expect(plugin.sections.isEmpty)
        #expect(plugin.menuBarItem == nil)
        #expect(plugin.settingsView != nil)
        #expect(host.requests == 0)
        plugin.deactivate(); plugin.deactivate()
    }

    @Test func settingsAreNamespacedAndDisablingPreservesTheSavedChoice() throws {
        let domain = "logo.tests." + UUID().uuidString
        let store = UserDefaults(suiteName: domain)!
        defer { store.removePersistentDomain(forName: domain) }
        store.set(0.92, forKey: "brightness")
        let device = FixtureDevice(), runtime = LogoRuntime(device: device, store: store)
        runtime.settings.brightness = 0.37; runtime.settings.mode = .agents
        runtime.stop()
        #expect(device.started == 0)
        #expect(device.stopped == 1)
        #expect(store.double(forKey: "brightness") == 0.92)
        let next = LogoRuntime(device: FixtureDevice(), store: store)
        #expect(next.settings.brightness == 0.37)
        #expect(next.settings.mode == .agents)
        #expect(!next.settings.keepClosed)
        #expect(!next.settings.shortcuts)
        next.stop()
    }

    @Test func switchingAwayFromMusicStopsCaptureAndDisablePreventsRearming() async {
        let domain = "logo.tests." + UUID().uuidString
        let store = UserDefaults(suiteName: domain)!
        defer { store.removePersistentDomain(forName: domain) }
        let device = FixtureDevice(), sound = FixtureSound(), host = FixtureHost()
        host.isDryRun = false
        let runtime = LogoRuntime(device: device, store: store, sound: sound, observesSystemEvents: false)
        runtime.settings.mode = .music
        #expect(sound.starts == 0)
        runtime.start(host: host)
        for _ in 0..<100 where !runtime.active { await Task.yield() }
        #expect(runtime.active)
        #expect(sound.starts == 1)
        runtime.settings.musicGain = 1.8
        #expect(sound.starts == 1)
        runtime.settings.mode = .steady
        #expect(sound.stops >= 1)
        #expect(device.levels.last == runtime.settings.brightness)
        let written = device.levels.count
        runtime.stop(); runtime.stop()
        runtime.settings.mode = .music
        await Task.yield()
        #expect(!runtime.active)
        #expect(device.stopped == 1)
        #expect(device.levels.count == written)
        #expect(sound.starts == 1)
        #expect(host.requests == 0)
    }

    @Test func unsupportedHardwareNeverStartsCaptureOrNativeControl() async {
        let domain = "logo.tests." + UUID().uuidString
        let store = UserDefaults(suiteName: domain)!
        defer { store.removePersistentDomain(forName: domain) }
        let device = FixtureDevice(), sound = FixtureSound(), host = FixtureHost()
        device.supported = false; host.isDryRun = false
        let runtime = LogoRuntime(device: device, store: store, sound: sound, observesSystemEvents: false)
        runtime.settings.mode = .music
        runtime.start(host: host); runtime.connect()
        await Task.yield()
        #expect(device.started == 0)
        #expect(sound.starts == 0)
        #expect(!runtime.active)
        runtime.stop()
    }
}
