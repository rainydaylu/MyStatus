import Darwin
import Foundation
import IOKit

// Every symbol in this file is private system API, resolved at runtime so a macOS
// that drops one loses that reading instead of failing to launch.

// MARK: - Temperatures (IOHIDEventSystem)

final class TemperatureReader {
    private typealias Create = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias SetMatching = @convention(c) (CFTypeRef, CFDictionary) -> Int32
    private typealias CopyServices = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    private typealias CopyProperty = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
    private typealias CopyEvent = @convention(c) (CFTypeRef, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
    private typealias GetFloat = @convention(c) (CFTypeRef, Int32) -> Double

    private let copyProperty: CopyProperty
    private let copyEvent: CopyEvent
    private let getFloat: GetFloat
    private let services: [CFTypeRef]

    private static let temperatureEvent: Int64 = 15
    private static let temperatureField: Int32 = 15 << 16

    init?() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
              let create = dlsym(handle, "IOHIDEventSystemClientCreate"),
              let setMatching = dlsym(handle, "IOHIDEventSystemClientSetMatching"),
              let copyServices = dlsym(handle, "IOHIDEventSystemClientCopyServices"),
              let copyProperty = dlsym(handle, "IOHIDServiceClientCopyProperty"),
              let copyEvent = dlsym(handle, "IOHIDServiceClientCopyEvent"),
              let getFloat = dlsym(handle, "IOHIDEventGetFloatValue") else {
            return nil
        }
        self.copyProperty = unsafeBitCast(copyProperty, to: CopyProperty.self)
        self.copyEvent = unsafeBitCast(copyEvent, to: CopyEvent.self)
        self.getFloat = unsafeBitCast(getFloat, to: GetFloat.self)

        guard let client = unsafeBitCast(create, to: Create.self)(kCFAllocatorDefault)?.takeRetainedValue() else {
            return nil
        }
        let matching = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary
        _ = unsafeBitCast(setMatching, to: SetMatching.self)(client, matching)
        guard let list = unsafeBitCast(copyServices, to: CopyServices.self)(client)?.takeRetainedValue() as? [CFTypeRef],
              !list.isEmpty else {
            return nil
        }
        services = list
        // The services stay valid only while their client does.
        retainedClient = client
    }

    private let retainedClient: CFTypeRef

    func read() -> [TemperatureReading] {
        var samples: [String: [Double]] = [:]
        for service in services {
            guard let name = copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String,
                  let event = copyEvent(service, Self.temperatureEvent, 0, 0)?.takeRetainedValue() else {
                continue
            }
            let value = getFloat(event, Self.temperatureField)
            if value > 0, value < 150 { samples[name, default: []].append(value) }
        }
        return Self.readings(from: samples)
    }

