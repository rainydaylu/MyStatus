import StatusDeckKit
import Foundation

// Plain values produced by the sampler and read by the UI. Nothing here touches
// a system API, so the formatting and maths around them stay easy to test.

enum CoreKind: Sendable {
    case efficiency
    case performance
}

struct CoreLoad: Identifiable, Equatable, Sendable {
    let id: Int
    let kind: CoreKind
    var user: Double
    var system: Double
    var total: Double { min(1, user + system) }
}

struct CPUStats: Equatable, Sendable {
    var user = 0.0
    var system = 0.0
    var cores: [CoreLoad] = []

    var total: Double { min(1, user + system) }
    var efficiencyCores: [CoreLoad] { cores.filter { $0.kind == .efficiency } }
    var performanceCores: [CoreLoad] { cores.filter { $0.kind == .performance } }
    var efficiencyAverage: Double { Self.average(efficiencyCores) }
    var performanceAverage: Double { Self.average(performanceCores) }

    private static func average(_ cores: [CoreLoad]) -> Double {
        cores.isEmpty ? 0 : cores.map(\.total).reduce(0, +) / Double(cores.count)
    }
}

struct GPUStats: Equatable, Sendable {
    var utilization = 0.0
    var renderer = 0.0
    var tiler = 0.0
    var memoryInUse: UInt64 = 0
}

/// Frequency and energy readings from IOReport. `nil` means the channel is not
/// published on this machine, which the UI shows as a dash rather than zero.
struct SoCStats: Equatable, Sendable {
    var cpuFrequencyMHz: Double?
    var efficiencyFrequencyMHz: Double?
    var performanceFrequencyMHz: Double?
    var gpuFrequencyMHz: Double?
    var cpuWatts: Double?
    var gpuWatts: Double?
    var aneWatts: Double?
    var dramWatts: Double?
}

struct MemoryStats: Equatable, Sendable {
    var total: UInt64 = 0
    var app: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var cached: UInt64 = 0
    var free: UInt64 = 0
    var swapTotal: UInt64 = 0
    var swapUsed: UInt64 = 0
    /// 0...1, derived from `kern.memorystatus_level`.
    var pressure = 0.0
    /// 1 normal, 2 warning, 4 critical, as `kern.memorystatus_vm_pressure_level` reports it.
    var pressureLevel = 1
    var pageInBytesPerSecond = 0.0
    var pageOutBytesPerSecond = 0.0

    var used: UInt64 { app + wired + compressed }
    /// What the used memory leaves over, cache included, as Activity Monitor reckons it.
    var available: UInt64 { total > used ? total - used : 0 }
    var usedFraction: Double { total == 0 ? 0 : min(1, Double(used) / Double(total)) }
}

struct VolumeStats: Identifiable, Equatable, Sendable {
    var id: String { path }
    let path: String
    let name: String
    let total: UInt64
    let available: UInt64
    let isRoot: Bool

    var usedFraction: Double {
        total == 0 ? 0 : min(1, 1 - Double(available) / Double(total))
    }
}

struct DiskStats: Equatable, Sendable {
    var volumes: [VolumeStats] = []
    var readBytesPerSecond = 0.0
    var writeBytesPerSecond = 0.0
    var totalReadBytes: UInt64 = 0
    var totalWrittenBytes: UInt64 = 0

    var root: VolumeStats? { volumes.first(where: \.isRoot) ?? volumes.first }
}

struct InterfaceStats: Identifiable, Equatable, Sendable {
    var id: String { name }
    let name: String
    var ipv4: String?
    var ipv6: String?
    var isPrimary = false
}

struct NetworkStats: Equatable, Sendable {
    var uploadBytesPerSecond = 0.0
    var downloadBytesPerSecond = 0.0
    var uploadedSinceLaunch: UInt64 = 0
    var downloadedSinceLaunch: UInt64 = 0
    var interfaces: [InterfaceStats] = []
    var router: String?
}

struct TemperatureReading: Identifiable, Equatable, Sendable {
    enum Group: Int, CaseIterable, Sendable {
        case cpu, gpu, soc, storage, battery, board

        var title: String {
            switch self {
            case .cpu: "CPU"
            case .gpu: "GPU"
            case .soc: "SoC"
            case .storage: DeckL("固态硬盘")
            case .battery: DeckL("电池")
            case .board: DeckL("主板")
            }
        }
    }

    var id: String { name }
    let name: String
    let group: Group
    let celsius: Double
}

struct FanReading: Identifiable, Equatable, Sendable {
    let id: Int
    let rpm: Double
    let minimumRPM: Double?
    let maximumRPM: Double?

    var isOff: Bool { rpm < 1 }
    var name: String { "风扇 \(id + 1)" }

    var fraction: Double {
        guard let maximumRPM, maximumRPM > 0 else { return isOff ? 0 : 1 }
        return min(1, rpm / maximumRPM)
    }
}

struct SensorStats: Equatable, Sendable {
    var temperatures: [TemperatureReading] = []
    var fans: [FanReading] = []
    var systemWatts: Double?
    var adapterInputWatts: Double?

    func average(_ group: TemperatureReading.Group) -> Double? {
        let values = temperatures.filter { $0.group == group }.map(\.celsius)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    func maximum(_ group: TemperatureReading.Group) -> Double? {
        temperatures.filter { $0.group == group }.map(\.celsius).max()
    }
}

struct BatteryStats: Equatable, Sendable {
    var isPresent = false
    var percent = 0
    var isCharging = false
    var isFullyCharged = false
    var isExternalPowerConnected = false
    var minutesRemaining: Int?
    var cycleCount: Int?
    /// Full-charge capacity against design capacity, 0...1.
    var health: Double?
    var temperatureCelsius: Double?
    var volts: Double?
    var amps: Double?
    var adapterWatts: Int?
    var isLowPowerMode = false

    var watts: Double? {
        guard let volts, let amps else { return nil }
        return volts * amps
    }

    var statusText: String {
        guard isPresent else { return DeckL("无电池") }
        if isFullyCharged { return DeckL("已充电") }
        if isCharging { return DeckL("充电中") }
        if isExternalPowerConnected { return DeckL("已接电源") }
        return DeckL("使用电池")
    }
}

struct ProcessEntry: Identifiable, Equatable, Sendable {
    /// The outermost `.app` bundle path, or the bare process name for a daemon.
    let id: String
    let name: String
    let bundlePath: String?
    /// Share of all logical CPUs, 0...1.
    let cpu: Double
    let memory: UInt64
}

struct ProcessStats: Equatable, Sendable {
    var byCPU: [ProcessEntry] = []
    var byMemory: [ProcessEntry] = []
}

struct SystemSnapshot: Equatable, Sendable {
    var sampledMetrics: Metric = []
    var cpu = CPUStats()
    var gpu = GPUStats()
    var soc = SoCStats()
    var memory = MemoryStats()
    var disk = DiskStats()
    var network = NetworkStats()
    var sensors = SensorStats()
    var battery = BatteryStats()
    var processes = ProcessStats()
    var uptime: TimeInterval = 0
    var loadAverage: [Double] = [0, 0, 0]

    init() {}
}
