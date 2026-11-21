import Foundation
import Testing
@testable import StatusDeckCore

@Suite struct AppCalibrationTests {
    private func rows(correlated: Bool = false, correction: Bool = true) -> [AppCalibrationFit.Row] {
        (0..<100).map { i in
            let a = 1 + Double(i % 5)
            let b = correlated ? a * 2 : 0.2 + Double((i * 7) % 11) * 0.3
            let y = 2 + a * (correction ? 1.25 : 1) + b * (correction ? 0.75 : 1)
            return .init(time: Double(i * 300), actualRate: y,
                         apps: ["/A.app": .init(name: "A", rate: a), "/B.app": .init(name: "B", rate: b)])
        }
    }

    @Test func independentAppFactorsRecoverWithoutChargingSharedBaselineToApps() throws {
        let result = try #require(AppCalibrationFit.fit(rows(), at: .now))
        #expect(abs((result.coefficients["/A.app"]?.factor ?? 0) - 1.25) < 0.06)
        #expect(abs((result.coefficients["/B.app"]?.factor ?? 0) - 0.75) < 0.06)
        #expect(abs(result.backgroundRate - 2) < 0.2)
        #expect(result.trainingCount == 80)
        #expect(result.validationCount == 20)
        #expect(result.fittedRMSE < result.baselineRMSE * 0.2)
        #expect(AppCalibrationFit.fit(rows(), previous: result, at: .now) == nil)
    }

    @Test func tooFewOrCollinearOrAlreadyAccurateSamplesDoNotInventCoefficients() {
        #expect(AppCalibrationFit.fit(Array(rows().prefix(20)), at: .now) == nil)
        #expect(AppCalibrationFit.fit(rows(correlated: true), at: .now) == nil)
        #expect(AppCalibrationFit.fit(rows(correction: false), at: .now) == nil)
    }

    private func battery(_ percent: Double, external: Bool = false) -> BatteryStats {
        var b = BatteryStats()
        b.isPresent = true; b.isExternalPowerConnected = external
        b.percent = Int(percent); b.currentChargeCapacity = Int(percent * 100)
        b.rawFullChargeCapacity = 10_000; b.fullChargeCapacity = 10_000; b.nominalVolts = 10
        b.volts = 10; b.amps = -2
        return b
    }

    @Test func minuteWindowsAlignToGaugeSamplesAndExcludeACAndSleep() {
        let points = [0, 60, 120].map { second in
            BatteryObservation(battery: battery(90 - Double(second) / 60), at: Date(timeIntervalSince1970: Double(second)))
        }
        let sample = AppCalibrationSample(start: 30, end: 90, apps: ["a": .init(name: "A", rate: 2)])
        let valid = AppCalibrationFit.rows(samples: [sample], battery: points)
        #expect(valid.count == 1)
        #expect(valid.first?.actualRate == 60)
        let ac = BatteryObservation(battery: battery(89, external: true), at: Date(timeIntervalSince1970: 60))
        #expect(AppCalibrationFit.rows(samples: [sample], battery: [points[0], ac, points[2]]).isEmpty)
        let late = BatteryObservation(battery: battery(80), at: Date(timeIntervalSince1970: 600))
        #expect(AppCalibrationFit.rows(samples: [sample], battery: [points[0], late]).isEmpty)
    }

    @Test func correctedTotalIncludesAppsBeyondFiveAndDoesNotApplyGlobalFactorTwice() throws {
        let entries = (0..<6).map { AppEnergyEntry(id: "\($0)", name: "App", bundlePath: "/\($0).app", watts: 1) }
        let stats = AppEnergyStats(state: .ready, entries: Array(entries.prefix(5)), seconds: 60,
                                   appWatts: 6, allEntries: entries)
        var b = battery(90)
        b.energyCalibrationMethod = .perApp; b.energyCalibrationFactor = 1.4
        b.appEnergyCalibration = ["/5.app": 1.5]
        #expect(stats.percentPerHour(battery: b) == 6.5)
        #expect(entries[5].percentPerHour(battery: b) == 1.5)
        b.energyCalibrationEnabled = false
        #expect(stats.percentPerHour(battery: b) == 6)
        b.energyCalibrationEnabled = true; b.energyCalibrationMethod = .global
        #expect(abs((stats.percentPerHour(battery: b) ?? 0) - 8.4) < 0.0001)
    }

    @Test func logsOnlyFreshMeasuredWindowsAndPreservesPause() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = BatteryLearningStore(folder: dir, enabled: true)
        let start = Date(timeIntervalSince1970: 100_000)
        let entry = AppEnergyEntry(id: "a", name: "A", bundlePath: "/A.app", watts: 2)
        store.observe(battery(90), at: start)
        store.observe(battery(89.6), at: start.addingTimeInterval(60))
        var energy = AppEnergyStats(state: .ready, entries: [entry], seconds: 60, appWatts: 2,
                                    sampledAt: start.addingTimeInterval(60), allEntries: [entry])
        store.recordAppEnergy(energy, battery: battery(89.6), at: start.addingTimeInterval(60))
        store.recordAppEnergy(energy, battery: battery(89.6), at: start.addingTimeInterval(120)) // old cache
        #expect(store.status(at: start.addingTimeInterval(60)).appWindowCount == 1)
        store.setEnabled(false)
        energy.sampledAt = start.addingTimeInterval(120)
        store.recordAppEnergy(energy, battery: battery(89), at: start.addingTimeInterval(120))
        store.flush()
        let file = try #require(FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first { $0.pathExtension == "jsonl" })
        #expect(try String(contentsOf: file, encoding: .utf8).split(separator: "\n").count == 1)
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int == 0o600)
    }

    @Test func dailyFitUsesPriorDayAlignedWindowsAndPersistsIndependentFactors() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = Date(timeIntervalSince1970: 1_704_067_200)
        let store = BatteryLearningStore(folder: dir, calendar: calendar, enabled: true)
        var percent = 95.0
        for row in rows() {
            let start = day.addingTimeInterval(row.time), end = start.addingTimeInterval(60)
            store.observe(battery(percent), at: start)
            store.observe(battery(percent - row.actualRate / 60), at: end)
            let entries = row.apps.map { path, value in
                AppEnergyEntry(id: path, name: value.name, bundlePath: path, watts: value.rate)
            }
            store.recordAppEnergy(.init(state: .ready, entries: entries, seconds: 60,
                                        sampledAt: end, allEntries: entries), battery: battery(percent), at: end)
            percent -= row.actualRate / 12
        }
        #expect(store.model.perApp == nil)
        #expect(store.status(at: day).appWindowCount == 100)
        let tomorrow = day.addingTimeInterval(86_400)
        store.observe(battery(percent, external: true), at: tomorrow)
        let fitted = try #require(store.model.perApp)
        #expect(abs((fitted.coefficients["/A.app"]?.factor ?? 0) - 1.25) < 0.07)
        let loaded = BatteryLearningStore(folder: dir, calendar: calendar, enabled: true)
        #expect(loaded.model.perApp == fitted)
        store.observe(battery(percent, external: true), at: tomorrow.addingTimeInterval(60))
        #expect(store.model.perApp?.fittedAt == fitted.fittedAt)
    }
}
