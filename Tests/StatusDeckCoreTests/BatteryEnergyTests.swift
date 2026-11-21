import Foundation
import Testing
@testable import StatusDeckCore

@Suite struct BatteryEnergyTests {
    private func counter(_ cpu: UInt64, id: UInt64 = 1, path: String = "/Applications/App.app", gpu: UInt64 = 0, ane: UInt64 = 0) -> AppEnergyCounter {
        AppEnergyCounter(coalitionID: id, bundlePath: path, name: "App", cpu: cpu, gpu: gpu, ane: ane)
    }

    @Test func differentiatesNanojoulesAndConvertsWattsToBatteryPercentPerHour() throws {
        var window = AppEnergyWindow()
        #expect(window.record([counter(1_000_000_000)], at: 10, available: true).state == .warmingUp)
        let stats = window.record([counter(7_000_000_000, gpu: 2_000_000_000, ane: 2_000_000_000)], at: 12, available: true)
        let entry = try #require(stats.entries.first)
        #expect(entry.watts == 5)
        var battery = BatteryStats()
        battery.fullChargeCapacity = 10_000
        battery.nominalVolts = 10
        battery.volts = 12
        #expect(battery.estimatedFullChargeWattHours == 100)
        #expect(entry.percentPerHour(battery: battery) == 5)
        #expect(entry.percentPerHour(battery: BatteryStats()) == nil)
    }

    @Test func helperCoalitionsMergeButDuplicateReadingsNeverDoubleCount() throws {
        var window = AppEnergyWindow()
        _ = window.record([counter(1), counter(1, id: 2)], at: 0, available: true)
        let stats = window.record([counter(2_000_000_001), counter(2_000_000_001), counter(4_000_000_001, id: 2)], at: 2, available: true)
        #expect(stats.entries.count == 1)
        #expect(try #require(stats.entries.first).watts == 3)
    }

    @Test func clippingTheWindowUsesElapsedTimeRatherThanNumberOfSamples() throws {
        var window = AppEnergyWindow()
        _ = window.record([counter(0)], at: 0, available: true)
        _ = window.record([counter(80_000_000_000)], at: 40, available: true) // 2 W
        let stats = window.record([counter(120_000_000_000)], at: 80, available: true) // 1 W
        #expect(stats.seconds == 60)
        #expect(abs((try #require(stats.entries.first).watts) - 4.0 / 3) < 0.00001)
    }

    @Test func counterResetsAndSleepGapsNeverProduceEnergySpikes() {
        var window = AppEnergyWindow()
        _ = window.record([counter(9_000_000_000)], at: 0, available: true)
        #expect(window.record([counter(1)], at: 3, available: true).entries.isEmpty)
        #expect(window.record([counter(100_000_000_000)], at: 200, available: true).state == .warmingUp)
        #expect(window.record([], at: 203, available: false).state == .unavailable)
        window.reset()
        #expect(window.record([counter(300)], at: 204, available: true).state == .warmingUp)
    }

    @Test func sharedSystemEnergyStaysInChipTotalWithoutBecomingAnApp() throws {
        var window = AppEnergyWindow()
        _ = window.record([counter(1), counter(1, id: 2, path: "")], at: 0, available: true)
        let stats = window.record([counter(2_000_000_001), counter(4_000_000_001, id: 2, path: "")], at: 2, available: true)
        #expect(stats.chipWatts == 3)
        #expect(stats.entries.count == 1)
        #expect(try #require(stats.entries.first).watts == 1)
    }

    @Test func powerFlowUsesActualInputAndLeavesMissingDomainsUnknown() {
        var snapshot = SystemSnapshot()
        snapshot.battery.isExternalPowerConnected = true
        snapshot.battery.adapterWatts = 140
        snapshot.battery.adapterInputWatts = 85
        snapshot.battery.systemLoadWatts = 23.8
        snapshot.battery.volts = 12
        snapshot.battery.amps = 5.1
        snapshot.appEnergy.chipWatts = 10.7
        snapshot.sensors.displayWatts = 3.83
        let flow = BatteryPowerFlow(snapshot: snapshot)
        #expect(flow.input == 85)
        #expect(abs((flow.battery ?? 0) - 61.2) < 0.00001)
        #expect(abs((flow.other ?? 0) - 9.27) < 0.00001)
        snapshot.sensors.displayWatts = nil
        #expect(BatteryPowerFlow(snapshot: snapshot).other == nil)
        snapshot.battery.isExternalPowerConnected = false
        snapshot.battery.amps = -2
        #expect(BatteryPowerFlow(snapshot: snapshot).input == 24)
        #expect(BatteryPowerFlow(snapshot: SystemSnapshot()).input == nil)
    }

    @Test func telemetryPowerIsMilliwattsAndInvalidValuesAreNotShownAsZero() {
        let stats = BatteryReader.parse(registry: ["PowerTelemetryData": ["SystemPowerIn": 85_000, "SystemLoad": 23_800]], into: BatteryStats(), adapter: nil)
        #expect(stats.adapterInputWatts == 85)
        #expect(stats.systemLoadWatts == 23.8)
        let unavailable = BatteryReader.parse(registry: ["PowerTelemetryData": ["SystemLoad": -1]], into: BatteryStats(), adapter: nil)
        #expect(unavailable.systemLoadWatts == nil)
    }

    @Test func timeBadgeSwitchesBetweenRuntimeAndChargeTimeAndHidesWhenFull() {
        var b = BatteryStats()
        b.isPresent = true; b.percent = 60; b.minutesRemaining = 125
        #expect(BatteryTimeEstimate(b)?.minutes == 125)
        #expect(BatteryTimeEstimate(b)?.charging == false)
        b.isExternalPowerConnected = true
        #expect(BatteryTimeEstimate(b) == nil) // charging paused: no false runtime
        b.isCharging = true; b.minutesRemaining = 40
        #expect(BatteryTimeEstimate(b)?.charging == true)
        b.isFullyCharged = true
        #expect(BatteryTimeEstimate(b) == nil)
        b.isFullyCharged = false; b.percent = 100
        #expect(BatteryTimeEstimate(b) == nil)
        b.percent = 60; b.minutesRemaining = nil
        #expect(BatteryTimeEstimate(b) == nil)
    }

    @Test func chargingUsesTimeToFullAndDischargingUsesTimeToEmpty() {
        let source: [String: Any] = ["Time to Full Charge": 44, "Time to Empty": 180]
        let charging = BatteryReader.parse(registry: ["IsCharging": true, "TimeRemaining": 99],
                                           into: BatteryStats(), adapter: nil, powerSource: source)
        #expect(charging.minutesRemaining == 44)
        let discharging = BatteryReader.parse(registry: ["IsCharging": false, "TimeRemaining": 99],
                                              into: BatteryStats(), adapter: nil, powerSource: source)
        #expect(discharging.minutesRemaining == 180)
    }
}
