import Darwin
import Foundation
import IOKit
import IOKit.ps
import SystemConfiguration

enum SystemControl {
    static func int(_ name: String) -> Int? {
        var value = 0
        var size = MemoryLayout<Int>.size
        // Some keys are 32-bit: the zeroed upper half keeps the value correct on little-endian.
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
    }

    static func uptime(now: Date = Date()) -> TimeInterval {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctlbyname("kern.boottime", &bootTime, &size, nil, 0) == 0 else { return 0 }
        return now.timeIntervalSince1970 - TimeInterval(bootTime.tv_sec)
    }

    static func loadAverage() -> [Double] {
        var values = [Double](repeating: 0, count: 3)
        return getloadavg(&values, 3) == 3 ? values : [0, 0, 0]
    }
}

// MARK: - CPU

final class CPUReader {
    private struct Ticks {
        var user: UInt32
        var system: UInt32
        var idle: UInt32
        var nice: UInt32
    }

    private let host = mach_host_self()
    private var previous: [Ticks] = []
    private lazy var kinds: [Int: CoreKind] = Self.readCoreKinds()

    func read() -> CPUStats {
        var coreCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &coreCount, &info, &infoCount) == KERN_SUCCESS,
              let info else {
            return CPUStats()
        }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        let stride = Int(CPU_STATE_MAX)
        let current = (0..<Int(coreCount)).map { core -> Ticks in
            let offset = stride * core
            return Ticks(
                user: UInt32(bitPattern: info[offset + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: info[offset + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: info[offset + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: info[offset + Int(CPU_STATE_NICE)])
            )
        }
        defer { previous = current }
        guard previous.count == current.count else { return CPUStats() }

        var stats = CPUStats()
        for (index, (now, before)) in zip(current, previous).enumerated() {
            // Tick counters are 32-bit and wrap, so the deltas subtract with wrap-around.
            let user = Double(now.user &- before.user) + Double(now.nice &- before.nice)
            let system = Double(now.system &- before.system)
            let idle = Double(now.idle &- before.idle)
            let total = user + system + idle
            stats.cores.append(CoreLoad(
                id: index,
                kind: kinds[index] ?? .performance,
                user: total > 0 ? user / total : 0,
                system: total > 0 ? system / total : 0
            ))
        }
        // The rings list efficiency cores first whatever order the kernel uses.
        stats.cores.sort { lhs, rhs in
            lhs.kind == rhs.kind ? lhs.id < rhs.id : lhs.kind == .efficiency
        }
        let count = Double(max(1, stats.cores.count))
        stats.user = stats.cores.map(\.user).reduce(0, +) / count
        stats.system = stats.cores.map(\.system).reduce(0, +) / count
        return stats
    }

    /// `cluster-type` in the device tree is "E" or "P" per logical CPU. Newer
    /// chips add other letters, all of which count as performance here.
    private static func readCoreKinds() -> [Int: CoreKind] {
        var kinds: [Int: CoreKind] = [:]
        let count = SystemControl.int("hw.logicalcpu") ?? 0
        for index in 0..<count {
            let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus/cpu\(index)")
            guard entry != 0 else { continue }
            defer { IOObjectRelease(entry) }
            if let data = IORegistryEntryCreateCFProperty(entry, "cluster-type" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Data, let first = data.first {
                kinds[index] = first == UInt8(ascii: "E") ? .efficiency : .performance
            }
        }
        if kinds.isEmpty, let efficiency = SystemControl.int("hw.perflevel1.logicalcpu") {
            for index in 0..<count { kinds[index] = index < efficiency ? .efficiency : .performance }
        }
        return kinds
    }
}

// MARK: - GPU

struct GPUReader {
    func read() -> GPUStats {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return GPUStats()
        }
        defer { IOObjectRelease(iterator) }

        var stats = GPUStats()
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let values = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] else { continue }
            func percent(_ key: String) -> Double { Double(values[key] as? Int ?? 0) / 100 }
            stats.utilization = max(stats.utilization, percent("Device Utilization %"))
            stats.renderer = max(stats.renderer, percent("Renderer Utilization %"))
            stats.tiler = max(stats.tiler, percent("Tiler Utilization %"))
            stats.memoryInUse = max(stats.memoryInUse, UInt64(values["In use system memory"] as? Int ?? 0))
        }
        return stats
    }
}

// MARK: - Memory

final class MemoryReader {
    private let host = mach_host_self()
    private let pageSize = UInt64(vm_kernel_page_size)
    private let total = UInt64(ProcessInfo.processInfo.physicalMemory)
    private var previousPaging: (pageIns: UInt64, pageOuts: UInt64, at: Date)?

