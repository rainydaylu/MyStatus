import StatusDeckKit
import SwiftUI

/// The tools at the bottom of a detail window, for looking further.
private enum UtilityApps {
    private static let folder = "/System/Applications/Utilities"
    static let activityMonitor = "\(folder)/Activity Monitor.app"
    static let console = "\(folder)/Console.app"
    static let terminal = "\(folder)/Terminal.app"
    static let diskUtility = "\(folder)/Disk Utility.app"
    static let systemInformation = "\(folder)/System Information.app"
    static let all = [activityMonitor, console, terminal, diskUtility, systemInformation]
}

/// A heading and the most demanding processes under it, each with its app's icon.
private struct ProcessBlock: View {
    let entries: [ProcessEntry]
    let value: (ProcessEntry) -> String
    @Environment(\.deckTheme) private var theme

    var body: some View {
        DeckCard {
            VStack(alignment: .leading, spacing: 6) {
                DeckTitle(DeckL("进程"))
                if entries.isEmpty {
                    Text(DeckL("读取中…")).font(.system(size: 13)).foregroundStyle(theme.secondary)
                }
                ForEach(entries) { entry in
                    HStack(spacing: 7) {
                        Image(nsImage: DeckAppIcon.image(forPath: entry.bundlePath))
                            .resizable()
                            .frame(width: 18, height: 18)
                        Text(entry.name)
                            .font(.system(size: 13))
                            .foregroundStyle(theme.primary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(value(entry))
                            .font(.system(size: 13))
                            .monospacedDigit()
                            .foregroundStyle(theme.primary)
                    }
                }
            }
        }
    }
}

// MARK: - CPU and GPU

final class CPUPlugin: BuiltInPlugin {
    init(services: SharedServices) {
        super.init(manifest: PluginManifest(
            id: "com.statusdeck.cpu",
            name: "CPU 与 GPU",
            summary: "处理器占用、每核负载、频率、功耗和占用最高的应用。",
            symbol: "cpu",
            category: .monitor,
            sortOrder: 300
        ), services: services)
    }

    override func didActivate() {
        // Sampled all the time, so that the graph has its history the moment the panel opens.
        services.store.sampler.setInterest(owner: manifest.id, always: [.cpu], whilePanelVisible: [.gpu, .soc, .sensors, .system])
    }

    override func willDeactivate() {
        services.store.sampler.removeInterest(owner: manifest.id)
        services.store.sampler.removeInterest(owner: "\(manifest.id).processes")
    }

    override var sections: [DeckSection] {
        let store = services.store
        let owner = "\(manifest.id).processes"
        return [DeckSection(id: "cpu", title: "CPU") {
            CPURow(store: store)
        } detail: {
            CPUDetail(store: store) { [weak self] in self?.host?.closePanel() }
                // Listing processes launches `ps`, so it only runs with the list in view.
                .onAppear { store.sampler.setInterest(owner: owner, whilePanelVisible: [.processes]) }
                .onDisappear { store.sampler.removeInterest(owner: owner) }
        }]
    }
}

private func frequencyAndTemperature(_ megahertz: Double?, _ celsius: Double?) -> String {
    "\(Format.gigahertz(megahertz)), \(Format.degrees(celsius))"
}

private struct CoreRings: View {
    let cores: [CoreLoad]
    @Environment(\.deckTheme) private var theme

    var body: some View {
        // Ten fit on a line. Machines with more cores simply wrap.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 22, maximum: 30), spacing: 3)], spacing: 5) {
            ForEach(cores) { core in
                DeckRing(value: core.total, color: core.kind.color(in: theme), lineWidth: 3.5)
                    .frame(width: 22, height: 22)
                    .help("\(core.kind.title) \(core.id + 1) · \(Format.percent(core.total))")
            }
        }
    }
}

private extension CoreKind {
    func color(in theme: DeckTheme) -> Color {
        switch self {
        case .efficiency: theme.magenta
        case .performance: theme.accent
        case .superCore: .orange
        case .unknown: theme.secondary
        }
    }
}

private struct CoreLegends: View {
    let cpu: CPUStats
    var soc: SoCStats? = nil
    @Environment(\.deckTheme) private var theme

    var body: some View {
        VStack(spacing: 3) {
            ForEach(cpu.coreKinds, id: \.self) { kind in
                let count = cpu.cores(of: kind).count
                let load = Format.percent(cpu.average(of: kind))
                DeckLegendDot("\(kind.title) × \(count)",
                              soc.map { "\(load) · \(Format.gigahertz($0.frequency(for: kind)))" } ?? load,
                              color: kind.color(in: theme))
            }
        }
    }
}

private struct CPURow: View {
    @ObservedObject var store: SystemStore
    @Environment(\.deckTheme) private var theme

