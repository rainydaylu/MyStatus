import AppKit
import Foundation

/// Background: measure [0,60], [300,360], ... . Foreground: [0,60], [60,120], ... .
/// A five-minute counter delta must never be presented as a one-minute average.
struct AppEnergySchedule {
    enum Kind: Equatable { case baseline, finish }
    struct Request: Equatable { let kind: Kind; let deadline: Double }
    private(set) var enabled = false
    private(set) var foreground = false
    private(set) var next: Request?
    private var windowStart: Double?
    static let window: Double = 60
    static let backgroundPeriod: Double = 300

    mutating func configure(enabled: Bool, foreground: Bool, at now: Double) {
        let wasEnabled = self.enabled
        let wasForeground = self.foreground
        self.enabled = enabled
        self.foreground = foreground
        if !enabled { next = nil; windowStart = nil; return }
        if !wasEnabled {
            restart(at: now)
        } else if foreground, !wasForeground, next?.kind == .baseline {
            // Show the cached result immediately; start a fresh minute now.
            restart(at: now)
        }
        // Reopening during an existing minute keeps that baseline and deadline.
    }

    mutating func restart(at now: Double) {
        windowStart = nil
        next = enabled ? Request(kind: .baseline, deadline: now) : nil
    }

    mutating func completed(_ request: Request, at now: Double, measured: Bool) {
        guard enabled, next == request else { return }
        if request.kind == .baseline || !measured {
            windowStart = now
            next = Request(kind: .finish, deadline: now + Self.window)
        } else if foreground {
            windowStart = now
            next = Request(kind: .finish, deadline: now + Self.window)
        } else {
            let start = windowStart ?? now - Self.window
            windowStart = nil
            next = Request(kind: .baseline, deadline: max(now, start + Self.backgroundPeriod))
        }
    }
}

/// Only one compact result is cached, not a record of the user's process history.
struct AppEnergyResultCache {
    let file: URL
    private struct Record: Codable { let version: Int; let value: AppEnergyStats }

    static var standard: Self {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("StatusDeck", isDirectory: true)
        return Self(file: folder.appendingPathComponent("app-energy-cache.json"))
    }

    func load(now: Date = Date()) -> AppEnergyStats? {
        guard let data = try? Data(contentsOf: file), data.count <= 65_536,
              let record = try? JSONDecoder().decode(Record.self, from: data), record.version == 1 else { return nil }
        let value = record.value
        guard value.state == .ready, value.seconds.isFinite, (55...90).contains(value.seconds),
              let date = value.sampledAt, (-5...86_400).contains(now.timeIntervalSince(date)),
              value.entries.count <= 5,
              value.entries.allSatisfy({ $0.watts.isFinite && (0...1_000).contains($0.watts) }),
              [value.chipWatts, value.appWatts].compactMap({ $0 }).allSatisfy({ $0.isFinite && (0...1_000).contains($0) }) else { return nil }
        return value
    }

    func save(_ value: AppEnergyStats) {
        guard value.state == .ready, value.sampledAt != nil, (55...90).contains(value.seconds),
              let data = try? JSONEncoder().encode(Record(version: 1, value: value)) else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch { /* In-memory caching still works if storage is unavailable. */ }
    }
}

/// One coalescible timer on the existing sampler queue. It does not poll or
/// keep the Mac awake. Only cumulative counter endpoints are read.
final class AppEnergyMonitor {
    private let queue: DispatchQueue
    private let publish: (AppEnergyStats) -> Void
    private let reader = AppEnergyReader()
    private let cache: AppEnergyResultCache
    private var schedule = AppEnergySchedule()
    private var timer: DispatchSourceTimer?
    private var cached: AppEnergyStats
    private var lastSaved: Double = -.infinity
    private var wakeObserver: NSObjectProtocol?

    init(queue: DispatchQueue, cache: AppEnergyResultCache = .standard, publish: @escaping (AppEnergyStats) -> Void) {
        self.queue = queue
        self.cache = cache
        self.publish = publish
        cached = cache.load() ?? AppEnergyStats()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                                        object: nil, queue: nil) { [weak self] _ in
            self?.queue.async { [weak self] in
                guard let self else { return }
                self.reader.reset()
                self.schedule.restart(at: ProcessInfo.processInfo.systemUptime)
                self.arm()
            }
        }
    }

    deinit {
        timer?.cancel()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    /// Called on the sampler queue whenever ownership or detail visibility changes.
    func configure(enabled: Bool, foreground: Bool) {
        let wasEnabled = schedule.enabled
        let now = ProcessInfo.processInfo.systemUptime
        schedule.configure(enabled: enabled, foreground: foreground, at: now)
        if !enabled {
            timer?.cancel(); timer = nil
            reader.reset()
        } else {
            if !wasEnabled { publish(cached) }
            arm()
        }
    }

    private func arm() {
        timer?.cancel(); timer = nil
        guard let request = schedule.next else { return }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + max(0, request.deadline - ProcessInfo.processInfo.systemUptime),
                        leeway: .milliseconds(250))
        source.setEventHandler { [weak self] in
            guard let self, self.schedule.next == request else { return }
            if request.kind == .baseline { self.reader.reset() }
            let result = self.reader.read()
            let now = ProcessInfo.processInfo.systemUptime
            let measured = result.state == .ready && result.seconds >= 55
            if measured {
                self.cached = result
                // At most one tiny disk write every five minutes. Menu reopening
                // always uses memory and never triggers an extra cache write.
                if now - self.lastSaved >= AppEnergySchedule.backgroundPeriod {
                    self.cache.save(result)
                    self.lastSaved = now
                }
            } else if self.cached.state != .ready {
                self.cached = result
            }
            self.publish(self.cached)
            self.schedule.completed(request, at: now, measured: measured)
            self.arm()
        }
        timer = source
        source.resume()
    }
}