    func read() -> MemoryStats {
        var stats = MemoryStats()
        stats.total = total

        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            // Same split as Activity Monitor: purgeable and file-backed pages are cache.
            let page = pageSize
            let internalPages = UInt64(info.internal_page_count)
            let purgeable = UInt64(info.purgeable_count)
            stats.app = (internalPages > purgeable ? internalPages - purgeable : 0) * page
            stats.wired = UInt64(info.wire_count) * page
            stats.compressed = UInt64(info.compressor_page_count) * page
            stats.cached = (UInt64(info.external_page_count) + purgeable) * page
            stats.free = UInt64(info.free_count) * page

            let now = Date()
            let pageIns = UInt64(info.pageins)
            let pageOuts = UInt64(info.pageouts)
            if let previous = previousPaging, now > previous.at {
                let elapsed = now.timeIntervalSince(previous.at)
                stats.pageInBytesPerSecond = Double(pageIns &- previous.pageIns) * Double(page) / elapsed
                stats.pageOutBytesPerSecond = Double(pageOuts &- previous.pageOuts) * Double(page) / elapsed
            }
            previousPaging = (pageIns, pageOuts, now)
        }

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.stride
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            stats.swapTotal = swap.xsu_total
            stats.swapUsed = swap.xsu_used
        }
        if let level = SystemControl.int("kern.memorystatus_level") {
            stats.pressure = Double(max(0, min(100, 100 - level))) / 100
        }
        if let level = SystemControl.int("kern.memorystatus_vm_pressure_level") {
            stats.pressureLevel = level
        }
        return stats
    }
}

// MARK: - Disk

final class DiskReader {
    private var previous: (read: UInt64, write: UInt64, at: Date)?

    func volumes() -> [VolumeStats] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeLocalizedNameKey, .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey, .volumeIsBrowsableKey
        ]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url -> VolumeStats? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let total = values.volumeTotalCapacity, total > 0, values.volumeIsBrowsable != false else {
                return nil
            }
            let important = values.volumeAvailableCapacityForImportantUsage.map { UInt64(max(0, $0)) }
            let available = important ?? UInt64(max(0, values.volumeAvailableCapacity ?? 0))
            return VolumeStats(
                path: url.path,
                name: values.volumeLocalizedName ?? values.volumeName ?? url.lastPathComponent,
                total: UInt64(total),
                available: available,
                isRoot: url.path == "/"
            )
        }
        .sorted { $0.isRoot && !$1.isRoot }
    }

    func activity(now: Date = Date()) -> (read: Double, write: Double, totalRead: UInt64, totalWrite: UInt64) {
        let current = Self.readCounters()
        defer { previous = (current.read, current.write, now) }
        guard let previous else { return (0, 0, current.read, current.write) }
        let elapsed = now.timeIntervalSince(previous.at)
        guard elapsed > 0 else { return (0, 0, current.read, current.write) }
        return (
            Double(current.read >= previous.read ? current.read - previous.read : 0) / elapsed,
            Double(current.write >= previous.write ? current.write - previous.write : 0) / elapsed,
            current.read,
            current.write
        )
    }

    private static func readCounters() -> (read: UInt64, write: UInt64) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else {
            return (0, 0)
        }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0
        var write: UInt64 = 0
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let statistics = IORegistryEntryCreateCFProperty(entry, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] else { continue }
            read &+= UInt64(statistics["Bytes (Read)"] as? Int ?? 0)
            write &+= UInt64(statistics["Bytes (Write)"] as? Int ?? 0)
        }
        return (read, write)
    }
}

// MARK: - Network

final class NetworkReader {
    private var previous: [String: (input: UInt32, output: UInt32)] = [:]
    private var previousTime: Date?
    private var uploaded: UInt64 = 0
    private var downloaded: UInt64 = 0

    func read(now: Date = Date()) -> NetworkStats {
        var stats = NetworkStats()
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return stats }
        defer { freeifaddrs(head) }

        let primary = Self.primaryRoute()
        stats.router = primary.router

        var counters: [String: (input: UInt32, output: UInt32)] = [:]
        var interfaces: [String: InterfaceStats] = [:]
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            let name = String(cString: current.pointee.ifa_name)
            let flags = Int32(current.pointee.ifa_flags)
            guard Self.isUserFacing(name), flags & IFF_UP != 0, flags & IFF_RUNNING != 0,
                  let address = current.pointee.ifa_addr else { continue }

