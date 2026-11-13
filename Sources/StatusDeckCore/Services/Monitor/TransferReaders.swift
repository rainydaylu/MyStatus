import Darwin
import Foundation
import Combine

/// Each bar is the peak within its time bin.
struct TransferHistory: Equatable {
    struct Sample: Equatable {
        let at: TimeInterval
        let date: Date
        let first: Double
        let second: Double
    }

    private var samples: [Sample] = []

    mutating func append(_ first: Double, _ second: Double, at time: TimeInterval, date: Date = Date()) {
        samples.append(Sample(at: time, date: date, first: first, second: second))
        HistoryRange.prune(&samples, at: time, timestamp: \.at)
    }

    func bins(seconds: Int, count: Int) -> (first: [Double], second: [Double]) {
        let samples = measuredBins(seconds: seconds, count: count)
        return (samples.first.map { $0 ?? 0 }, samples.second.map { $0 ?? 0 })
    }

    /// Missing slots are not zero-rate measurements. Curves join recorded points.
    func measuredBins(seconds: Int, count: Int) -> (first: [Double?], second: [Double?]) {
        guard count > 0 else { return ([], []) }
        var first = [Double?](repeating: nil, count: count)
        var second = first
        guard let start = start(seconds: seconds), count > 0 else { return (first, second) }
        let binWidth = Double(seconds) / Double(count)
        for sample in samples.reversed().prefix(while: { $0.at >= start }) {
            let index = min(count - 1, Int((sample.at - start) / binWidth))
            first[index] = max(first[index] ?? 0, sample.first)
            second[index] = max(second[index] ?? 0, sample.second)
        }
        return (first, second)
    }

    /// Return a real paired measurement from the hovered bar, never two peaks
    /// that may have happened at different instants within the same bar.
    func sample(at fraction: Double, seconds: Int, count: Int) -> Sample? {
        guard let start = start(seconds: seconds), count > 0, (0...1).contains(fraction) else { return nil }
        let binWidth = Double(seconds) / Double(count)
        let target = start + fraction * Double(seconds)
        let index = min(count - 1, Int(fraction * Double(count)))
        let lowerBound = start + Double(index) * binWidth
        let upperBound = lowerBound + binWidth
        let first = firstIndex(atOrAfter: lowerBound)
        let last = index == count - 1 ? samples.endIndex : firstIndex(atOrAfter: upperBound)
        return samples[first..<last].reversed()
            .min(by: { abs($0.at - target) < abs($1.at - target) })
    }

    private func firstIndex(atOrAfter time: TimeInterval) -> Int {
        var lower = samples.startIndex
        var upper = samples.endIndex
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if samples[middle].at < time { lower = middle + 1 }
            else { upper = middle }
        }
        return lower
    }

    private func start(seconds: Int) -> TimeInterval? {
        guard seconds > 0, let last = samples.last else { return nil }
        return last.at - Double(seconds)
    }
}

struct ProcessTransfer: Identifiable, Equatable, Sendable {
    static let limit = 8

    let id: Int32
    let name: String
    let first: Double
    let second: Double
    let bundlePath: String?
}

struct TransferCounter: Equatable, Sendable {
    let pid: Int32
    let identity: String
    let first: UInt64
    let second: UInt64
}

struct TransferRateReader {
    private var previous: [Int32: TransferCounter] = [:]
    private var previousAt: TimeInterval?

    mutating func read(_ rows: [TransferCounter], at time: TimeInterval, includeIdle: Bool = false) -> [ProcessTransfer] {
        let elapsed = previousAt.map { time - $0 } ?? 0
        let next = Dictionary(rows.map { ($0.pid, $0) }, uniquingKeysWith: { _, last in last })
        defer { previous = next; previousAt = time }
        guard elapsed > 0 else { return [] }
        let deltas = next.values.compactMap { row -> (TransferCounter, Double, Double)? in
            guard let old = previous[row.pid], old.identity == row.identity else { return nil }
            let first = row.first >= old.first ? Double(row.first - old.first) / elapsed : 0
            let second = row.second >= old.second ? Double(row.second - old.second) / elapsed : 0
            return includeIdle || first + second > 0 ? (row, first, second) : nil
        }
        return Self.ranked(deltas)
    }

