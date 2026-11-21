import Foundation
import Testing
@testable import StatusDeckCore

@Suite struct BatteryLearningTests {
    private func pack(percent: Double, external: Bool = false) -> BatteryStats {
        var b = BatteryStats()
        b.isPresent = true
        b.isExternalPowerConnected = external
        b.percent = Int(percent)
        b.currentChargeCapacity = Int((percent * 100).rounded())
        b.rawFullChargeCapacity = 10_000
        b.fullChargeCapacity = 10_000
        b.nominalVolts = 10
        b.volts = 10
        b.amps = -2 // 20 W / 100 Wh = baseline 20%/h
        return b
    }

    private func discharge(start: Date, factor: Double = 1.1, external: Bool = false) -> [BatteryObservation] {
        (0...60).map { i in
            // 30 minutes, observed 11 points vs baseline 10.
            let percent = 90 - Double(i) / 60 * 10 * factor
            return BatteryObservation(battery: pack(percent: percent, external: external), at: start.addingTimeInterval(Double(i) * 30))
        }
    }

    @Test func oneCoefficientMatchesObservedDischargeWithoutChangingAppShares() throws {
        let points = discharge(start: Date(timeIntervalSince1970: 1_000))
        let result = try #require(BatteryProportionFit.fit(points))
        #expect(abs(result.factor - 1.1) < 0.001)
        #expect(abs(result.actual - 11) < 0.001)
        #expect(abs(result.predicted - 10) < 0.001)
        var battery = pack(percent: 90)
        battery.energyCalibrationFactor = result.factor
        #expect(abs((AppEnergyEntry.percentPerHour(watts: 5, battery: battery) ?? 0) - 5.5) < 0.001)
    }

    @Test func chargingSparseOrInsufficientObservationsDoNotAdjustTheModel() {
        let start = Date(timeIntervalSince1970: 1_000)
        #expect(BatteryProportionFit.fit(discharge(start: start, external: true)) == nil)
        #expect(BatteryProportionFit.fit(Array(discharge(start: start).prefix(5))) == nil)
        let all = discharge(start: start)
        #expect(BatteryProportionFit.fit([all[0], all[60]]) == nil) // sleep/long gap
        #expect(BatteryProportionFit.fit(discharge(start: start, factor: 3)) == nil)
    }

    @Test func csvPreservesActualGaugeCapacityAndPower() throws {
        let point = BatteryObservation(battery: pack(percent: 83.25), at: Date(timeIntervalSince1970: 123))
        let restored = try #require(BatteryObservation(csv: Substring(point.csv.trimmingCharacters(in: .newlines))))
        #expect(restored.measuredPercent == 83.25)
        #expect(restored.currentMAH == 8_325)
        #expect(restored.watts == -20)
        #expect(restored.baselinePercentPerHour == 20)
        #expect(!restored.external)
    }

    @Test func fittingHappensOncePerDayAndNoDataPreservesLastFactor() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01
        let store = BatteryLearningStore(folder: dir, calendar: calendar)
        for i in 0...60 {
            store.observe(pack(percent: 90 - Double(i) / 60 * 11), at: day.addingTimeInterval(Double(i) * 30))
        }
        store.flush()
        #expect(store.model.factor == 1) // today's partial data is not used
        store.observe(pack(percent: 79, external: true), at: day.addingTimeInterval(86_400))
        #expect(abs(store.model.factor - 1.1) < 0.001)
        let fittedAt = store.model.fittedAt
        store.observe(pack(percent: 79, external: true), at: day.addingTimeInterval(86_460))
        #expect(store.model.fittedAt == fittedAt)
        store.observe(pack(percent: 79, external: true), at: day.addingTimeInterval(9 * 86_400))
        #expect(abs(store.model.factor - 1.1) < 0.001)
        let again = BatteryLearningStore(folder: dir, calendar: calendar)
        #expect(again.model.factor == store.model.factor)
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        #expect(files.contains { $0.lastPathComponent == "battery-2024-01-01.csv" })
    }
}