    var body: some View {
        let snapshot = store.snapshot
        let cpu = snapshot.cpu
        VStack(alignment: .leading, spacing: 7) {
            DeckTitleRow("CPU", value: frequencyAndTemperature(snapshot.soc.cpuFrequencyMHz, snapshot.sensors.average(.cpu)))
            DeckBarGraph(lower: store.history.cpuUser, upper: store.history.cpuSystem, capacity: History.capacity)
                .frame(height: 56)
            HStack(spacing: 18) {
                DeckLegendDot(DeckL("用户"), Format.percent(cpu.user), color: theme.accent)
                DeckLegendDot(DeckL("系统"), Format.percent(cpu.system), color: theme.magenta)
            }
            CoreRings(cores: cpu.cores)
                .padding(.top, 3)
            CoreLegends(cpu: cpu)
        }
    }
}

private struct CPUDetail: View {
    @ObservedObject var store: SystemStore
    let onOpenApp: () -> Void
    @Environment(\.deckTheme) private var theme

    var body: some View {
        let snapshot = store.snapshot
        let cpu = snapshot.cpu
        VStack(spacing: DeckTheme.cardSpacing) {
            DeckCard {
                VStack(alignment: .leading, spacing: 7) {
                    DeckTitleRow("CPU", value: frequencyAndTemperature(snapshot.soc.cpuFrequencyMHz, snapshot.sensors.average(.cpu)))
                    DeckBarGraph(lower: store.history.cpuUser, upper: store.history.cpuSystem, capacity: History.capacity)
                        .frame(height: 70)
                    VStack(spacing: 3) {
                        DeckLegendDot(DeckL("用户"), Format.percent(cpu.user), color: theme.accent)
                        DeckLegendDot(DeckL("系统"), Format.percent(cpu.system), color: theme.magenta)
                        DeckLegendDot(DeckL("闲置"), Format.percent(1 - cpu.total), color: theme.track)
                    }
                }
            }
            DeckCard {
                VStack(alignment: .leading, spacing: 7) {
                    CoreRings(cores: cpu.cores)
                    CoreLegends(cpu: cpu, soc: snapshot.soc)
                    DeckInfoRow(DeckL("功耗"), Format.watts(snapshot.soc.cpuWatts))
                }
            }
            DeckCard {
                VStack(alignment: .leading, spacing: 7) {
                    DeckTitleRow("GPU", value: frequencyAndTemperature(snapshot.soc.gpuFrequencyMHz, snapshot.sensors.average(.gpu)))
                    DeckBarGraph(lower: store.history.gpu, capacity: History.capacity)
                        .frame(height: 36)
                    VStack(spacing: 3) {
                        DeckLegendDot(DeckL("占用"), Format.percent(snapshot.gpu.utilization), color: theme.accent)
                        DeckInfoRow(DeckL("显存"), Format.bytes(snapshot.gpu.memoryInUse, binary: true))
                        DeckInfoRow(DeckL("功耗"), Format.watts(snapshot.soc.gpuWatts))
                    }
                }
            }
            ProcessBlock(entries: snapshot.processes.byCPU) { String(format: "%.1f%%", $0.cpu * 100) }
            DeckCard {
                VStack(spacing: 3) {
                    DeckInfoRow(DeckL("平均负载"), snapshot.loadAverage.map { String(format: "%.2f", $0) }.joined(separator: "  "))
                    DeckInfoRow(DeckL("运行时间"), Format.duration(snapshot.uptime))
                }
            }
            DeckCard {
                DeckAppShortcutRow(paths: UtilityApps.all, onOpen: onOpenApp)
            }
        }
    }
}

// MARK: - Memory

final class MemoryPlugin: BuiltInPlugin {
    init(services: SharedServices) {
        super.init(manifest: PluginManifest(
            id: "com.statusdeck.memory",
            name: "内存",
            summary: "内存压力、用量明细、分页、交换空间和占用最多的应用。",
            symbol: "memorychip",
            category: .monitor,
            sortOrder: 310
        ), services: services)
    }

    override func didActivate() {
        services.store.sampler.setInterest(owner: manifest.id, always: [.memory])
    }

    override func willDeactivate() {
        services.store.sampler.removeInterest(owner: manifest.id)
        services.store.sampler.removeInterest(owner: "\(manifest.id).processes")
    }

    override var sections: [DeckSection] {
        let store = services.store
        let owner = "\(manifest.id).processes"
        return [DeckSection(id: "memory", title: DeckL("内存")) {
            MemoryRow(store: store)
        } detail: {
            MemoryDetail(store: store) { [weak self] in self?.host?.closePanel() }
                .onAppear { store.sampler.setInterest(owner: owner, whilePanelVisible: [.processes]) }
                .onDisappear { store.sampler.removeInterest(owner: owner) }
        }]
    }
}

private struct MemoryRings: View {
    let memory: MemoryStats
    var drilldowns: SystemStore? = nil
    @Environment(\.deckTheme) private var theme

