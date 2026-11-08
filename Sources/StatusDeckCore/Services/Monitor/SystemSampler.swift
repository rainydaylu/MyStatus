import Combine
import Foundation

struct Metric: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let cpu = Metric(rawValue: 1 << 0)
    static let gpu = Metric(rawValue: 1 << 1)
    static let soc = Metric(rawValue: 1 << 2)
    static let memory = Metric(rawValue: 1 << 3)
    static let disk = Metric(rawValue: 1 << 4)
    static let network = Metric(rawValue: 1 << 5)
    static let sensors = Metric(rawValue: 1 << 6)
    static let battery = Metric(rawValue: 1 << 7)
    static let processes = Metric(rawValue: 1 << 8)
    static let system = Metric(rawValue: 1 << 9)
}

/// Owns every reader and calls them from one serial queue. Only what some enabled
/// plugin asked for is read, and most of that only while the panel is open, so a
/// monitoring tool does not become a noticeable load of its own.
final class SystemSampler {
    var onSample: ((SystemSnapshot) -> Void)?

    private let queue = DispatchQueue(label: "statusdeck.sampler", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var always: [String: Metric] = [:]
    private var whileVisible: [String: Metric] = [:]
    private var isPanelVisible = false
    private var interval: TimeInterval = 1
    private var tick = 0
    private var snapshot = SystemSnapshot()

    private let cpu = CPUReader()
    private let gpu = GPUReader()
    private let memory = MemoryReader()
    private let disk = DiskReader()
    private let network = NetworkReader()
    private let battery = BatteryReader()
    private let processes = ProcessReader()
    private lazy var temperatures = TemperatureReader()
    private lazy var smc = SMCClient()
    private lazy var ioReport = IOReportReader()

    /// What this owner wants. An owner with empty sets has effectively withdrawn.
    func setInterest(owner: String, always newAlways: Metric = [], whilePanelVisible newVisible: Metric = []) {
        queue.async { [self] in
            always[owner] = newAlways.isEmpty ? nil : newAlways
            whileVisible[owner] = newVisible.isEmpty ? nil : newVisible
            reconcile(sampleNow: true)
        }
    }

    func removeInterest(owner: String) {
        setInterest(owner: owner)
    }

    func setPanelVisible(_ visible: Bool) {
        queue.async { [self] in
            guard isPanelVisible != visible else { return }
            isPanelVisible = visible
            if visible {
                ioReport?.reset()
                tick = 0
            }
            reconcile(sampleNow: visible)
        }
    }

    func setInterval(_ newInterval: TimeInterval) {
        queue.async { [self] in
            guard interval != newInterval else { return }
            interval = newInterval
            restartTimer()
        }
    }

    func refreshBattery() {
        queue.async { [self] in
            snapshot.battery = battery.read()
            snapshot.sampledMetrics = []
            onSample?(snapshot)
        }
    }

    private var active: Metric {
        var metrics = always.values.reduce(into: Metric()) { $0.formUnion($1) }
        if isPanelVisible { metrics = whileVisible.values.reduce(into: metrics) { $0.formUnion($1) } }
        return metrics
    }

    private func reconcile(sampleNow: Bool) {
        if active.isEmpty {
            timer?.cancel()
            timer = nil
        } else if timer == nil {
            restartTimer()
        } else if sampleNow {
            sample()
        }
    }

    private func restartTimer() {
        timer?.cancel()
        timer = nil
        guard !active.isEmpty else { return }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(100))
        source.setEventHandler { [weak self] in self?.sample() }
        source.resume()
        timer = source
    }

