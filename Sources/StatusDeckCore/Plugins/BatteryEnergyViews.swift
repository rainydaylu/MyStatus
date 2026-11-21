import StatusDeckKit
import SwiftUI

struct BatteryPowerFlow: Equatable {
    let isExternal: Bool
    let input: Double?
    let battery: Double?
    let system: Double?
    let chip: Double?
    let display: Double?
    let other: Double?

    init(snapshot: SystemSnapshot) {
        func valid(_ value: Double?) -> Double? {
            guard let value, value.isFinite, value >= 0, value <= 1_000 else { return nil }
            return value
        }
        let stats = snapshot.battery
        let external = stats.isExternalPowerConnected
        let batteryWatts = stats.watts.flatMap { $0.isFinite && abs($0) <= 1_000 ? $0 : nil }
        let incoming = external ? valid(stats.adapterInputWatts) ?? valid(snapshot.sensors.adapterInputWatts) : batteryWatts.map { max(0, -$0) }
        isExternal = external
        battery = batteryWatts
        input = incoming
        // Never use adapterWatts here: that is a negotiated rating, not a
        // measurement of the power entering the computer.
        system = valid(stats.systemLoadWatts) ?? valid(snapshot.sensors.systemWatts)
            ?? incoming.flatMap { source in batteryWatts.map { external ? max(0, source - $0) : source } }
        let domains = [snapshot.soc.cpuWatts, snapshot.soc.gpuWatts, snapshot.soc.aneWatts].compactMap(valid)
        let recentEstimate = snapshot.appEnergy.sampledAt.map { Date().timeIntervalSince($0) <= 90 } ?? true
        // A zero/unavailable CPU domain must not turn GPU-only power into a
        // purported whole-chip reading when the cached minute is stale.
        let fullLiveReading = (snapshot.soc.cpuWatts ?? 0) > 0
        chip = (recentEstimate ? valid(snapshot.appEnergy.chipWatts) : nil)
            ?? (fullLiveReading && !domains.isEmpty ? domains.reduce(0, +) : nil)
        display = valid(snapshot.sensors.displayWatts)
        if let system, let chip, let display, system >= chip + display {
            other = system - chip - display
        } else {
            other = nil
        }
    }
}

/// A compact flow ribbon on the same DeckCard surface as the other flyouts.
struct BatteryPowerFlowCard: View {
    let snapshot: SystemSnapshot
    @Environment(\.deckTheme) private var theme