    static func ranked(_ deltas: [(TransferCounter, Double, Double)]) -> [ProcessTransfer] {
        deltas.sorted {
            let lhs = $0.1 + $0.2
            let rhs = $1.1 + $1.2
            if lhs != rhs { return lhs > rhs }
            let lhsTotal = Double($0.0.first) + Double($0.0.second)
            let rhsTotal = Double($1.0.first) + Double($1.0.second)
            return lhsTotal == rhsTotal ? $0.0.pid < $1.0.pid : lhsTotal > rhsTotal
        }.prefix(ProcessTransfer.limit).map { row, first, second in
            let bundle = Self.bundlePath(row.pid)
            let label = bundle.flatMap { Bundle(path: $0)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String }
                ?? Self.processName(row.pid)
                ?? (row.identity.allSatisfy(\.isNumber) ? "PID \(row.pid)" : row.identity)
            return ProcessTransfer(id: row.pid, name: label, first: first, second: second, bundlePath: bundle)
        }
    }

    private static func bundlePath(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4_096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return ProcessReader.outermostBundle(of: String(cString: buffer))
    }

    private static func processName(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 1024)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }
}

enum TransferSource: Equatable, Sendable {
    case disk, network

    static func networkRates() -> [ProcessTransfer]? {
        // nettop needs one session with a baseline and then a delta. Comparing
        // totals from separate launches loses connections that closed between them.
        guard let data = Subprocess.output("/usr/bin/nettop", ["-n", "-P", "-d", "-s", "1", "-L", "2", "-x", "-J", "bytes_in,bytes_out"], timeout: 5),
              let output = String(data: data, encoding: .utf8) else { return nil }
        return parseNettopRates(output)
    }

    static func diskCounters() -> [TransferCounter]? {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return nil }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let read = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard read > 0 else { return nil }
        let rows = pids.prefix(min(Int(read), pids.count)).compactMap { pid -> TransferCounter? in
            guard pid > 0 else { return nil }
            var info = rusage_info_v2()
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
            }
            guard result == 0 else { return nil }
            return TransferCounter(pid: pid, identity: String(info.ri_proc_start_abstime),
                                   first: info.ri_diskio_bytesread, second: info.ri_diskio_byteswritten)
        }
        return rows.isEmpty ? nil : rows
    }

    static func parseNettopRates(_ output: String) -> [ProcessTransfer]? {
        let frames = nettopFrames(output)
        guard frames.count == 2 else { return nil }
        return TransferRateReader.ranked(frames[1].map { ($0, Double($0.first), Double($0.second)) })
    }

    static func nettopFrames(_ output: String) -> [[TransferCounter]] {
        var columns: (input: Int, output: Int)?
        var frames: [[TransferCounter]] = []
        var rows: [TransferCounter] = []
        for line in output.split(whereSeparator: \.isNewline) {
            let cells = csvFields(line)
            if let input = cells.firstIndex(of: "bytes_in"), let output = cells.firstIndex(of: "bytes_out") {
                if columns != nil { frames.append(rows) }
                rows.removeAll(keepingCapacity: true)
                columns = (input, output)
                continue
            }
            guard let columns, cells.count > max(columns.input, columns.output),
                  let received = UInt64(cells[columns.input]), let sent = UInt64(cells[columns.output]) else { continue }
            for label in cells.prefix(min(columns.input, columns.output)).reversed() {
                guard !label.contains(":"), let dot = label.lastIndex(of: "."),
                      let pid = Int32(label[label.index(after: dot)...]), pid > 0 else { continue }
                rows.append(TransferCounter(pid: pid, identity: String(label[..<dot]), first: sent, second: received))
                break
            }
        }
        if columns != nil { frames.append(rows) }
        return frames
    }

    private static func csvFields(_ line: Substring) -> [String] {
        var fields: [String] = []
        var field = ""
        var quoted = false
        var iterator = line.makeIterator()
        while let char = iterator.next() {
            if char == "\"" { quoted.toggle() }
            else if char == ",", !quoted {
                fields.append(field.trimmingCharacters(in: .whitespaces))
                field = ""
            } else { field.append(char) }
        }
        fields.append(field.trimmingCharacters(in: .whitespaces))
        return fields
    }
}

