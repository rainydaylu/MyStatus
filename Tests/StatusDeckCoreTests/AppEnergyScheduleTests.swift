import Foundation
import Testing
@testable import StatusDeckCore

@Suite struct AppEnergyScheduleTests {
    @Test func backgroundMeasuresOneMinuteEveryFiveMinutes() throws {
        var schedule = AppEnergySchedule()
        schedule.configure(enabled: true, foreground: false, at: 0)
        #expect(schedule.next == .init(kind: .baseline, deadline: 0))
        schedule.completed(try #require(schedule.next), at: 0, measured: false)
        #expect(schedule.next == .init(kind: .finish, deadline: 60))
        schedule.completed(try #require(schedule.next), at: 60, measured: true)
        #expect(schedule.next == .init(kind: .baseline, deadline: 300))
        schedule.completed(try #require(schedule.next), at: 300, measured: false)
        #expect(schedule.next == .init(kind: .finish, deadline: 360))
        schedule.completed(try #require(schedule.next), at: 360, measured: true)
        #expect(schedule.next == .init(kind: .baseline, deadline: 600))
    }

    @Test func foregroundUsesMinuteDeltasAndReopeningKeepsTheBaseline() throws {
        var schedule = AppEnergySchedule()
        schedule.configure(enabled: true, foreground: false, at: 0)
        schedule.completed(try #require(schedule.next), at: 0, measured: false)
        schedule.configure(enabled: true, foreground: true, at: 20)
        #expect(schedule.next?.deadline == 60)
        schedule.configure(enabled: true, foreground: false, at: 25)
        schedule.configure(enabled: true, foreground: true, at: 30)
        #expect(schedule.next?.deadline == 60)
        schedule.completed(try #require(schedule.next), at: 60, measured: true)
        #expect(schedule.next == .init(kind: .finish, deadline: 120))
        schedule.completed(try #require(schedule.next), at: 120, measured: true)
        #expect(schedule.next == .init(kind: .finish, deadline: 180))
    }

    @Test func foregroundInterruptsBackgroundIdleWithoutInventingAPastMinute() throws {
        var schedule = AppEnergySchedule()
        schedule.configure(enabled: true, foreground: false, at: 0)
        schedule.completed(try #require(schedule.next), at: 0, measured: false)
        schedule.completed(try #require(schedule.next), at: 60, measured: true)
        schedule.configure(enabled: true, foreground: true, at: 150)
        #expect(schedule.next == .init(kind: .baseline, deadline: 150))
        schedule.completed(try #require(schedule.next), at: 150, measured: false)
        #expect(schedule.next == .init(kind: .finish, deadline: 210))
    }

    @Test func disableStopsReadRequestsAndWakeStartsANewWindow() throws {
        var schedule = AppEnergySchedule()
        schedule.configure(enabled: true, foreground: true, at: 0)
        schedule.completed(try #require(schedule.next), at: 0, measured: false)
        schedule.restart(at: 1_000)
        #expect(schedule.next == .init(kind: .baseline, deadline: 1_000))
        schedule.configure(enabled: false, foreground: false, at: 1_010)
        #expect(schedule.next == nil)
        schedule.restart(at: 2_000)
        #expect(schedule.next == nil)
    }

    @Test func unavailableOrInterruptedReadRetriesWithAFreshMinute() throws {
        var schedule = AppEnergySchedule()
        schedule.configure(enabled: true, foreground: false, at: 0)
        schedule.completed(try #require(schedule.next), at: 0, measured: false)
        schedule.completed(try #require(schedule.next), at: 160, measured: false)
        #expect(schedule.next == .init(kind: .finish, deadline: 220))
    }

    @Test func headerTotalIncludesAppsBeyondTheTopFiveButExcludesSharedSystemEnergy() {
        var window = AppEnergyWindow()
        let baseline = (0..<7).map { id in
            AppEnergyCounter(coalitionID: UInt64(id), bundlePath: id < 6 ? "/App\(id).app" : "",
                             name: "App\(id)", cpu: 0, gpu: 0, ane: 0)
        }
        let ending = baseline.map { item in
            AppEnergyCounter(coalitionID: item.coalitionID, bundlePath: item.bundlePath, name: item.name,
                             cpu: 60_000_000_000, gpu: 0, ane: 0)
        }
        _ = window.record(baseline, at: 0, available: true)
        let stats = window.record(ending, at: 60, available: true)
        #expect(stats.entries.count == 5)
        #expect(stats.appWatts == 6)
        #expect(stats.chipWatts == 7)
        #expect(stats.entries.map(\.watts).reduce(0, +) == 5)
    }

    @Test func cacheRestoresLastMinuteAndRejectsExpiredOrMalformedResults() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = AppEnergyResultCache(file: dir.appendingPathComponent("energy.json"))
        let now = Date(timeIntervalSince1970: 10_000)
        let stats = AppEnergyStats(state: .ready,
                                   entries: [.init(id: "a", name: "App", bundlePath: "/App.app", watts: 1)],
                                   seconds: 60, chipWatts: 2, appWatts: 1, sampledAt: now)
        cache.save(stats)
        #expect(cache.load(now: now.addingTimeInterval(120)) == stats)
        #expect(cache.load(now: now.addingTimeInterval(86_401)) == nil)
        let permissions = try FileManager.default.attributesOfItem(atPath: cache.file.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        try Data("invalid".utf8).write(to: cache.file)
        #expect(cache.load(now: now) == nil)
    }
}