    var body: some View {
        let flow = BatteryPowerFlow(snapshot: snapshot)
        DeckCard {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    DeckTitle(DeckL("电力流向", "Power flow"))
                    Spacer()
                    Text(flow.isExternal ? DeckL("已接电源", "Plugged in") : DeckL("电池供电", "On battery"))
                        .font(.system(size: 10)).foregroundStyle(theme.secondary)
                }
                GeometryReader { geometry in
                    let width = geometry.size.width
                    let sourceX: CGFloat = 20
                    let middleX = width * 0.48
                    let endX = width - 15
                    let deviceY: CGFloat = flow.isExternal ? 77 : 53
                    Canvas { context, _ in
                        let maximum = max(1, flow.input ?? flow.system ?? 1)
                        func ribbon(_ from: CGPoint, _ to: CGPoint, watts: Double?, color: Color) {
                            let amount = watts.map { abs($0) }
                            let thickness = amount.map { CGFloat(max(2, min(22, 22 * $0 / maximum))) } ?? 3
                            if amount == nil {
                                var line = Path()
                                line.move(to: from)
                                let dx = (to.x - from.x) * 0.52
                                line.addCurve(to: to, control1: CGPoint(x: from.x + dx, y: from.y),
                                              control2: CGPoint(x: to.x - dx, y: to.y))
                                context.stroke(line, with: .color(theme.secondary.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                return
                            }
                            let dx = (to.x - from.x) * 0.52
                            var path = Path()
                            path.move(to: CGPoint(x: from.x, y: from.y - thickness / 2))
                            path.addCurve(to: CGPoint(x: to.x, y: to.y - thickness / 2),
                                          control1: CGPoint(x: from.x + dx, y: from.y - thickness / 2),
                                          control2: CGPoint(x: to.x - dx, y: to.y - thickness / 2))
                            path.addLine(to: CGPoint(x: to.x, y: to.y + thickness / 2))
                            path.addCurve(to: CGPoint(x: from.x, y: from.y + thickness / 2),
                                          control1: CGPoint(x: to.x - dx, y: to.y + thickness / 2),
                                          control2: CGPoint(x: from.x + dx, y: from.y + thickness / 2))
                            path.closeSubpath()
                            context.fill(path, with: .linearGradient(Gradient(colors: [color.opacity(0.45), color.opacity(0.13)]),
                                                                    startPoint: from, endPoint: to))
                            context.stroke(path, with: .color(color.opacity(0.3)), lineWidth: 0.6)
                        }
                        if flow.isExternal {
                            ribbon(CGPoint(x: 41, y: 42), CGPoint(x: middleX - 19, y: 17), watts: flow.battery, color: theme.positive)
                        }
                        ribbon(CGPoint(x: 41, y: 62), CGPoint(x: middleX - 19, y: deviceY), watts: flow.system, color: theme.accent)
                        for (watts, y, color) in [(flow.chip, CGFloat(39), theme.accent),
                                                 (flow.display, CGFloat(65), theme.magenta),
                                                 (flow.other, CGFloat(91), theme.secondary)] {
                            ribbon(CGPoint(x: middleX + 19, y: deviceY), CGPoint(x: endX - 16, y: y), watts: watts, color: color)
                        }
                    }
                    VStack(spacing: 7) {
                        Image(systemName: flow.isExternal ? "powerplug.fill" : "battery.75percent").font(.system(size: 17))
                        Text(Format.watts(flow.input)).font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    }
                    .foregroundStyle(flow.isExternal ? theme.accent : theme.positive)
                    .frame(width: 40, height: 80)
                    .background(RoundedRectangle(cornerRadius: 12).fill(theme.inset))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.cardStroke, lineWidth: 0.7))
                    .position(x: sourceX, y: 52)
                    if flow.isExternal {
                        node("battery.100percent", color: theme.positive).position(x: middleX, y: 17)
                            .help(DeckL("电池", "Battery"))
                        value(flow.battery).position(x: width * 0.30, y: 13)
                            .help(DeckL("正值充电，负值放电", "Positive: charging; negative: discharging"))
                    }
                    node("laptopcomputer", color: theme.accent).position(x: middleX, y: deviceY)
                        .help(DeckL("整机耗电", "System power"))
                    value(flow.system).position(x: width * 0.30, y: flow.isExternal ? 85 : 72)
                    node("cpu", color: theme.accent).position(x: endX, y: 39).help(DeckL("芯片", "Chip"))
                    node("display", color: theme.magenta).position(x: endX, y: 65).help(DeckL("内置屏幕", "Built-in display"))
                    node("ellipsis", color: theme.secondary).position(x: endX, y: 91).help(DeckL("其他耗电", "Other power"))
                    value(flow.chip).position(x: width * 0.73, y: 33)
                    value(flow.display).position(x: width * 0.73, y: 62)
                    value(flow.other).position(x: width * 0.73, y: 91)
                }
                .frame(height: 103)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(DeckLF("电力流向：输入 %@，电池 %@，整机 %@，芯片 %@，屏幕 %@，其他 %@", "Power flow: input %@, battery %@, system %@, chip %@, display %@, other %@",
                                          Format.watts(flow.input), Format.watts(flow.battery), Format.watts(flow.system),
                                          Format.watts(flow.chip), Format.watts(flow.display), Format.watts(flow.other)))
            }
        }
        .accessibilityIdentifier("battery.power-flow")
    }

    private func node(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(color)
            .frame(width: 32, height: 24)
            .background(RoundedRectangle(cornerRadius: 8).fill(theme.inset))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.cardStroke, lineWidth: 0.7))
    }

    private func value(_ watts: Double?) -> some View {
        Text(Format.watts(watts)).font(.system(size: 10, weight: .semibold)).monospacedDigit()
            .foregroundStyle(theme.primary).padding(.horizontal, 3).padding(.vertical, 1)
            .background(theme.cardBottom.opacity(0.7), in: Capsule())
    }
}

struct BatteryHardwareEnergyCard: View {
    let snapshot: SystemSnapshot
    @Environment(\.deckTheme) private var theme

    var body: some View {
        let flow = BatteryPowerFlow(snapshot: snapshot)
        DeckCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    DeckTitle(DeckL("硬件与系统", "Hardware and system"))
                    Spacer()
                    Text(DeckL("实时功率", "Live power")).font(.system(size: 10)).foregroundStyle(theme.secondary)
                }
                DeckInfoRow(DeckL("内置屏幕", "Built-in display"), Format.watts(flow.display))
                DeckInfoRow(DeckL("其他硬件与系统", "Other hardware and system"), flow.other.map { "≈ " + Format.watts($0) } ?? "—")
                Text(DeckL("其他项为整机扣除芯片与屏幕后的余量估算；风扇暂无独立功耗读数。", "Other power is the estimated remainder after chip and display power. A separate fan-power reading is unavailable."))
                    .font(.system(size: 9)).foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("battery.hardware-energy")
    }
}

struct BatteryAppEnergyCard: View {
    let energy: AppEnergyStats
    let battery: BatteryStats
    @Environment(\.deckTheme) private var theme