    var body: some View {
        let total = Double(max(1, memory.total))
        HStack(spacing: 0) {
            ringLink(isPressure: true) {
                DeckRing(value: memory.pressure, color: pressureColor) {
                    DeckRingPercent(memory.pressure, caption: DeckL("压力"))
                }
                .frame(width: 108, height: 108)
                .frame(maxWidth: .infinity)
            }
            ringLink(isPressure: false) {
                DeckRing(segments: [
                    (Double(memory.app) / total, theme.accent),
                    (Double(memory.wired) / total, theme.magenta),
                    (Double(memory.compressed) / total, theme.amber)
                ]) {
                    DeckRingPercent(memory.usedFraction, caption: DeckL("内存"))
                }
                .frame(width: 108, height: 108)
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func ringLink<Ring: View>(isPressure: Bool, @ViewBuilder ring: @escaping () -> Ring) -> some View {
        if let drilldowns {
            PanelDrilldownLink(id: isPressure ? "memory.pressure" : "memory.usage",
                               title: isPressure ? DeckL("内存压力", "Memory pressure") : DeckL("内存构成", "Memory breakdown")) {
                ring()
            } detail: {
                MemoryHistoryView(store: drilldowns, isPressure: isPressure)
            }
        } else {
            ring()
        }
    }

    private var pressureColor: Color {
        switch memory.pressureLevel {
        case 4: theme.negative
        case 2: theme.warning
        default: theme.accent
        }
    }
}

private struct MemoryRow: View {
    @ObservedObject var store: SystemStore

    var body: some View {
        MemoryRings(memory: store.snapshot.memory)
    }
}

private struct MemoryDetail: View {
    @ObservedObject var store: SystemStore
    let onOpenApp: () -> Void
    @Environment(\.deckTheme) private var theme

    var body: some View {
        let memory = store.snapshot.memory
        let swapFraction = memory.swapTotal == 0 ? 0 : Double(memory.swapUsed) / Double(memory.swapTotal)
        VStack(spacing: DeckTheme.cardSpacing) {
            DeckCard { MemoryRings(memory: memory, drilldowns: store) }
            DeckCard {
                PanelDrilldownLink(id: "memory.breakdown", title: DeckL("内存构成", "Memory breakdown")) {
                    VStack(spacing: 3) {
                        DeckLegendDot(DeckL("App 内存"), Format.bytes(memory.app, binary: true), color: theme.accent)
                        DeckLegendDot(DeckL("联动内存"), Format.bytes(memory.wired, binary: true), color: theme.magenta)
                        DeckLegendDot(DeckL("已压缩"), Format.bytes(memory.compressed, binary: true), color: theme.amber)
                        DeckLegendDot(DeckL("可用"), Format.bytes(memory.available, binary: true), color: theme.track)
                    }
                } detail: {
                    MemoryHistoryView(store: store, isPressure: false)
                }
            }
            ProcessBlock(entries: store.snapshot.processes.byMemory) { Format.bytes($0.memory, binary: true) }
            DeckCard {
                VStack(spacing: 3) {
                    DeckInfoRow(DeckL("写入分页"), Format.speed(memory.pageOutBytesPerSecond))
                    DeckInfoRow(DeckL("读取分页"), Format.speed(memory.pageInBytesPerSecond))
                }
            }
            DeckCard {
                VStack(spacing: 6) {
                    DeckTitleRow(DeckL("已使用的交换"), value: "\(Format.bytes(memory.swapUsed, binary: true)) / \(Format.bytes(memory.swapTotal, binary: true))")
                    DeckBar(value: swapFraction, height: 8)
                }
            }
            DeckCard {
                DeckAppShortcutRow(paths: UtilityApps.all, onOpen: onOpenApp)
            }
        }
    }
}

// MARK: - Disk

final class DiskPlugin: BuiltInPlugin {
    init(services: SharedServices) {
        super.init(manifest: PluginManifest(
            id: "com.statusdeck.disk",
            name: "磁盘",
            summary: "各卷可用空间和实时读写速度。",
            symbol: "internaldrive",
            category: .monitor,
            sortOrder: 320
        ), services: services)
    }

    override func didActivate() {
        services.store.sampler.setInterest(owner: manifest.id, always: [.disk])
    }

    override func willDeactivate() {
        services.store.sampler.removeInterest(owner: manifest.id)
    }

    override var sections: [DeckSection] {
        let store = services.store
        return [DeckSection(id: "disk", title: DeckL("磁盘")) {
            DiskRow(store: store)
        } detail: {
            DiskDetail(store: store) { [weak self] in self?.host?.closePanel() }
        }]
    }
}

private struct VolumeLine: View {
    let volume: VolumeStats
    @Environment(\.deckTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            DeckRing(value: volume.usedFraction, color: theme.accent, lineWidth: 3.5) {
                Text("\(Int((volume.usedFraction * 100).rounded()))")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(theme.primary)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(volume.name)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondary)
                    .lineLimit(1)
                Text(DeckLF("%@可用", "%@ available", Format.bytes(volume.available)))
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(theme.primary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
        }
    }
}

private struct DiskRow: View {
    @ObservedObject var store: SystemStore
    @Environment(\.deckTheme) private var theme

    var body: some View {
        let disk = store.snapshot.disk
        HStack(spacing: 6) {
            if let root = disk.root {
                VolumeLine(volume: root)
            } else {
                DeckTitle(DeckL("磁盘"))
                Spacer()
            }
            // Lights up while something is being read or written.
            VStack(spacing: 10) {
                Circle()
                    .fill(disk.readBytesPerSecond > 1000 ? theme.magenta : theme.track)
                    .frame(width: 9, height: 9)
                Circle()
                    .fill(disk.writeBytesPerSecond > 1000 ? theme.accent : theme.track)
                    .frame(width: 9, height: 9)
            }
        }
    }
}

private struct DiskDetail: View {
    @ObservedObject var store: SystemStore
    let onOpenApp: () -> Void
    @Environment(\.deckTheme) private var theme

    var body: some View {
        let disk = store.snapshot.disk
        VStack(spacing: DeckTheme.cardSpacing) {
            ForEach(disk.volumes) { volume in
                DeckCard {
                    VStack(alignment: .leading, spacing: 7) {
                        VolumeLine(volume: volume)
                        DeckInfoRow(DeckL("总容量"), Format.bytes(volume.total))
                        DeckInfoRow(DeckL("已用空间", "Used space"), Format.bytes(volume.total - min(volume.total, volume.available)))
                        DeckBar(value: volume.usedFraction)
                    }
                }
            }
            PanelDrilldownLink(id: "disk.history", title: DeckL("磁盘活动", "Disk activity")) {
                DiskActivity(store: store, expanded: false)
            } detail: {
                DiskActivity(store: store, expanded: true)
            }
            DeckCard {
                VStack(alignment: .leading, spacing: 4) {
                    DeckInfoRow(DeckL("累计读取", "Total read"), Format.bytes(disk.totalReadBytes))
                    DeckInfoRow(DeckL("累计写入", "Total written"), Format.bytes(disk.totalWrittenBytes))
                }
            }
            ProcessTransferBlock(monitor: store.processTransfers, source: .disk,
                                 firstLabel: DeckL("读取"), secondLabel: DeckL("写入"))
            DeckCard {
                DeckAppShortcutRow(paths: [UtilityApps.diskUtility, UtilityApps.activityMonitor], onOpen: onOpenApp)
            }
        }
    }
}

private struct DiskActivity: View {
    @ObservedObject var store: SystemStore
    let expanded: Bool

    var body: some View {
        let disk = store.snapshot.disk
        TransferActivityCard(title: DeckL("磁盘活动", "Disk activity"), firstLabel: DeckL("读取"),
                             secondLabel: DeckL("写入"), first: disk.readBytesPerSecond,
                             second: disk.writeBytesPerSecond, history: store.history.diskActivity,
                             floor: 1_000_000, expanded: expanded)
    }
}

// MARK: - Network

final class NetworkPlugin: BuiltInPlugin {
    init(services: SharedServices) {
        super.init(manifest: PluginManifest(
            id: "com.statusdeck.network",
            name: "网络",
            summary: "上传和下载速度、累计流量、网络接口。",
            symbol: "arrow.up.arrow.down",
            category: .monitor,
            sortOrder: 330
        ), services: services)
    }

    override func didActivate() {
        services.store.sampler.setInterest(owner: manifest.id, always: [.network])
    }

    override func willDeactivate() {
        services.store.sampler.removeInterest(owner: manifest.id)
        services.wifi.poller.set(owner: manifest.id, interval: nil)
    }

    override func panelVisibilityChanged(_ isVisible: Bool) {
        services.wifi.poller.set(owner: manifest.id, interval: isVisible ? 5 : nil)
    }

    override var sections: [DeckSection] {
        let store = services.store
        let wifi = services.wifi
        return [DeckSection(id: "network", title: DeckL("网络")) {
            NetworkRow(store: store)
        } detail: {
            NetworkDetail(store: store, wifi: wifi) { [weak self] in self?.host?.closePanel() }
        }]
    }
}

private struct NetworkGraph: View {
    @ObservedObject var store: SystemStore
    let height: CGFloat
    @Environment(\.deckTheme) private var theme

    var body: some View {
        let network = store.snapshot.network
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                DeckStat(Format.speed(network.uploadBytesPerSecond), label: DeckL("上传"), color: theme.magenta)
                DeckStat(Format.speed(network.downloadBytesPerSecond), label: DeckL("下载"), color: theme.accent)
            }
            DeckMirrorGraph(upper: store.history.upload, lower: store.history.download, floor: 64_000, capacity: History.capacity)
                .frame(height: height)
        }
    }
}

private struct NetworkRow: View {
    let store: SystemStore

