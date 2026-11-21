import Foundation
import Testing
@testable import StatusDeckCore

@Suite struct FanWriteConfirmationTests {
    private func fan(mode: Int = 1, target: Int = 3_000, actual: Int = 1_350) -> FanTarget {
        FanTarget(id: 0, name: "Fan 1", currentSpeed: actual, minSpeed: 1_350,
                  maxSpeed: 6_250, targetSpeed: target, mode: mode)
    }

    @Test func delayedTargetReadbackIsConfirmedInsteadOfImmediatelyReverted() {
        var reads = 0, time = 0.0
        let result = FanWriteConfirmation.wait(fanID: 0, speed: 3_000, read: {
            reads += 1
            return [fan(target: reads < 4 ? 1_350 : 3_000)]
        }, pause: { time += 0.15 }, now: { time })
        #expect(result.confirmed)
        #expect(reads == 4)
        #expect(result.fans?.first?.targetSpeed == 3_000)
        #expect(time < 1)
    }

    @Test func mechanicalRampDoesNotHaveToFinishBeforeTheAcceptedTargetIsShown() {
        let result = FanWriteConfirmation.wait(fanID: 0, speed: 3_000,
                                               read: { [fan(actual: 1_350)] }, pause: {})
        #expect(result.confirmed)
        #expect(result.fans?.first?.currentSpeed == 1_350)
    }

    @Test func genuinelyRejectedTargetStopsAtTheBoundAndCanBeRolledBack() {
        var reads = 0, time = 0.0
        let result = FanWriteConfirmation.wait(fanID: 0, speed: 3_000, read: {
            reads += 1
            return [fan(mode: 0, target: 1_350)]
        }, pause: { time += 0.15 }, now: { time })
        #expect(!result.confirmed)
        #expect(reads == 16)
        #expect(time <= 2.5)
        let restored = FanWriteConfirmation.wait(fanID: 0, speed: nil,
                                                 read: { [fan(mode: 0, target: 3_000)] }, pause: {})
        #expect(restored.confirmed) // stale target is irrelevant in automatic mode
    }

    @Test func transientMissingReadsAreRetriedAndUnknownModeIsNotAutomatic() {
        var reads = 0
        let result = FanWriteConfirmation.wait(fanID: 0, speed: 3_000, read: {
            reads += 1
            return reads < 3 ? nil : [fan()]
        }, pause: {})
        #expect(result.confirmed)
        #expect(reads == 3)
        let unknown = FanWriteConfirmation.wait(fanID: 0, speed: nil,
                                                read: { [fan(mode: -1)] }, pause: {})
        #expect(!unknown.confirmed)
    }
}
