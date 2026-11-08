import Foundation
import Testing
@testable import StatusDeckCore

@Suite struct TransferAndFanTests {
    @Test func parsesNettopByColumnNameAndSkipsAggregateRows() throws {
        let rows = try #require(TransferSource.parseNettop("""
            time,,bytes_out,bytes_in,
            12:03:01.400001,"Editor, Helper.231",123,789,
            12:03:01.400001,,123,789,
            """))
        #expect(rows == [TransferCounter(pid: 231, identity: "Editor, Helper", first: 123, second: 789)])
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