    var body: some View {
        NetworkGraph(store: store, height: 46)
    }
}

private struct NetworkDetail: View {
    @ObservedObject var store: SystemStore
    @ObservedObject var wifi: WiFiController
    let onOpenApp: () -> Void
    @Environment(\.deckTheme) private var theme

    var body: some View {
        let network = store.snapshot.network
        VStack(spacing: DeckTheme.cardSpacing) {
            PanelDrilldownLink(id: "network.history", title: DeckL("网速历史", "Speed history")) {
                NetworkActivity(store: store, expanded: false)
            } detail: {
                NetworkActivity(store: store, expanded: true)
            }
            DeckCard {
                PanelDrilldownLink(id: "network.wifi", title: "Wi-Fi") {
                    HStack(spacing: 8) {
                        Image(systemName: wifi.state.isPoweredOn ? "wifi" : "wifi.slash")
                            .foregroundStyle(theme.accent)
                        Text("Wi-Fi")
                        Spacer(minLength: 6)
                        Text(wifiSubtitle(wifi.state)).foregroundStyle(theme.secondary).lineLimit(1)
                    }
                } detail: {
                    WiFiDetail(wifi: wifi)
                }
            }
            DeckCard {
                VStack(alignment: .leading, spacing: 3) {
                    DeckTitle(DeckL("本次运行累计", "Since launch"))
                    DeckInfoRow(DeckL("已上传"), Format.bytes(network.uploadedSinceLaunch))
                    DeckInfoRow(DeckL("已下载"), Format.bytes(network.downloadedSinceLaunch))
                }
            }
            DeckCard {
                VStack(alignment: .leading, spacing: 3) {
                    DeckTitle(DeckL("网络接口"))
                    ForEach(network.interfaces) { interface in
                        DeckInfoRow(interface.isPrimary ? "\(interface.name)（主要）" : interface.name, interface.ipv4 ?? interface.ipv6 ?? "—")
                    }
                    if let router = network.router {
                        DeckInfoRow(DeckL("路由器"), router)
                    }
                }
            }
            ProcessTransferBlock(monitor: store.processTransfers, source: .network,
                                 firstLabel: DeckL("上传"), secondLabel: DeckL("下载"))
            DeckCard {
                DeckAppShortcutRow(paths: [UtilityApps.activityMonitor, UtilityApps.console, UtilityApps.terminal], onOpen: onOpenApp)
            }
        }
        .onAppear { wifi.refresh() }
    }
}

private struct NetworkActivity: View {
    @ObservedObject var store: SystemStore
    let expanded: Bool