            switch Int32(address.pointee.sa_family) {
            case AF_LINK:
                if let data = current.pointee.ifa_data?.assumingMemoryBound(to: if_data.self).pointee {
                    counters[name] = (data.ifi_ibytes, data.ifi_obytes)
                }
            case AF_INET:
                if let text = Self.numericHost(address) {
                    interfaces[name, default: InterfaceStats(name: name)].ipv4 = text
                }
            case AF_INET6:
                if let text = Self.numericHost(address), !text.hasPrefix("fe80") {
                    interfaces[name, default: InterfaceStats(name: name)].ipv6 = text
                }
            default:
                break
            }
        }

        var inputDelta: UInt64 = 0
        var outputDelta: UInt64 = 0
        for (name, value) in counters {
            guard let before = previous[name] else { continue }
            // `if_data` counters are 32-bit, so a wrapped subtraction stays right
            // as long as less than 4 GiB moves between two samples.
            inputDelta += UInt64(value.input &- before.input)
            outputDelta += UInt64(value.output &- before.output)
        }
        if let previousTime {
            let elapsed = now.timeIntervalSince(previousTime)
            if elapsed > 0 {
                stats.downloadBytesPerSecond = Double(inputDelta) / elapsed
                stats.uploadBytesPerSecond = Double(outputDelta) / elapsed
            }
            downloaded += inputDelta
            uploaded += outputDelta
        }
        previous = counters
        previousTime = now
        stats.uploadedSinceLaunch = uploaded
        stats.downloadedSinceLaunch = downloaded

        if let name = primary.interface { interfaces[name]?.isPrimary = true }
        stats.interfaces = interfaces.values
            .filter { $0.ipv4 != nil || $0.ipv6 != nil }
            .sorted { $0.isPrimary != $1.isPrimary ? $0.isPrimary : $0.name < $1.name }
        return stats
    }

    /// Only real links count: `utun` would double every byte on a VPN, and
    /// `awdl`/`llw`/`anpi` are internal plumbing the user never chose.
    static func isUserFacing(_ name: String) -> Bool {
        name.hasPrefix("en") && !name.hasPrefix("enc")
    }

    private static func numericHost(_ address: UnsafeMutablePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else {
            return nil
        }
        return String(cString: host)
    }

    private static func primaryRoute() -> (interface: String?, router: String?) {
        guard let store = SCDynamicStoreCreate(nil, "StatusDeck" as CFString, nil, nil),
              let value = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] else {
            return (nil, nil)
        }
        return (value["PrimaryInterface"] as? String, value["Router"] as? String)
    }
}

// MARK: - Battery

struct BatteryReader {
    func read() -> BatteryStats {
        var stats = BatteryStats()
        stats.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return stats }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let registry = properties?.takeRetainedValue() as? [String: Any] else {
            return stats
        }
        return Self.parse(registry: registry, into: stats,
                          adapter: IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any],
                          powerSource: Self.internalPowerSource())
    }

    private static func internalPowerSource() -> [String: Any]? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        return sources.lazy.compactMap { IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any] }
            .first { $0[kIOPSTypeKey] as? String == kIOPSInternalBatteryType }
    }

    static func parse(registry: [String: Any], into base: BatteryStats, adapter: [String: Any]?,
                      powerSource: [String: Any]? = nil) -> BatteryStats {
        var stats = base
        let data = registry["BatteryData"] as? [String: Any] ?? [:]
        func number(_ key: String, valid: (Int) -> Bool = { _ in true }) -> Int? {
            [registry[key], data[key]].lazy.compactMap { ($0 as? NSNumber)?.intValue }.first(where: valid)
        }
        stats.isPresent = true
        stats.percent = registry["CurrentCapacity"] as? Int ?? 0
        stats.isCharging = registry["IsCharging"] as? Bool ?? false
        stats.isFullyCharged = registry["FullyCharged"] as? Bool ?? false
        stats.isExternalPowerConnected = registry["ExternalConnected"] as? Bool ?? false
        stats.cycleCount = number("CycleCount")
        stats.designCapacity = number("DesignCapacity") { $0 > 1 }
        stats.fullChargeCapacity = number("NominalChargeCapacity") { $0 > 1 }
            ?? number("AppleRawMaxCapacity") { $0 > 1 }
        stats.healthCondition = (powerSource?[kIOPSBatteryHealthConditionKey] as? String)
            ?? (powerSource?[kIOPSBatteryHealthKey] as? String)
        let cellMillivolts = (data["CellVoltage"] as? [Int]) ?? (registry["CellVoltage"] as? [Int]) ?? []
        stats.cellVolts = cellMillivolts.map { $0 > 0 && $0 < 6_000 ? Double($0) / 1_000 : nil }

        // 65535 is the registry's "still calculating" marker.
        if let minutes = registry["TimeRemaining"] as? Int, minutes > 0, minutes < 65535 {
            stats.minutesRemaining = minutes
        }
        if let design = stats.designCapacity, let full = stats.fullChargeCapacity {
            stats.health = min(1, Double(full) / Double(design))
        }
        if let temperature = number("Temperature"), temperature > 0 {
            stats.temperatureCelsius = Double(temperature) / 100
        }
        if let voltage = number("Voltage"), voltage > 0 {
            stats.volts = Double(voltage) / 1000
        }
        if let amperage = number("InstantAmperage") ?? number("Amperage") {
            stats.amps = Double(amperage) / 1000
        }
        stats.adapterWatts = (adapter?["Watts"] as? Int) ?? ((registry["AdapterDetails"] as? [String: Any])?["Watts"] as? Int)
        return stats
    }
}