    private func sample() {
        defer { tick &+= 1 }
        let metrics = active
        snapshot.sampledMetrics = metrics
        if metrics.contains(.cpu) { snapshot.cpu = cpu.read() }
        if metrics.contains(.memory) { snapshot.memory = memory.read() }
        if metrics.contains(.network) { snapshot.network = network.read() }
        // Slow-changing values are spaced out by multiples of the tick.
        if metrics.contains(.battery), tick % (isPanelVisible ? 5 : 30) == 0 { snapshot.battery = battery.read() }
        if metrics.contains(.gpu) { snapshot.gpu = gpu.read() }
        if metrics.contains(.soc) {
            // The first read after opening only starts an interval and comes back
            // empty, so the previous values stay up instead of flashing to dashes.
            if let reading = ioReport?.read(), reading != SoCStats() { snapshot.soc = reading }
        }
        if metrics.contains(.system) {
            snapshot.uptime = SystemControl.uptime()
            snapshot.loadAverage = SystemControl.loadAverage()
        }
        if metrics.contains(.disk) {
            let rates = disk.activity()
            snapshot.disk.readBytesPerSecond = rates.read
            snapshot.disk.writeBytesPerSecond = rates.write
            snapshot.disk.totalReadBytes = rates.totalRead
            snapshot.disk.totalWrittenBytes = rates.totalWrite
            if isPanelVisible, tick % 10 == 0 || snapshot.disk.volumes.isEmpty { snapshot.disk.volumes = disk.volumes() }
        }
        if metrics.contains(.sensors), tick % 2 == 0 {
            if let temperatures { snapshot.sensors.temperatures = temperatures.read() }
            if let smc {
                snapshot.sensors.fans = smc.fans()
                snapshot.sensors.systemWatts = smc.read("PSTR")
                snapshot.sensors.adapterInputWatts = smc.read("PDTR")
            }
        }
        if metrics.contains(.processes), tick % 3 == 0 { snapshot.processes = processes.read() }
        onSample?(snapshot)
    }
}

/// Rolling series behind the graphs.
struct History: Equatable {
    static let capacity = 72

    var cpuUser: [Double] = []
    var cpuSystem: [Double] = []
    var upload: [Double] = []
    var download: [Double] = []
    var memoryPressure: [Double] = []
    var gpu: [Double] = []
    var diskActivity = TransferHistory()
    var networkActivity = TransferHistory()

    mutating func append(_ snapshot: SystemSnapshot, includesPanelOnlySeries: Bool) {
        Self.push(snapshot.cpu.user, to: &cpuUser)
        Self.push(snapshot.cpu.system, to: &cpuSystem)
        let now = ProcessInfo.processInfo.systemUptime
        if snapshot.sampledMetrics.contains(.network) {
            Self.push(snapshot.network.uploadBytesPerSecond, to: &upload)
            Self.push(snapshot.network.downloadBytesPerSecond, to: &download)
            networkActivity.append(snapshot.network.uploadBytesPerSecond, snapshot.network.downloadBytesPerSecond, at: now)
        }
        if snapshot.sampledMetrics.contains(.disk) {
            diskActivity.append(snapshot.disk.readBytesPerSecond, snapshot.disk.writeBytesPerSecond, at: now)
        }
        Self.push(snapshot.memory.pressure, to: &memoryPressure)
        if includesPanelOnlySeries {
            Self.push(snapshot.gpu.utilization, to: &gpu)
        }
    }

    private static func push(_ value: Double, to series: inout [Double]) {
        series.append(value)
        if series.count > capacity { series.removeFirst(series.count - capacity) }
    }
}

/// The main-actor side of the sampler: what views and menu bar icons observe.
@MainActor
final class SystemStore: ObservableObject {
    @Published private(set) var snapshot = SystemSnapshot()
    @Published private(set) var history = History()

    let sampler = SystemSampler()
    private var isPanelVisible = false

    init() {
        sampler.onSample = { [weak self] snapshot in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.receive(snapshot) }
            }
        }
    }

    func setPanelVisible(_ visible: Bool) {
        isPanelVisible = visible
        sampler.setPanelVisible(visible)
    }

    private func receive(_ next: SystemSnapshot) {
        snapshot = next
        history.append(next, includesPanelOnlySeries: isPanelVisible)
    }
}
