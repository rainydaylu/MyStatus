import Darwin
import Foundation

/// Keep one hour of timestamped measurements. Each bar is the peak within its time bin.
struct TransferHistory: Equatable {
    private struct Sample: Equatable {
        let at: TimeInterval
        let first: Double
        let second: Double
    }

    private var samples: [Sample] = []

    mutating func append(_ first: Double, _ second: Double, at time: TimeInterval) {
        samples.append(Sample(at: time, first: first, second: second))
        let cutoff = time - 3600
        if let first = samples.firstIndex(where: { $0.at >= cutoff }), first > 0 {
            samples.removeFirst(first)
        }
        // Also bound memory if several immediate samples share one timestamp.
        if samples.count > 4_096 { samples.removeFirst(samples.count - 4_096) }
    }

    func bins(seconds: Int, count: Int) -> (first: [Double], second: [Double]) {
        var first = Array(repeating: 0.0, count: count)
        var second = first
        guard let last = samples.last else { return (first, second) }
        let start = last.at - Double(seconds)
        for sample in samples.reversed() {
            guard sample.at >= start else { break }
            let index = min(count - 1, Int((sample.at - start) / Double(seconds) * Double(count)))
            first[index] = max(first[index], sample.first)
            second[index] = max(second[index], sample.second)
        }
        return (first, second)
    }
}

struct ProcessTransfer: Identifiable, Equatable, Sendable {
    let id: Int32
    let name: String
    let first: Double
    let second: Double
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

    mutating func read(_ rows: [TransferCounter], at time: TimeInterval, limit: Int = 8) -> [ProcessTransfer] {
        let elapsed = previousAt.map { time - $0 } ?? 0
        let next = Dictionary(rows.map { ($0.pid, $0) }, uniquingKeysWith: { _, last in last })
        defer { previous = next; previousAt = time }
        guard elapsed > 0 else { return [] }
        let deltas = next.values.compactMap { row -> (TransferCounter, Double, Double)? in
            guard let old = previous[row.pid], old.identity == row.identity else { return nil }
            let first = row.first >= old.first ? Double(row.first - old.first) / elapsed : 0
            let second = row.second >= old.second ? Double(row.second - old.second) / elapsed : 0
            return first + second > 0 ? (row, first, second) : nil
        }
        return deltas.sorted {
            let lhs = $0.1 + $0.2
            let rhs = $1.1 + $1.2
            return lhs == rhs ? $0.0.pid < $1.0.pid : lhs > rhs
        }.prefix(limit).map { row, first, second in
            let label = Self.processName(row.pid) ?? (row.identity.allSatisfy(\.isNumber) ? "PID \(row.pid)" : row.identity)
            return ProcessTransfer(id: row.pid, name: label, first: first, second: second)
        }
    }

    private static func processName(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 1024)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }
}

enum TransferSource: Sendable {
    case disk, network

    func counters() -> [TransferCounter]? {
        switch self {
        case .disk: return Self.diskCounters()
        case .network:
            guard let data = Subprocess.output("/usr/bin/nettop", ["-P", "-L", "1", "-x", "-J", "bytes_in,bytes_out"], timeout: 4),
                  let output = String(data: data, encoding: .utf8) else { return nil }
            return Self.parseNettop(output)
        }
    }

    private static func diskCounters() -> [TransferCounter]? {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return nil }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let read = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard read > 0 else { return nil }
        let rows = pids.prefix(Int(read)).compactMap { pid -> TransferCounter? in
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

    static func parseNettop(_ output: String) -> [TransferCounter]? {
        var columns: (input: Int, output: Int)?
        var rows: [TransferCounter] = []
        for line in output.split(whereSeparator: \.isNewline) {
            let cells = csvFields(line)
            if let input = cells.firstIndex(of: "bytes_in"), let output = cells.firstIndex(of: "bytes_out") {
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
        return columns == nil ? nil : rows
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