    /// The same sensor name is published several times, once per die or rail, so
    /// each name becomes one averaged reading.
    static func readings(from samples: [String: [Double]]) -> [TemperatureReading] {
        samples.compactMap { name, values -> TemperatureReading? in
            guard !values.isEmpty, let group = group(forSensor: name) else { return nil }
            return TemperatureReading(
                name: name,
                group: group,
                celsius: values.reduce(0, +) / Double(values.count)
            )
        }
        .sorted { lhs, rhs in
            lhs.group.rawValue != rhs.group.rawValue
                ? lhs.group.rawValue < rhs.group.rawValue
                : lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// `nil` drops the sensor. `tcal` is a fixed calibration value, not a temperature.
    static func group(forSensor name: String) -> TemperatureReading.Group? {
        let lower = name.lowercased()
        if lower.contains("tcal") { return nil }
        if lower.contains("gas gauge") || lower.contains("battery") { return .battery }
        if lower.contains("nand") { return .storage }
        if lower.contains("tdie") || lower.contains("acc mtr") || lower.contains("cpu") { return .cpu }
        if lower.contains("gpu") { return .gpu }
        if let range = lower.range(of: "tp"), let last = lower[range.upperBound...].last {
            if last == "g" { return .gpu }
            if last == "s" { return .soc }
        }
        if lower.contains("soc") { return .soc }
        return .board
    }
}

// MARK: - SMC (fans, whole-system power)

/// AppleSMC's 80-byte key-data ABI, encoded byte by byte. Read-only: the only
/// commands ever issued are 9 (key info) and 5 (read bytes), never 6 (write).
/// The layout and the power-sensor keys come from Status Trio's SystemPowerReader.
final class SMCClient {
    private var connection: io_connect_t = 0

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
    }

    deinit { IOServiceClose(connection) }

    func read(_ key: String) -> Double? {
        let code = key.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        var request = [UInt8](repeating: 0, count: 80)
        for offset in 0..<4 { request[offset] = UInt8(truncatingIfNeeded: code >> (offset * 8)) }
        request[42] = 9
        guard let info = exchange(request), info[40] == 0 else { return nil }
        let size = Self.littleEndian(info, at: 28)
        let type = Self.littleEndian(info, at: 32)
        guard size > 0, size <= 32 else { return nil }
        request.replaceSubrange(28..<32, with: info[28..<32])
        request[42] = 5
        guard let response = exchange(request), response[40] == 0 else { return nil }
        return Self.decode(type: type, payload: Array(response[48..<(48 + Int(size))]))
    }

    private func exchange(_ request: [UInt8]) -> [UInt8]? {
        var response = [UInt8](repeating: 0, count: 80)
        var size = response.count
        let result = request.withUnsafeBytes { input in
            response.withUnsafeMutableBytes { output in
                IOConnectCallStructMethod(connection, 2, input.baseAddress, input.count, output.baseAddress, &size)
            }
        }
        return result == KERN_SUCCESS && size == 80 ? response : nil
    }

    /// `flt ` and `ui16` are little-endian on Apple silicon; the fixed-point
    /// `fpe2` and `sp78` encodings stay big-endian.
    static func decode(type: UInt32, payload: [UInt8]) -> Double? {
        switch (type, payload.count) {
        case (0x666c7420, 4): // flt
            let value = Float(bitPattern: littleEndian(payload, at: 0))
            return value.isFinite ? Double(value) : nil
        case (0x66706532, 2): // fpe2
            return Double(UInt16(payload[0]) << 8 | UInt16(payload[1])) / 4
        case (0x73703738, 2): // sp78
            return Double(Int16(bitPattern: UInt16(payload[0]) << 8 | UInt16(payload[1]))) / 256
        case (0x75693820, 1): // ui8
            return Double(payload[0])
        case (0x75693136, 2): // ui16
            return Double(UInt16(payload[0]) | UInt16(payload[1]) << 8)
        case (0x75693332, 4): // ui32
            return Double(littleEndian(payload, at: 0))
        default:
            return nil
        }
    }

    private static func littleEndian(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }

    func fans() -> [FanReading] {
        let count = Int(read("FNum") ?? 0)
        guard count > 0, count <= 8 else { return [] }
        return (0..<count).compactMap { index in
            guard let rpm = read("F\(index)Ac") else { return nil }
            return FanReading(
                id: index,
                rpm: max(0, rpm),
                minimumRPM: read("F\(index)Mn"),
                maximumRPM: read("F\(index)Mx")
            )
        }
    }
}

// MARK: - Frequency and energy (IOReport)

/// Reads DVFS residency and energy counters without root, the same channels
/// `powermetrics` reports. Residency is only meaningful between two samples.
final class IOReportReader {
    private typealias CopyChannels = @convention(c) (CFString, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFDictionary>?
    private typealias MergeChannels = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Void
    private typealias CreateSubscription = @convention(c) (UnsafeRawPointer?, CFMutableDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>, UInt64, CFTypeRef?) -> Unmanaged<CFTypeRef>?
    private typealias CreateSamples = @convention(c) (CFTypeRef, CFMutableDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias CreateDelta = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias ChannelString = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias SimpleValue = @convention(c) (CFDictionary, Int32) -> Int64
    private typealias StateCount = @convention(c) (CFDictionary) -> Int32
    private typealias StateName = @convention(c) (CFDictionary, Int32) -> Unmanaged<CFString>?
    private typealias StateResidency = @convention(c) (CFDictionary, Int32) -> Int64

    private let createSamples: CreateSamples
    private let createDelta: CreateDelta
    private let group: ChannelString
    private let channelName: ChannelString
    private let unit: ChannelString
    private let simple: SimpleValue
    private let stateCount: StateCount
    private let stateResidency: StateResidency

    private let subscription: CFTypeRef
    private let channels: CFMutableDictionary
    private let tables: DVFSTables

    private var previous: (sample: CFDictionary, at: Date)?

    init?() {
        guard let handle = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY),
              let copyChannels = dlsym(handle, "IOReportCopyChannelsInGroup"),
              let merge = dlsym(handle, "IOReportMergeChannels"),
              let subscribe = dlsym(handle, "IOReportCreateSubscription"),
              let createSamples = dlsym(handle, "IOReportCreateSamples"),
              let createDelta = dlsym(handle, "IOReportCreateSamplesDelta"),
              let group = dlsym(handle, "IOReportChannelGetGroup"),
              let channelName = dlsym(handle, "IOReportChannelGetChannelName"),
              let unit = dlsym(handle, "IOReportChannelGetUnitLabel"),
              let simple = dlsym(handle, "IOReportSimpleGetIntegerValue"),
              let stateCount = dlsym(handle, "IOReportStateGetCount"),
              let stateResidency = dlsym(handle, "IOReportStateGetResidency") else {
            return nil
        }
        self.createSamples = unsafeBitCast(createSamples, to: CreateSamples.self)
        self.createDelta = unsafeBitCast(createDelta, to: CreateDelta.self)
        self.group = unsafeBitCast(group, to: ChannelString.self)
        self.channelName = unsafeBitCast(channelName, to: ChannelString.self)
        self.unit = unsafeBitCast(unit, to: ChannelString.self)
        self.simple = unsafeBitCast(simple, to: SimpleValue.self)
        self.stateCount = unsafeBitCast(stateCount, to: StateCount.self)
        self.stateResidency = unsafeBitCast(stateResidency, to: StateResidency.self)

        let copy = unsafeBitCast(copyChannels, to: CopyChannels.self)
        guard let energy = copy("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue(),
              let cpu = copy("CPU Stats" as CFString, "CPU Core Performance States" as CFString, 0, 0, 0)?.takeRetainedValue(),
              let gpu = copy("GPU Stats" as CFString, "GPU Performance States" as CFString, 0, 0, 0)?.takeRetainedValue() else {
            return nil
        }
        let mergeChannels = unsafeBitCast(merge, to: MergeChannels.self)
        mergeChannels(energy, cpu, nil)
        mergeChannels(energy, gpu, nil)
        guard let mutable = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, energy) else { return nil }

        var subscribed: Unmanaged<CFMutableDictionary>?
        guard let subscription = unsafeBitCast(subscribe, to: CreateSubscription.self)(nil, mutable, &subscribed, 0, nil)?.takeRetainedValue(),
              let channels = subscribed?.takeRetainedValue() else {
            return nil
        }
        self.subscription = subscription
        self.channels = channels
        self.tables = DVFSTables.read()
    }

    /// Forgets the last sample, so the next read starts a fresh interval instead
    /// of averaging over the time the panel was closed.
    func reset() { previous = nil }

    func read(now: Date = Date()) -> SoCStats {
        guard let sample = createSamples(subscription, channels, nil)?.takeRetainedValue() else { return SoCStats() }
        defer { previous = (sample, now) }
        guard let previous,
              let delta = createDelta(previous.sample, sample, nil)?.takeRetainedValue(),
              let entries = (delta as NSDictionary)["IOReportChannels"] as? [CFDictionary] else {
            return SoCStats()
        }
        let elapsed = now.timeIntervalSince(previous.at)
        guard elapsed > 0 else { return SoCStats() }

        var stats = SoCStats()
        var efficiency = FrequencyAccumulator()
        var performance = FrequencyAccumulator()
        var superCores = FrequencyAccumulator()
        var graphics = FrequencyAccumulator()

        for entry in entries {
            let groupName = group(entry)?.takeUnretainedValue() as String? ?? ""
            let name = channelName(entry)?.takeUnretainedValue() as String? ?? ""
            if groupName == "Energy Model" {
                let joules = Double(simple(entry, 0)) * Self.joules(perUnit: unit(entry)?.takeUnretainedValue() as String? ?? "")
                switch name {
                case "CPU Energy": stats.cpuWatts = joules / elapsed
                case "GPU Energy": stats.gpuWatts = joules / elapsed
                case _ where name.hasPrefix("ANE"): stats.aneWatts = (stats.aneWatts ?? 0) + joules / elapsed
                case _ where name.hasPrefix("DRAM"): stats.dramWatts = (stats.dramWatts ?? 0) + joules / elapsed
                default: break
                }
                continue
            }
            let residencies = (0..<max(0, stateCount(entry))).map { Double(stateResidency(entry, $0)) }
            if groupName == "CPU Stats" {
                if name.hasPrefix("ECPU") {
                    efficiency.add(residencies: residencies, table: tables.efficiency, tableIncludesIdle: false)
                } else if name.hasPrefix("MCPU") {
                    performance.add(residencies: residencies, table: tables.performance, tableIncludesIdle: false)
                } else if name.hasPrefix("PCPU"), !tables.superCores.isEmpty {
                    superCores.add(residencies: residencies, table: tables.superCores, tableIncludesIdle: false)
                } else if name.contains("CPU") {
                    performance.add(residencies: residencies, table: tables.performance, tableIncludesIdle: false)
                }
            } else if groupName == "GPU Stats", name.hasPrefix("GPUPH") {
                graphics.add(residencies: residencies, table: tables.graphics, tableIncludesIdle: tables.graphics.first == 0)
            }
        }
        stats.efficiencyFrequencyMHz = efficiency.averageMHz
        stats.performanceFrequencyMHz = performance.averageMHz
        stats.superFrequencyMHz = superCores.averageMHz
        stats.gpuFrequencyMHz = graphics.averageMHz
        stats.cpuFrequencyMHz = (efficiency + performance + superCores).averageMHz
        return stats
    }

    private static func joules(perUnit label: String) -> Double {
        switch label.trimmingCharacters(in: .whitespaces) {
        case "mJ": 1e-3
        case "uJ", "µJ": 1e-6
        case "nJ": 1e-9
        default: 0
        }
    }
}

/// Residency-weighted average over the active DVFS states of one or more channels.
struct FrequencyAccumulator {
    private var weighted = 0.0
    private var active = 0.0