    var body: some View {
        let network = store.snapshot.network
        TransferActivityCard(title: expanded ? DeckL("网速历史", "Speed history") : DeckL("网络活动", "Network activity"),
                             firstLabel: DeckL("上传"), secondLabel: DeckL("下载"),
                             first: network.uploadBytesPerSecond, second: network.downloadBytesPerSecond,
                             history: store.history.networkActivity, floor: 64_000, expanded: expanded)
    }
}

// MARK: - Sensors

final class SensorsPlugin: BuiltInPlugin {
    init(services: SharedServices) {
        super.init(manifest: PluginManifest(
            id: "com.statusdeck.sensors",
            name: "传感器",
            summary: "CPU、GPU、硬盘和电池温度，风扇转速和整机功耗。调节风扇需要一次管理员授权。",
            symbol: "thermometer.medium",
            category: .monitor,
            sortOrder: 340
        ), services: services)
    }

    override func didActivate() {
        services.store.sampler.setInterest(owner: manifest.id, always: [.sensors, .soc, .battery])
    }

    override func willDeactivate() {
        services.store.sampler.removeInterest(owner: manifest.id)
        services.fans.restoreOwnedFans()
    }

    override var sections: [DeckSection] {
        let store = services.store
        let fans = services.fans
        return [DeckSection(id: "sensors", title: DeckL("传感器")) {
            SensorsRow(store: store)
        } detail: {
            SensorsDetail(store: store, fans: fans)
        }]
    }

    override var settingsView: AnyView? {
        AnyView(FanControls(controller: services.fans, detailed: true))
    }
}

private struct SensorRing: View {
    let title: String
    let value: String
    let caption: String?
    let fraction: Double
    @Environment(\.deckTheme) private var theme

    var body: some View {
        DeckRing(value: fraction, color: theme.accent, lineWidth: 3.5) {
            VStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 11))
                Text(value)
                    .font(.system(size: 18))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let caption {
                    Text(caption)
                        .font(.system(size: 10))
                        .foregroundStyle(theme.secondary)
                        .lineLimit(1)
                }
            }
            .monospacedDigit()
            .foregroundStyle(theme.primary)
            .padding(.horizontal, 7)
        }
        .frame(width: 80, height: 80)
        .frame(maxWidth: .infinity)
    }
}

private struct SensorsRow: View {
    @ObservedObject var store: SystemStore

