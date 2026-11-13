import Carbon
import AppKit
import Foundation
import Testing
import StatusDeckKit
@testable import StatusDeckCore

@Suite struct HardwareCompatibilityTests {
    @Test func oneSecondSamplesDoNotCreateFalseZeroGapsInTransferCurves() {
        var history = TransferHistory()
        for index in 0...60 { history.append(228_000, 7_100_000, at: Double(index)) }
        let bins = history.bins(seconds: 60, count: 60)
        #expect(bins.first.allSatisfy { $0 == 228_000 })
        #expect(bins.second.allSatisfy { $0 == 7_100_000 })
        let measured = history.measuredBins(seconds: 60, count: 72)
        #expect(measured.first.contains(nil))
        #expect(measured.first.compactMap { $0 }.allSatisfy { $0 == 228_000 })
        #expect(!measured.first.contains(0))
        history.append(0, 0, at: 61)
        #expect(history.measuredBins(seconds: 60, count: 72).first.last == 0)
    }

    @Test func frequencyDomainsFollowClusterMetadataInsteadOfFixedMSeriesKeys() {
        let data = Data([22, 0, 0, 0, 0, 0, 0, 0, 23, 1, 0, 0, 0, 0, 0, 0, 5, 2, 0, 0, 0, 0, 0, 0])
        let keys = DVFSTables.cpuTableKeys(accClusters: data, clusterKinds: [0: .performance, 1: .performance, 2: .superCore])
        #expect(keys[.performance] == "voltage-states22-sram")
        #expect(keys[.superCore] == "voltage-states5-sram")
        #expect(keys[.efficiency] == nil)
        #expect(DVFSTables.cpuTableKeys(accClusters: Data([1, 2]), clusterKinds: [:]).isEmpty)
    }

    @Test func m5ProDistinguishesSuperAndPerformanceUsingTheActualClusterLetters() {
        let clusters = Dictionary(uniqueKeysWithValues: (0..<18).map { ($0, $0 < 12 ? "M" : "P") })
        let result = CPUCoreTopology.resolve(count: 18, clusters: clusters, levels: [
            CPUPerformanceLevel(name: "Super", count: 6), CPUPerformanceLevel(name: "Performance", count: 12)
        ])
        #expect(result.values.filter { $0 == .superCore }.count == 6)
        #expect(result.values.filter { $0 == .performance }.count == 12)
        #expect(result[0] == .performance)
        #expect(result[12] == .superCore)
    }

    @Test func olderChipsKeepEfficiencyAndPerformanceCores() {
        let result = CPUCoreTopology.resolve(count: 8, clusters: [0: "E", 7: "P"], levels: [
            CPUPerformanceLevel(name: "Performance", count: 4), CPUPerformanceLevel(name: "Efficiency", count: 4)
        ])
        #expect((0..<4).allSatisfy { result[$0] == .efficiency })
        #expect((4..<8).allSatisfy { result[$0] == .performance })
    }

    @Test func threeKindsAndMissingRegistryEntriesUseNamedPerformanceLevels() {
        let result = CPUCoreTopology.resolve(count: 10, clusters: [:], levels: [
            CPUPerformanceLevel(name: "Super", count: 2), CPUPerformanceLevel(name: "Performance", count: 4),
            CPUPerformanceLevel(name: "Efficiency", count: 4)
        ])
        #expect(result[0] == .efficiency)
        #expect(result[4] == .performance)
        #expect(result[8] == .superCore)
        #expect(result.count == 10)
    }

    @Test func unrecognizedClustersAreNotCalledPerformanceCores() {
        let result = CPUCoreTopology.resolve(count: 2, clusters: [0: "X"], levels: [])
        #expect(result[0] == .unknown)
        #expect(result[1] == nil)
    }

    @Test func superCoreLoadDoesNotDilutePerformanceLoad() {
        let stats = CPUStats(cores: [
            CoreLoad(id: 0, kind: .performance, user: 0.1, system: 0.1),
            CoreLoad(id: 1, kind: .superCore, user: 0.7, system: 0.2)
        ])
        #expect(stats.coreKinds == [.performance, .superCore])
        #expect(abs(stats.average(of: .performance) - 0.2) < 0.00001)
        #expect(abs(stats.average(of: .superCore) - 0.9) < 0.00001)
    }

    @MainActor @Test func clipboardUpgradeKeepsCustomShortcutsAndAddsTheRequestedDefault() {
        #expect(ClipboardPlugin.effectiveHotKey(nil).modifiers == UInt32(cmdKey | shiftKey))
        #expect(ClipboardPlugin.effectiveHotKey(ClipboardPlugin.legacyHotKey) == ClipboardPlugin.defaultHotKey)
        let custom = DeckHotKey(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(controlKey | shiftKey), label: "custom")
        #expect(ClipboardPlugin.effectiveHotKey(custom) == custom)
        #expect(HotKeyCenter.carbonModifiers([.command, .shift, .capsLock, .numericPad]) == UInt32(cmdKey | shiftKey))
    }

    @Test func asymmetricTransferRatesGetIndependentReadableScales() {
        let upload = TransferRateScale(values: [100_000, 228_000], floor: 64_000)
        let download = TransferRateScale(values: [6_000_000, 7_100_000], floor: 64_000)
        #expect(upload.maximum == 500_000)
        #expect(download.maximum == 10_000_000)
        #expect(228_000 / upload.maximum > 0.4)
        #expect(TransferRateScale(values: [0, .nan, .infinity], floor: 64_000).maximum == 100_000)
        #expect(TransferRateScale(values: [], floor: 0).maximum > 0)
    }
}