    /// State 0 of a channel is always idle/off. A table either starts at that
    /// state (a leading 0 MHz entry) or at the first active one, and states past
    /// the end of the table clamp to the last entry, because some chips publish
    /// more states than they have frequencies.
    mutating func add(residencies: [Double], table: [Double], tableIncludesIdle: Bool) {
        guard !table.isEmpty, residencies.count > 1 else { return }
        for state in 1..<residencies.count {
            let index = tableIncludesIdle ? state : state - 1
            weighted += residencies[state] * table[min(index, table.count - 1)]
            active += residencies[state]
        }
    }

    static func + (lhs: Self, rhs: Self) -> Self {
        var sum = lhs
        sum.weighted += rhs.weighted
        sum.active += rhs.active
        return sum
    }

    var averageMHz: Double? { active > 0 ? weighted / active : nil }
}

/// The frequency tables behind the residency states, stored in the `pmgr` node.
struct DVFSTables {
    var efficiency: [Double] = []
    var performance: [Double] = []
    var superCores: [Double] = []
    var graphics: [Double] = []

    static func read() -> DVFSTables {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceNameMatching("pmgr"), &iterator) == KERN_SUCCESS else {
            return DVFSTables()
        }
        defer { IOObjectRelease(iterator) }

        var tables = DVFSTables()
        let clusterKinds = CPUReader.readClusterKinds()
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            func table(_ key: String) -> [Double] {
                guard let data = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? Data else { return [] }
                return megahertz(fromVoltageStates: data)
            }
            let clusters = IORegistryEntryCreateCFProperty(entry, "acc-clusters" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Data ?? Data()
            let keys = cpuTableKeys(accClusters: clusters, clusterKinds: clusterKinds)
            let hasSuper = clusterKinds.values.contains(.superCore)
            if hasSuper {
                if tables.superCores.isEmpty { tables.superCores = table(keys[.superCore] ?? "voltage-states5-sram") }
                if tables.performance.isEmpty, let key = keys[.performance] { tables.performance = table(key) }
            } else if tables.performance.isEmpty {
                tables.performance = table(keys[.performance] ?? "voltage-states5-sram")
            }
            if tables.efficiency.isEmpty { tables.efficiency = table(keys[.efficiency] ?? "voltage-states1-sram") }
            if tables.graphics.isEmpty { tables.graphics = table("voltage-states9") }
        }
        return tables
    }

