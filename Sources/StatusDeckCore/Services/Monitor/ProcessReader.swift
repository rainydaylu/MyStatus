import Darwin
import Foundation

/// A bounded subprocess. `system_profiler` and `pmset` can hang, and a sampler
/// must never wait on them forever.
enum Subprocess {
    static func output(_ path: String, _ arguments: [String], timeout: TimeInterval = 8) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return process.terminationStatus == 0 ? data : nil
    }
}

/// Top processes, grouped by app so that a browser and its helpers read as one.
///
/// `ps` is used because it is setuid and can see other users' processes, which
/// libproc cannot: without it `WindowServer` and `kernel_task` would be missing.
final class ProcessReader {
    private var bundlePaths: [Int32: String?] = [:]
    private let coreCount = max(1, ProcessInfo.processInfo.activeProcessorCount)

    func read(limit: Int = 5) -> ProcessStats {
        guard let data = Subprocess.output("/bin/ps", ["-Aceo", "pid=,pcpu=,rss=,comm="], timeout: 4),
              let text = String(data: data, encoding: .utf8) else {
            return ProcessStats()
        }
        let rows = Self.parse(text)

        struct Group { var name: String; var bundle: String?; var cpu = 0.0; var memory: UInt64 = 0 }
        var groups: [String: Group] = [:]
        var seen = Set<Int32>()
        for row in rows {
            seen.insert(row.pid)
            let bundle = bundlePath(for: row.pid)
            let key = bundle ?? row.name
            var group = groups[key] ?? Group(
                name: bundle.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? row.name,
                bundle: bundle
            )
            group.cpu += row.cpuPercent
            group.memory += row.residentBytes
            groups[key] = group
        }
        // Forget exited pids so the cache cannot grow without bound or reuse a stale path.
        bundlePaths = bundlePaths.filter { seen.contains($0.key) }

        let entries = groups.map { key, group in
            ProcessEntry(id: key, name: group.name, bundlePath: group.bundle,
                         cpu: group.cpu / 100 / Double(coreCount), memory: group.memory)
        }
        return ProcessStats(
            byCPU: Array(entries.sorted { $0.cpu > $1.cpu }.prefix(limit)),
            byMemory: Array(entries.sorted { $0.memory > $1.memory }.prefix(limit))
        )
    }

    struct Row: Equatable {
        let pid: Int32
        let cpuPercent: Double
        let residentBytes: UInt64
        let name: String
    }

    static func parse(_ text: String) -> [Row] {
        text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int32(parts[0]), let cpu = Double(parts[1]), let kilobytes = UInt64(parts[2]) else {
                return nil
            }
            return Row(pid: pid, cpuPercent: cpu, residentBytes: kilobytes * 1024, name: String(parts[3]))
        }
    }

    private func bundlePath(for pid: Int32) -> String? {
        if let cached = bundlePaths[pid] { return cached }
        var buffer = [CChar](repeating: 0, count: 4096)
        var path: String?
        if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
            path = Self.outermostBundle(of: String(cString: buffer))
        }
        bundlePaths[pid] = path
        return path
    }

    /// "/Applications/Foo.app/Contents/Frameworks/Bar Helper.app/Contents/MacOS/Bar" → "/Applications/Foo.app"
    static func outermostBundle(of executablePath: String) -> String? {
        guard let range = executablePath.range(of: ".app/") else { return nil }
        return String(executablePath[..<range.lowerBound]) + ".app"
    }
}