    var body: some View {
        let snapshot = store.snapshot
        let sensors = snapshot.sensors
        let busiestFan = sensors.fans.max { $0.rpm < $1.rpm }
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                DeckTitle(DeckL("传感器"))
                ForEach(sensors.fans) { fan in
                    DeckInfoRow(fan.name, fan.isOff ? DeckL("关") : "\(Int(fan.rpm)) rpm")
                }
                if let volts = snapshot.battery.volts {
                    DeckInfoRow(DeckL("电池"), String(format: "%.1f V", volts))
                }
                DeckInfoRow(DeckL("显卡"), Format.gigahertz(snapshot.soc.gpuFrequencyMHz))
            }
            HStack(spacing: 0) {
                SensorRing(
                    title: "CPU",
                    value: Format.degrees(sensors.average(.cpu)),
                    caption: snapshot.soc.cpuFrequencyMHz.map { String(format: "%.1fGHz", $0 / 1000) },
                    fraction: (sensors.average(.cpu) ?? 0) / 100
                )
                SensorRing(
                    title: "GPU",
                    value: Format.degrees(sensors.average(.gpu)),
                    caption: snapshot.soc.gpuFrequencyMHz.map { String(format: "%.1fGHz", $0 / 1000) },
                    fraction: (sensors.average(.gpu) ?? 0) / 100
                )
                SensorRing(
                    title: DeckL("风扇"),
                    value: busiestFan.map { $0.isOff ? DeckL("关") : "\(Int($0.rpm))" } ?? "--",
                    caption: nil,
                    fraction: busiestFan?.fraction ?? 0
                )
            }
        }
    }
}

private struct SensorsDetail: View {
    @ObservedObject var store: SystemStore
    let fans: FanController
    @State private var showsTemperatures = false
    @Environment(\.deckTheme) private var theme