    /// Each 8-byte record maps a voltage domain to a logical CPU cluster.
    static func cpuTableKeys(accClusters: Data, clusterKinds: [Int: CoreKind]) -> [CoreKind: String] {
        let bytes = Array(accClusters)
        var keys: [CoreKind: String] = [:]
        guard bytes.count >= 8 else { return keys }
        for offset in stride(from: 0, through: bytes.count - 8, by: 8) {
            guard let kind = clusterKinds[Int(bytes[offset + 1])], kind != .unknown else { continue }
            if keys[kind] == nil { keys[kind] = "voltage-states\(bytes[offset])-sram" }
        }
        return keys
    }

    /// Each entry is a little-endian `(frequency: UInt32, voltage: UInt32)`.
    /// M1–M3 store Hz and later chips store kHz; no real clock is below 100 MHz,
    /// so the largest value tells the two apart.
    static func megahertz(fromVoltageStates data: Data) -> [Double] {
        let bytes = [UInt8](data)
        guard bytes.count >= 8 else { return [] }
        let raw = stride(from: 0, to: bytes.count - 7, by: 8).map { offset -> Double in
            var value: UInt32 = 0
            for byte in 0..<4 { value |= UInt32(bytes[offset + byte]) << UInt32(byte * 8) }
            return Double(value)
        }
        let divisor = (raw.max() ?? 0) >= 100_000_000 ? 1_000_000.0 : 1_000.0
        return raw.map { $0 / divisor }
    }
}
