import Foundation
import Testing
@testable import StatusDeckCore

@Suite struct HistoryChartTests {
    @Test func minuteChargeSamplesFillNormalChartSlotsWithoutInventingMeasurements() {
        var history = MonitorHistory<Int>()
        let date = Date(timeIntervalSince1970: 1_000)
        // Slightly more than a minute also covers normal timer scheduling jitter.
        for index in 0...60 {
            let time = Double(index) * 61
            history.append(100 - index / 10, at: time, date: date.addingTimeInterval(time))
        }
        #expect(history.bins(seconds: 3_600, count: 72).contains { $0 == nil })
        let bars = history.bins(seconds: 3_600, count: 72, holdingFor: 90)
        #expect(bars.count == 72)
        #expect(bars.allSatisfy { $0 != nil })
        #expect(bars.compactMap { $0 }.allSatisfy { sample in
            sample.time.truncatingRemainder(dividingBy: 61) == 0 && sample.date == date.addingTimeInterval(sample.time)
        })
    }

    @Test func chargeHistoryDoesNotFillSleepOrPreLaunchIntervals() {
        var history = MonitorHistory<Int>()
        let date = Date(timeIntervalSince1970: 1_000)
        history.append(90, at: 0, date: date)
        history.append(80, at: 3_600, date: date.addingTimeInterval(3_600))
        let bars = history.bins(seconds: 3_600, count: 72, holdingFor: 90)
        #expect(bars[0]?.value == 90)
        #expect(bars[1..<71].allSatisfy { $0 == nil })
        #expect(bars[71]?.value == 80)

        var newlyStarted = MonitorHistory<Int>()
        newlyStarted.append(80, at: 3_600, date: date.addingTimeInterval(3_600))
        let startup = newlyStarted.bins(seconds: 3_600, count: 72, holdingFor: 90)
        #expect(startup.dropLast().allSatisfy { $0 == nil })
    }

    @Test func aRecentChargeReadingCanCarryIntoTheSelectedRange() {
        var history = MonitorHistory<Int>()
        let date = Date(timeIntervalSince1970: 1_000)
        history.append(85, at: 40, date: date)
        let bars = history.bins(seconds: 60, count: 6, endingAt: 110, holdingFor: 90)
        #expect(bars.allSatisfy { $0?.value == 85 && $0?.date == date })
        #expect(history.bins(seconds: 60, count: 6, endingAt: 210, holdingFor: 90).allSatisfy { $0 == nil })
    }

    @Test func transferBarsKeepBothScalesAndCannotConnectAcrossMissingSlots() throws {
        let size = CGSize(width: 300, height: 120)
        let upload = try #require(TransferBarLayout.rect(index: 0, count: 60, value: 1_000, maximum: 2_000, upward: true, size: size))
        let download = try #require(TransferBarLayout.rect(index: 0, count: 60, value: 1_000_000, maximum: 2_000_000, upward: false, size: size))
        #expect(upload.maxY == size.height / 2)
        #expect(download.minY == size.height / 2)
        #expect(upload.height == download.height)
        let later = try #require(TransferBarLayout.rect(index: 2, count: 60, value: 1_000, maximum: 2_000, upward: true, size: size))
        #expect(later.minX > upload.maxX)
        #expect(TransferBarLayout.rect(index: 1, count: 60, value: nil, maximum: 2_000, upward: true, size: size) == nil)
        #expect(TransferBarLayout.rect(index: 1, count: 60, value: 0, maximum: 2_000, upward: true, size: size) == nil)
    }
}
