import CPrivateAPI
import Darwin
import Foundation

struct AppEnergyEntry: Identifiable, Equatable, Sendable, Codable {
    let id: String
    let name: String
    let bundlePath: String
    let watts: Double

    func percentPerHour(battery: BatteryStats) -> Double? {
        Self.percentPerHour(watts: watts, battery: battery)
    }

    static func percentPerHour(watts: Double?, battery: BatteryStats) -> Double? {
        guard let watts, watts.isFinite, watts >= 0, let capacity = battery.estimatedFullChargeWattHours else { return nil }
        let factor = battery.energyCalibrationFactor
        let validFactor = factor.isFinite && (0.5...1.5).contains(factor) ? factor : 1
        return watts / capacity * 100 * validFactor
    }
}

struct AppEnergyStats: Equatable, Sendable, Codable {
    enum State: String, Equatable, Sendable, Codable { case warmingUp, ready, unavailable }
    var state: State = .warmingUp
    var entries: [AppEnergyEntry] = []
    var seconds: Double = 0
    var chipWatts: Double?
    /// All attributable apps, including those below the displayed top five.
    var appWatts: Double?
    var sampledAt: Date?
}

/// One reading per resource coalition, never one copy of the same energy for
/// every helper PID. CPU, GPU and ANE counters are separate nanojoule domains.
struct AppEnergyCounter: Equatable {
    let coalitionID: UInt64
    let bundlePath: String
    let name: String
    let cpu: UInt64
    let gpu: UInt64
    let ane: UInt64

    func joules(since previous: Self) -> Double? {
        guard bundlePath == previous.bundlePath,
              cpu >= previous.cpu, gpu >= previous.gpu, ane >= previous.ane else { return nil }
        return (Double(cpu - previous.cpu) + Double(gpu - previous.gpu) + Double(ane - previous.ane)) / 1e9
    }
}

/// Differentiate cumulative counters, then time-weight the last minute.
/// New coalitions start a baseline; resets and sleep gaps cannot become spikes.
struct AppEnergyWindow {
    struct Interval {
        let start: Double
        let end: Double
        let energy: [String: (name: String, joules: Double)]
    }
    private var previous: [UInt64: AppEnergyCounter] = [:]
    private var previousTime: Double?
    private var intervals: [Interval] = []
    static let duration: Double = 60

    mutating func reset() { self = Self() }

    mutating func record(_ counters: [AppEnergyCounter], at now: Double, available: Bool) -> AppEnergyStats {
        guard now.isFinite else { reset(); return AppEnergyStats() }
        // Defensive deduplication also protects against a process table changing
        // while its coalition membership is being enumerated.
        let current = Dictionary(counters.map { ($0.coalitionID, $0) }, uniquingKeysWith: { first, _ in first })
        defer { previous = current; previousTime = now }
        guard available else {
            intervals = []
            return AppEnergyStats(state: .unavailable)
        }
        guard let last = previousTime, now > last, now - last <= 90 else {
            intervals = []
            return AppEnergyStats()
        }
        var energy: [String: (name: String, joules: Double)] = [:]
        for (id, counter) in current {
            guard let old = previous[id], let joules = counter.joules(since: old), joules.isFinite,
                  joules >= 0, joules / (now - last) <= 1_000 else { continue }
            var app = energy[counter.bundlePath] ?? (counter.name, 0)
            app.joules += joules
            energy[counter.bundlePath] = app
        }
        intervals.append(Interval(start: last, end: now, energy: energy))
        let cutoff = now - Self.duration
        intervals.removeAll { $0.end <= cutoff }
        let seconds = now - max(cutoff, intervals.first?.start ?? now)
        guard seconds > 0 else { return AppEnergyStats() }
        var totals: [String: (name: String, joules: Double)] = [:]
        for interval in intervals {
            let fraction = (interval.end - max(cutoff, interval.start)) / (interval.end - interval.start)
            for (path, item) in interval.energy {
                var total = totals[path] ?? (item.name, 0)
                total.joules += item.joules * fraction
                totals[path] = total
            }
        }
        let entries = totals.compactMap { path, item -> AppEnergyEntry? in
            let watts = item.joules / seconds
            guard !path.isEmpty, watts.isFinite, watts > 0 else { return nil }
            return AppEnergyEntry(id: path, name: item.name, bundlePath: path, watts: watts)
        }.sorted { $0.watts == $1.watts ? $0.name < $1.name : $0.watts > $1.watts }
        let chipWatts = totals.values.reduce(0) { $0 + $1.joules } / seconds
        let appTotals = totals.filter { !$0.key.isEmpty }
        let appWatts = appTotals.isEmpty ? nil : appTotals.values.reduce(0) { $0 + $1.joules } / seconds
        return AppEnergyStats(state: .ready, entries: Array(entries.prefix(5)), seconds: seconds,
                              chipWatts: chipWatts > 0 ? chipWatts : nil, appWatts: appWatts)
    }
}

/// Read-only coalition accounting adapted from EClinick/juice (MIT). Unlike
/// powerlog/powermetrics this route needs neither root nor Full Disk Access.
/// Only the energy monitor's serial queue calls this reader, at scheduled endpoints.
final class AppEnergyReader {
    private var window = AppEnergyWindow()
    private var paths: [Int32: (coalition: UInt64, bundle: String?)] = [:]

    func reset() { window.reset(); paths.removeAll(keepingCapacity: true) }

    func read() -> AppEnergyStats {
        let pids = Self.allPIDs()
        var groups: [UInt64: Int32] = [:]
        for pid in pids where pid > 0 {
            var membership = SDProcCoalition()
            guard sd_proc_coalition(pid, &membership) == 0, membership.coalitionID > 0 else { continue }
            if let representative = groups[membership.coalitionID], representative < pid { continue }
            groups[membership.coalitionID] = pid
        }
        let alive = Set(pids)
        paths = paths.filter { alive.contains($0.key) }
        var counters: [AppEnergyCounter] = []
        var available = false
        for (coalition, pid) in groups {
            var usage = SDCoalitionUsage()
            guard sd_coalition_resource_usage(coalition, &usage) == 0 else { continue }
            available = available || usage.cpuEnergyNJ > 0 || usage.gpuEnergyNJ > 0 || usage.aneEnergyNJ > 0
            let bundle: String?
            if let cached = paths[pid], cached.coalition == coalition {
                bundle = cached.bundle
            } else {
                var bytes = [CChar](repeating: 0, count: 4_096)
                bundle = proc_pidpath(pid, &bytes, UInt32(bytes.count)) > 0
                    ? ProcessReader.outermostBundle(of: String(cString: bytes)) : nil
                paths[pid] = (coalition, bundle)
            }
            counters.append(AppEnergyCounter(coalitionID: coalition, bundlePath: bundle ?? "",
                                            name: bundle.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? "",
                                            cpu: usage.cpuEnergyNJ, gpu: usage.gpuEnergyNJ, ane: usage.aneEnergyNJ))
        }
        var result = window.record(counters, at: ProcessInfo.processInfo.systemUptime, available: available)
        if result.state == .ready { result.sampledAt = Date() }
        return result
    }

    private static func allPIDs() -> [Int32] {
        // proc_listallpids returns a count, not a byte length.
        let needed = proc_listallpids(nil, 0)
        guard needed > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(needed) + 128)
        let written = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.stride))
        guard written > 0 else { return [] }
        return Array(pids.prefix(min(Int(written), pids.count)))
    }
}