    var body: some View {
        let snapshot = store.snapshot
        let sensors = snapshot.sensors
        VStack(spacing: DeckTheme.cardSpacing) {
            if !sensors.fans.isEmpty {
                DeckCard { FanControls(controller: fans, detailed: false, readings: sensors.fans, historyStore: store) }
            }
            readings(DeckL("电流", "Current"), current: snapshot.battery, source: \.battery,
                     fields: [("battery.amps", DeckL("电池"), \.amps)], format: { sensorNumber($0, unit: "A") })
            if snapshot.soc != SoCStats() || sensors.systemWatts != nil || snapshot.battery.watts != nil {
                DeckCard {
                    VStack(alignment: .leading, spacing: 3) {
                        DeckTitle(DeckL("功耗"))
                        sensorRows(current: snapshot.soc, source: \.soc, fields: [
                            ("power.cpu", "CPU", \.cpuWatts),
                            ("power.gpu", "GPU", \.gpuWatts),
                            ("power.ane", DeckL("神经引擎"), \.aneWatts),
                            ("power.memory", DeckL("内存"), \.dramWatts)
                        ], format: Format.watts)
                        sensorRows(current: sensors, source: \.sensors,
                                   fields: [("power.system", DeckL("整机"), \.systemWatts)], format: Format.watts)
                        sensorRows(current: snapshot.battery, source: \.battery,
                                   fields: [("power.battery", DeckL("电池"), \.watts)], format: Format.watts)
                    }
                }
            }
            readings(DeckL("电压"), current: snapshot.battery, source: \.battery,
                     fields: [("battery.volts", DeckL("电池"), \.volts)], format: { sensorNumber($0, unit: "V") })
            readings(DeckL("频率", "Frequency"), current: snapshot.soc, source: \.soc, fields: [
                ("frequency.super", DeckL("超级核心", "Super cores"), \.superFrequencyMHz),
                ("frequency.performance", DeckL("性能核心"), \.performanceFrequencyMHz),
                ("frequency.efficiency", DeckL("能效核心"), \.efficiencyFrequencyMHz),
                ("frequency.gpu", "GPU", \.gpuFrequencyMHz)
            ], format: Format.gigahertz)
            DeckCard {
                VStack(alignment: .leading, spacing: 3) {
                    Button { showsTemperatures.toggle() } label: {
                        HStack {
                            DeckTitle(DeckL("温度"))
                            Spacer()
                            Image(systemName: showsTemperatures ? "chevron.up" : "chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(theme.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if showsTemperatures {
                        if sensors.temperatures.isEmpty {
                            DeckInfoRow(DeckL("温度"), "--")
                        }
                        ForEach(sensors.temperatures) { reading in
                            SensorHistoryLink(id: "temperature.\(reading.id)", title: reading.name, current: reading.celsius,
                                              store: store, source: \.sensors,
                                              measure: { $0.temperatures.first { $0.id == reading.id }?.celsius },
                                              format: Format.degrees)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func readings<Value: Equatable>(_ title: String, current: Value, source: KeyPath<History, MonitorHistory<Value>>,
                                           fields: [(String, String, KeyPath<Value, Double?>)], format: @escaping (Double?) -> String) -> some View {
        if fields.contains(where: { current[keyPath: $0.2] != nil }) {
            DeckCard {
                VStack(alignment: .leading, spacing: 3) {
                    DeckTitle(title)
                    sensorRows(current: current, source: source, fields: fields, format: format)
                }
            }
        }
    }

    private func sensorRows<Value: Equatable>(current: Value, source: KeyPath<History, MonitorHistory<Value>>,
                                             fields: [(String, String, KeyPath<Value, Double?>)],
                                             format: @escaping (Double?) -> String) -> some View {
        ForEach(fields, id: \.0) { id, title, path in
            SensorHistoryLink(id: id, title: title, current: current[keyPath: path], store: store,
                              source: source, measure: { $0[keyPath: path] }, format: format)
        }
    }
}

private func sensorNumber(_ value: Double?, unit: String) -> String {
    value.map { String(format: "%.2f %@", locale: DeckLanguage.current.locale, $0, unit) } ?? "—"
}

// MARK: - Battery and power

final class BatteryPlugin: BuiltInPlugin {
    init(services: SharedServices) {
        super.init(manifest: PluginManifest(
            id: "com.statusdeck.battery",
            name: "电池",
            summary: "电量、健康度、循环次数、电量流向和低电量模式。",
            symbol: "battery.75percent",
            category: .monitor,
            sortOrder: 83,
            permissions: ["首次切换低电量模式时，与风扇控制共用一次管理员授权。"]
        ), services: services)
    }

    override func didActivate() {
        services.store.sampler.setInterest(owner: manifest.id, always: [.battery], whilePanelVisible: [.sensors])
    }

    override func willDeactivate() {
        services.store.sampler.removeInterest(owner: manifest.id)
    }

    override var sections: [DeckSection] {
        let store = services.store
        // A Mac without a battery has nothing to show here.
        guard store.snapshot.battery.isPresent || BatteryReader().read().isPresent else { return [] }
        return [DeckSection(id: "battery", title: DeckL("电池")) {
            BatteryRow(store: store, power: services.power)
        } detail: {
            BatteryDetail(store: store, power: services.power, bluetooth: services.bluetooth)
        }]
    }
}

private struct BatteryRow: View {
    @ObservedObject var store: SystemStore
    @ObservedObject var power: PowerController
    @Environment(\.openPanelDetail) private var openDetails

    var body: some View {
        let battery = store.snapshot.battery
        PanelSplitTile(title: DeckL("电池"), value: "\(battery.percent)% · \(battery.statusText)",
                           symbol: battery.isCharging ? "battery.100percent.bolt" : "battery.75percent",
                       isActive: battery.isCharging || battery.isLowPowerMode, isEnabled: !power.isApplying,
                       toggleHelp: battery.isLowPowerMode ? DeckL("关闭低电量模式", "Turn Low Power Mode off") : DeckL("开启低电量模式", "Turn Low Power Mode on"),
                       onToggle: { power.setLowPowerMode(!ProcessInfo.processInfo.isLowPowerModeEnabled) { store.sampler.refreshBattery() } },
                       onDetails: { openDetails?() })
    }
}

private func batteryColor(_ battery: BatteryStats, theme: DeckTheme) -> Color? {
    if battery.isLowPowerMode { return theme.warning }
    return battery.percent <= 20 && !battery.isCharging ? theme.negative : nil
}

private struct BatteryDetail: View {
    @ObservedObject var store: SystemStore
    @ObservedObject var power: PowerController
    @ObservedObject var bluetooth: BluetoothController
    @Environment(\.deckTheme) private var theme

    var body: some View {
        let battery = store.snapshot.battery
        let sensors = store.snapshot.sensors
        VStack(spacing: DeckTheme.cardSpacing) {
            DeckCard {
                VStack(spacing: 6) {
                PanelDrilldownLink(id: "battery.details", title: DeckL("电池详情", "Battery details")) {
                    HStack(spacing: 12) {
                        let charge = Double(battery.percent) / 100
                        DeckRing(value: charge, color: batteryColor(battery, theme: theme) ?? theme.accent) {
                            DeckRingPercent(charge, caption: DeckL("电量"))
                        }
                        .frame(width: 98, height: 98)
                        .frame(maxWidth: .infinity)
                        DeckRing(value: battery.health ?? 0, color: theme.magenta) {
                            if let health = battery.health {
                                DeckRingPercent(health, caption: DeckL("电池健康"))
                            } else {
                                Text("—").foregroundStyle(theme.secondary)
                            }
                        }
                        .frame(width: 98, height: 98)
                        .frame(maxWidth: .infinity)
                    }
                } detail: {
                    BatteryDiagnostics(store: store)
                }
                DeckInfoRow(battery.statusText, battery.minutesRemaining.map { minutes in
                    (battery.isCharging ? DeckL("充满还需", "Time until full") : DeckL("剩余", "Time remaining"))
                        + " " + Format.duration(TimeInterval(minutes) * 60)
                } ?? "")
                }
            }
            MonitorHistoryCard(history: store.history.battery,
                               series: [.init(title: DeckL("电量"), color: theme.accent, format: Format.percent)],
                               values: { [Double($0.percent) / 100] }, maximum: 1, compact: true)
            DeckCard {
                VStack(alignment: .leading, spacing: 3) {
                    DeckTitle(DeckL("电量流向"))
                    if let adapter = battery.adapterWatts { DeckInfoRow(DeckL("适配器额定"), "\(adapter) W") }
                    if let input = sensors.adapterInputWatts, battery.isExternalPowerConnected {
                        DeckInfoRow(DeckL("适配器输入"), Format.watts(input))
                    }
                    if let system = sensors.systemWatts { DeckInfoRow(DeckL("系统耗电"), Format.watts(system)) }
                    if let watts = battery.watts, abs(watts) >= 0.05 {
                        DeckInfoRow(watts > 0 ? DeckL("充入电池") : DeckL("电池放电"), Format.watts(abs(watts)))
                    }
                }
            }
            DeckCard {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(DeckL("低电量模式")).font(.system(size: 13)).foregroundStyle(theme.primary)
                        Spacer()
                        DeckSwitch(isOn: battery.isLowPowerMode, isEnabled: !power.isApplying) {
                            power.setLowPowerMode(!battery.isLowPowerMode) { store.sampler.refreshBattery() }
                        }
                    }
                    if let error = power.lastError {
                        Text(error).font(.system(size: 11)).foregroundStyle(theme.warning)
                    }
                }
            }
            DeckCard {
                VStack(alignment: .leading, spacing: 8) {
                    DeckTitle(DeckL("设备电量", "Device batteries"))
                    let devices = bluetooth.connected.filter { $0.summaryBattery != nil || $0.caseLevel != nil }
                    if devices.isEmpty {
                        Text(DeckL("暂无可读取电量的已连接设备。", "No connected devices report a battery level."))
                            .font(.caption).foregroundStyle(theme.secondary)
                    }
                    ForEach(devices) { device in
                        if let percent = device.summaryBattery {
                            DeckMeterRow(device.name, value: Double(percent) / 100, text: "\(percent)%")
                        } else {
                            DeckInfoRow(device.name, "—")
                        }
                        if let left = device.left { DeckInfoRow(DeckL("左耳", "Left"), "\(left)%") }
                        if let right = device.right { DeckInfoRow(DeckL("右耳", "Right"), "\(right)%") }
                        if let level = device.caseLevel { DeckInfoRow(DeckL("充电盒", "Charging case"), "\(level)%") }
                    }
                }
            }
        }
        .onAppear { bluetooth.refreshIfStale() }
    }
}

private struct BatteryDiagnostics: View {
    @ObservedObject var store: SystemStore

    var body: some View {
        let battery = store.snapshot.battery
        VStack(spacing: DeckTheme.cardSpacing) {
            DeckCard {
                VStack(alignment: .leading, spacing: 4) {
                    DeckTitle(DeckL("电池", "Battery"))
                    DeckInfoRow(DeckL("功耗"), Format.watts(battery.watts))
                    DeckInfoRow(DeckL("电流", "Current"), sensorNumber(battery.amps, unit: "A"))
                    DeckInfoRow(DeckL("电压"), sensorNumber(battery.volts, unit: "V"))
                    DeckInfoRow(DeckL("温度"), Format.degrees(battery.temperatureCelsius))
                }
            }
            DeckCard {
                VStack(alignment: .leading, spacing: 4) {
                    DeckTitle(DeckL("电池健康"))
                    DeckInfoRow(DeckL("循环次数"), battery.cycleCount.map { String($0) } ?? "—")
                    DeckInfoRow(DeckL("状态", "Condition"), condition(battery.healthCondition))
                    DeckInfoRow(DeckL("设计容量", "Design capacity"), capacity(battery.designCapacity))
                    DeckInfoRow(DeckL("满充容量", "Full charge capacity"), capacity(battery.fullChargeCapacity))
                }
            }
            if battery.cellVolts.contains(where: { $0 != nil }) {
                DeckCard {
                    VStack(alignment: .leading, spacing: 4) {
                        DeckTitle(DeckL("电池单元", "Battery cells"))
                        ForEach(battery.cellVolts.indices, id: \.self) { index in
                            DeckInfoRow(DeckLF("电池单元 %lld", "Cell %lld", Int64(index + 1)),
                                        sensorNumber(battery.cellVolts[index], unit: "V"))
                        }
                    }
                }
            }
        }
    }

    private func capacity(_ value: Int?) -> String {
        value.map { $0.formatted(.number.locale(DeckLanguage.current.locale)) + " mAh" } ?? "—"
    }

    private func condition(_ value: String?) -> String {
        switch value {
        case "Good": DeckL("正常", "Normal")
        case "Fair", "Poor", "Check Battery", "Permanent Battery Failure", "Service Recommended":
            DeckL("建议维修", "Service recommended")
        default: value ?? "—"
        }
    }
}