    var body: some View {
        DeckCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    DeckTitle(DeckL("App 能耗", "App energy"))
                    Spacer()
                    Text(totalRate).font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(theme.primary)
                        .help(DeckL("所有可归属 App 的合计，包含列表外的 App；不含硬件与共享系统耗电。", "Total for all attributable apps, including apps outside this list; excludes shared hardware and system power."))
                }
                if energy.state == .warmingUp {
                    Text(DeckL("首次采样正在积累 1 分钟数据，之后打开直接显示缓存。", "Collecting the first minute. Reopening will show cached results immediately."))
                        .font(.system(size: 11)).foregroundStyle(theme.secondary)
                } else if energy.state == .unavailable {
                    Text(DeckL("当前系统未提供可读取的 App 能耗。", "App energy counters are unavailable on this system."))
                        .font(.system(size: 11)).foregroundStyle(theme.secondary)
                } else if energy.entries.isEmpty {
                    Text(DeckL("当前未测得 App 能耗。", "No app energy use measured in this interval."))
                        .font(.system(size: 11)).foregroundStyle(theme.secondary)
                }
                ForEach(displayedEntries) { entry in
                    HStack(spacing: 8) {
                        Image(nsImage: DeckAppIcon.image(forPath: entry.bundlePath)).resizable().frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.name).font(.system(size: 12)).lineLimit(1).foregroundStyle(theme.primary)
                                Spacer(minLength: 5)
                                Text(rate(entry)).font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(theme.primary)
                            }
                            GeometryReader { proxy in
                                Capsule().fill(theme.inset)
                                Capsule().fill(theme.accent.opacity(0.7))
                                    .frame(width: proxy.size.width * min(1, (entry.percentPerHour(battery: battery) ?? entry.watts) / max(0.001, displayedEntries.first?.percentPerHour(battery: battery) ?? displayedEntries.first?.watts ?? 1)))
                            }.frame(height: 3)
                        }
                    }
                    .padding(.vertical, 2)
                    .help(Format.watts(entry.watts))
                }
                if energy.state == .ready {
                    Text(sampleDescription)
                        .font(.system(size: 9)).foregroundStyle(theme.secondary)
                }
                Text(DeckL("含辅助进程的 CPU / GPU / 神经引擎能耗；不含屏幕、风扇等共享耗电。接电时为电池等效估算。", "CPU / GPU / Neural Engine energy including helpers; excludes shared loads such as the display and fans. Rates are battery-equivalent estimates while plugged in."))
                    .font(.system(size: 9)).foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text(!battery.energyCalibrationEnabled
                         ? DeckL("校准已关闭", "Calibration is off")
                         : battery.energyCalibrationMethod == .perApp
                            ? DeckL("App 独立校准 · 未拟合的 App 系数为 1", "Per-app calibration · unfitted apps use factor 1")
                         : battery.energyCalibrationDate == nil
                            ? DeckL("校准：等待放电样本", "Calibration: waiting for discharge data")
                            : DeckL("已按真实放电记录校准", "Calibrated from measured discharge"))
                        .foregroundStyle(theme.secondary)
                    Spacer()
                    Button(DeckL("电量记录", "Battery records")) {
                        NSWorkspace.shared.open(BatteryLearningStore.standardFolder)
                    }.buttonStyle(.link)
                }.font(.system(size: 9))
            }
        }
        .accessibilityIdentifier("battery.app-energy")
    }

    private var totalRate: String {
        guard let percent = energy.percentPerHour(battery: battery) else {
            return DeckL("1h 耗电 —", "1h drain —")
        }
        if percent < 0.01 { return DeckL("1h 耗电 <0.01%", "1h drain <0.01%") }
        return String(format: DeckL("1h 耗电 ≈ %.2f%%", "1h drain ≈ %.2f%%"), percent)
    }

    private var displayedEntries: [AppEnergyEntry] {
        Array((energy.allEntries ?? energy.entries).sorted {
            ($0.percentPerHour(battery: battery) ?? $0.watts) > ($1.percentPerHour(battery: battery) ?? $1.watts)
        }.prefix(5))
    }

    private var sampleDescription: String {
        let average = energy.seconds >= 55 ? DeckL("1 分钟平均", "1-minute average")
            : DeckLF("平均 %lld 秒", "Average over %lld s", Int64(energy.seconds.rounded()))
        guard let date = energy.sampledAt else { return average }
        let age = max(0, Date().timeIntervalSince(date))
        let updated: String
        if age < 60 { updated = DeckL("刚刚更新", "Updated just now") }
        else if age < 3_600 { updated = DeckLF("%lld 分钟前更新", "Updated %lld min ago", Int64(age / 60)) }
        else { updated = DeckLF("%lld 小时前更新", "Updated %lld h ago", Int64(age / 3_600)) }
        return average + " · " + updated
    }

    private func rate(_ entry: AppEnergyEntry) -> String {
        guard let percent = entry.percentPerHour(battery: battery) else { return Format.watts(entry.watts) }
        if percent < 0.01 { return "<0.01%/h" }
        return String(format: "≈ %.2f%%/h", percent)
    }
}
