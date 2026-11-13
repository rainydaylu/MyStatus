import ApplicationServices
import Foundation
import StatusDeckKit
import Testing
@testable import MosPlugin

@MainActor
struct ScrollTests {
    private func testDefaults() -> UserDefaults {
        UserDefaults(suiteName: "mystatus.mos.tests.\(UUID())")!
    }

    private func wheel() throws -> CGEvent {
        try #require(CGEvent(scrollWheelEvent2Source: nil, units: .line,
                             wheelCount: 2, wheel1: 1, wheel2: 0, wheel3: 0))
    }

    @Test func freshInstallReversesWithoutSmoothingAndPreservesExplicitChoices() throws {
        let store = testDefaults()
        let preferences = MosPreferences(store: store)
        #expect(!preferences.options.smooth)
        #expect(preferences.options.reverseY)
        #expect(preferences.options.minimumStep == 23)
        #expect(preferences.options.speed == 1.45)
        #expect(preferences.options.duration == 0.50)
        let engine = MosEngine(preferences: preferences)
        defer { engine.stop() }
        let event = try wheel()
        _ = engine.receive(.scrollWheel, event, canPost: { true })
        #expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == -1)
        #expect(event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0)
        preferences.options.smooth = true
        preferences.options.reverse = false
        let restored = MosPreferences(store: store)
        #expect(restored.options.smooth)
        #expect(!restored.options.reverse)
    }

    @Test func fractionalGainUsesMosPointDeltaAndLegacyDurationCurve() throws {
        let preferences = MosPreferences(store: testDefaults())
        // Exercise fractional gain independently of the user's new presets.
        preferences.options.minimumStep = 2
        preferences.options.speed = 0.25
        preferences.options.duration = 0.1
        preferences.options.smooth = true
        preferences.options.reverse = false
        #expect(preferences.options.minimumStep == 2)
        #expect(preferences.options.speed == 0.25)
        #expect(preferences.options.duration == 0.1)
        #expect(preferences.options.frameTransition == 0.861)
        let engine = MosEngine(preferences: preferences)
        defer { engine.stop() }
        let event = try wheel()
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: 10)
        let passed = engine.receive(.scrollWheel, event, canPost: { true })?.takeUnretainedValue()
        #expect(passed === event)
        #expect(event.getIntegerValueField(.scrollWheelEventIsContinuous) == 1)
        #expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 0)
        #expect(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == 2)
    }

    @Test func smallDeltasAccumulateWithoutInflatingGain() throws {
        let preferences = MosPreferences(store: testDefaults())
        preferences.options.minimumStep = 2
        preferences.options.speed = 0.25
        preferences.options.smooth = true
        preferences.options.reverse = false
        preferences.options.duration = 0
        let engine = MosEngine(preferences: preferences)
        defer { engine.stop() }

        for pointInput in [false, true] {
            engine.stop()
            var output: [Int64] = []
            for _ in 0..<4 {
                let event = try wheel()
                event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0)
                event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: pointInput ? 1 : 0)
                _ = engine.receive(.scrollWheel, event, canPost: { true })
                output.append(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
            }
            #expect(output == (pointInput ? [0, 1, 0, 1] : [0, 0, 0, 1]))
        }
    }

    @Test func updatesPriorPresetsAndPreservesCustomProfiles() throws {
        let store = testDefaults()
        let defaults = PluginDefaults(pluginID: "com.statusdeck.mos", store: store)
        let old = MosScrollOptions(reverse: true, minimumStep: 12, speed: 1, duration: 0.32)
        defaults.set(try JSONEncoder().encode(old), forKey: "scrollOptions")
        let migrated = MosPreferences(store: store)
        #expect(migrated.options == MosScrollOptions(reverse: true))
        let prior = MosScrollOptions(smooth: true, reverse: false, minimumStep: 2, speed: 0.25, duration: 0.1)
        defaults.set(try JSONEncoder().encode(prior), forKey: "scrollOptions")
        #expect(MosPreferences(store: store).options == MosScrollOptions(smooth: true, reverse: false))

        let custom = MosScrollOptions(reverse: true, minimumStep: 12, speed: 0.5, duration: 0.32)
        defaults.set(try JSONEncoder().encode(custom), forKey: "scrollOptions")
        #expect(MosPreferences(store: store).options == custom)
    }

    @Test func deniedPostingLeavesWheelUsableAndDirectionCanStillChange() throws {
        let preferences = MosPreferences(store: testDefaults())
        preferences.options.horizontalKey = .option
        preferences.options.reverse = true
        preferences.options.reverseVertical = false
        preferences.options.reverseHorizontal = true
        let engine = MosEngine(preferences: preferences)
        let event = try wheel()
        event.flags = .maskAlternate
        let passed = engine.receive(.scrollWheel, event, canPost: { false })?.takeUnretainedValue()
        #expect(passed === event)
        #expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 0)
        #expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis2) == -1)
    }

    @Test func oldExceptionsAndDirectionMigrateAndRulesSurviveRestart() {
        let store = testDefaults()
        let defaults = PluginDefaults(pluginID: "com.statusdeck.mos", store: store)
        defaults.set(true, forKey: "reverseHorizontal")
        defaults.set("com.example.excluded", forKey: "excludedApps")
        let preferences = MosPreferences(store: store)
        #expect(preferences.options.reverseX && !preferences.options.reverseY)
        #expect(preferences.settings(for: "com.example.excluded")?.smooth == false)
        preferences.allowlist = true
        preferences.rules[0].options.smooth = true
        let restored = MosPreferences(store: store)
        #expect(restored.settings(for: "com.example.other") == nil)
        #expect(restored.settings(for: "com.example.excluded")?.smooth == true)
    }
}