struct NetworkProcessSnapshot {
    private var rows: [ProcessTransfer] = []
    private var lastSuccess: TimeInterval?

    func recentRows(at time: TimeInterval) -> [ProcessTransfer]? {
        guard let lastSuccess, time - lastSuccess < 8 else { return nil }
        return rows
    }

    mutating func update(_ incoming: [ProcessTransfer]?, at time: TimeInterval) -> ProcessTransferMonitor.Result {
        guard let incoming, !incoming.isEmpty else {
            if let recent = recentRows(at: time) { return .rows(recent) }
            return incoming == nil ? .unavailable : .rows([])
        }

        let previous = recentRows(at: time) ?? []
        let previousIDs = Set(previous.map(\.id))
        var seen = Set<Int32>()
        let unique = incoming.filter { seen.insert($0.id).inserted }
        let latest = Dictionary(unique.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var additions = unique.filter { !previousIDs.contains($0.id) }.makeIterator()
        rows = previous.compactMap { latest[$0.id] ?? additions.next() }
        rows.append(contentsOf: IteratorSequence(additions))
        lastSuccess = time
        return .rows(rows)
    }
}

/// The open flyout owns the sampling interval. The rows can be laid out or
/// replaced while this monitor keeps the disk baseline and the current result.
@MainActor
final class ProcessTransferMonitor: ObservableObject {
    enum Result: Equatable {
        case sampling, unavailable, rows([ProcessTransfer])
    }

    @Published private(set) var result = Result.sampling
    private(set) var source: TransferSource?
    private var job: Task<Void, Never>?
    private var diskReader = TransferRateReader()
    private var networkSnapshot = NetworkProcessSnapshot()
    private lazy var poller = IntervalPoller { [weak self] in self?.sample() }

    func show(_ source: TransferSource?) {
        guard self.source != source else { return }
        job?.cancel()
        job = nil
        poller.set(owner: "transfer", interval: nil)
        self.source = source
        diskReader = TransferRateReader()
        if source == .network, let recent = networkSnapshot.recentRows(at: ProcessInfo.processInfo.systemUptime) {
            result = .rows(recent)
        } else {
            result = .sampling
        }
        if source != nil { poller.set(owner: "transfer", interval: 2) }
    }

    private func sample() {
        guard let source, job == nil else { return }
        job = Task { [weak self] in
            switch source {
            case .disk:
                let counters = await Task.detached(priority: .utility) { TransferSource.diskCounters() }.value
                guard let self, !Task.isCancelled else { return }
                if let counters {
                    let rows = diskReader.read(counters, at: ProcessInfo.processInfo.systemUptime, includeIdle: true)
                    // Even the initial pass can display the real processes that
                    // have recorded I/O, with zero until the first rate is known.
                    result = .rows(rows.isEmpty ? TransferRateReader.ranked(counters
                        .filter { $0.first > 0 || $0.second > 0 }
                        .map { ($0, 0, 0) }) : rows)
                } else {
                    diskReader = TransferRateReader()
                    result = .unavailable
                }
                job = nil
            case .network:
                let rows = await Task.detached(priority: .utility) { TransferSource.networkRates() }.value
                guard let self, !Task.isCancelled else { return }
                let updated = networkSnapshot.update(rows, at: ProcessInfo.processInfo.systemUptime)
                if result != updated { result = updated }
                job = nil
            }
        }
    }
}
