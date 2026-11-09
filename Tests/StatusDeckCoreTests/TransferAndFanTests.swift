import Foundation
import Testing
@testable import StatusDeckCore

@Suite struct TransferAndFanTests {
    @Test func parsesNettopDeltaByColumnNameAndSkipsAggregateRows() throws {
        let rows = try #require(TransferSource.parseNettopRates("""
            ,bytes_in,bytes_out,
            Editor.2000231,99000,11000,
            time,,bytes_out,bytes_in,
            12:03:01.400001,"Editor, Helper.2000231",123,789,
            12:03:01.400001,,123,789,
            """))
        #expect(rows == [ProcessTransfer(id: 2_000_231, name: "Editor, Helper", first: 123, second: 789, bundlePath: nil)])
        #expect(TransferSource.parseNettopRates(",bytes_in,bytes_out,\nEditor.2000231,99000,11000,") == nil)
        #expect(TransferSource.parseNettopRates(",bytes_in,bytes_out,\n,bytes_in,bytes_out,") == [])
    }

    @Test func idleRatesKeepActualProcessesAfterBaseline() {
        let idle = TransferCounter(pid: 2_000_231, identity: "Editor", first: 12, second: 14)
        var reader = TransferRateReader()
        #expect(reader.read([idle], at: 10, includeIdle: true).isEmpty)
        let rows = reader.read([idle], at: 12, includeIdle: true)
        #expect(rows == [ProcessTransfer(id: idle.pid, name: "Editor", first: 0, second: 0, bundlePath: nil)])
    }

    @Test func processRatesRejectReusedPidsAndCounterResets() {
        var reader = TransferRateReader()
        #expect(reader.read([
            TransferCounter(pid: 1234, identity: "old", first: 4_000, second: 3_000),
            TransferCounter(pid: 1235, identity: "stable", first: 4_000, second: 3_000)
        ], at: 0).isEmpty)
        let rows = reader.read([
            TransferCounter(pid: 1234, identity: "new", first: 5_000, second: 9_000),
            TransferCounter(pid: 1235, identity: "stable", first: 2, second: 7_000)
        ], at: 2)
        #expect(rows.map(\.id) == [1235])
        #expect(rows.first?.first == 0)
        #expect(rows.first?.second == 2_000)
    }

    @Test func timeRangesOnlyUseSamplesWithinTheSelectedWindow() {
        var history = TransferHistory()
        history.append(700, 1, at: 100)
        history.append(50, 900, at: 240)
        history.append(60, 70, at: 280)
        #expect(history.bins(seconds: 60, count: 6).first.max() == 60)
        #expect(history.bins(seconds: 60, count: 6).second.max() == 900)
        #expect(history.bins(seconds: 300, count: 6).first.max() == 700)
    }

    @Test func hoverShowsOneActualSampleAndKeepsEmptyBucketsEmpty() {
        var history = TransferHistory()
        let date = Date(timeIntervalSince1970: 1_000)
        history.append(20, 150, at: 55, date: date)
        history.append(200, 30, at: 57, date: date.addingTimeInterval(2))
        history.append(0, 0, at: 60, date: date.addingTimeInterval(5))

        let sample = history.sample(at: 0.92, seconds: 60, count: 6)
        #expect(sample?.date == date)
        #expect(sample?.first == 20)
        #expect(sample?.second == 150)
        #expect(history.sample(at: 0.5, seconds: 60, count: 6) == nil)
        #expect(history.sample(at: 1, seconds: 60, count: 6)?.at == 60)
    }

    @Test func chartTooltipStaysBesideTheSameCoordinateUsedToSelectSamples() {
        let left = ChartHoverPosition(pointer: 40, width: 300, preferredTooltipWidth: 158)
        #expect(left.tooltipX == left.cursor + 6)
        #expect(left.fraction == 40.0 / 300)

        let right = ChartHoverPosition(pointer: 260, width: 300, preferredTooltipWidth: 158)
        #expect(right.tooltipX + right.tooltipWidth == right.cursor - 6)
        #expect(right.fraction == 260.0 / 300)

        let middle = ChartHoverPosition(pointer: 150, width: 300, preferredTooltipWidth: 158)
        #expect(middle.tooltipX == 156)
        #expect(middle.tooltipX + middle.tooltipWidth == 300)
    }

    @Test func chartKeepsOneSnapshotUntilThePointerLeaves() {
        var hover = ChartHoverSession<[Int]>()
        hover.move(to: CGPoint(x: 20, y: 10), showing: [1, 2])
        hover.move(to: CGPoint(x: 200, y: 10), showing: [3, 4])
        #expect(hover.pointer?.x == 200)
        #expect(hover.snapshot == [1, 2])
        hover.end()
        #expect(hover.snapshot == nil)
        hover.move(to: CGPoint(x: 20, y: 10), showing: [3, 4])
        #expect(hover.snapshot == [3, 4])
    }

    @Test func bothHistoriesCoverFiveHoursAtOneSamplePerSecond() {
        let seconds = HistoryRange.fiveHours.rawValue
        var monitor = MonitorHistory<Int>()
        var transfer = TransferHistory()
        let date = Date(timeIntervalSince1970: 0)
        for time in 0...(seconds + 1_000) {
            monitor.append(time, at: Double(time), date: date)
            transfer.append(Double(time), 0, at: Double(time), date: date)
        }
        let bars = monitor.bins(seconds: seconds, count: 72)
        #expect(bars[0]?.value == 1_249)
        #expect(bars[71]?.value == seconds + 1_000)
        #expect(transfer.sample(at: 0, seconds: seconds, count: 72)?.first == 1_000)
        #expect(transfer.sample(at: 1, seconds: seconds, count: 72)?.first == Double(seconds + 1_000))
    }

    @Test func networkRowsKeepTheirPositionsAndSurviveAShortSamplingGap() {
        func row(_ id: Int32, speed: Double) -> ProcessTransfer {
            ProcessTransfer(id: id, name: "Process \(id)", first: speed, second: 0, bundlePath: nil)
        }
        var snapshot = NetworkProcessSnapshot()
        #expect(snapshot.update([row(1, speed: 200), row(2, speed: 100), row(3, speed: 50)], at: 0)
            == .rows([row(1, speed: 200), row(2, speed: 100), row(3, speed: 50)]))
        let next = [row(4, speed: 60), row(2, speed: 90), row(3, speed: 250)]
        #expect(snapshot.update([next[2], next[1], next[0]], at: 2) == .rows(next))
        #expect(snapshot.update(nil, at: 4) == .rows(next))
        #expect(snapshot.update([], at: 6) == .rows(next))
        #expect(snapshot.update(nil, at: 10) == .unavailable)
        #expect(snapshot.recentRows(at: 10) == nil)
    }

    @Test func fanTargetsStayWithinReportedLimits() {
        let fan = FanTarget(id: 0, name: "Fan", currentSpeed: 1_500, minSpeed: 1_250, maxSpeed: 5_000, targetSpeed: 0, mode: 0)
        #expect(fan.clamp(10) == 1_250)
        #expect(fan.clamp(7_000) == 5_000)
        let unknown = FanTarget(id: 0, name: "Fan", currentSpeed: 0, minSpeed: 0, maxSpeed: 0, targetSpeed: 0, mode: 3)
        #expect(unknown.clamp(4_000) == nil)
    }

    @Test func stoppedFanIsDistinguishedFromAnUnavailableTachometer() throws {
        let data = Data("""
            [{"id":0,"name":"Fan 1","currentSpeed":0,"minSpeed":1250,"maxSpeed":5500,"targetSpeed":0,"mode":3},
             {"id":1,"name":"Fan 2","currentSpeed":null,"minSpeed":1250,"maxSpeed":5500,"targetSpeed":0,"mode":3}]
            """.utf8)
        let fans = try JSONDecoder().decode([FanTarget].self, from: data)
        #expect(fans[0].currentSpeed == 0)
        #expect(fans[0].bounds == 1250...5500)
        #expect(fans[1].currentSpeed == nil)
    }

    @Test func smallerScreensKeepWholeRowsAndDoNotAffectMenuBarOnlyPlugins() {
        let ids = ["wifi", "bluetooth", "display", "cpu", "disk", "trioicon"].map { "com.statusdeck." + $0 }
        let hidden = PanelTileLayout.initialHiddenModules(ids, screenHeight: 400)
        #expect(hidden == ["com.statusdeck.cpu"])
        #expect(PanelTileLayout.initialHiddenModules(ids, screenHeight: 1_000).isEmpty)
    }
}
