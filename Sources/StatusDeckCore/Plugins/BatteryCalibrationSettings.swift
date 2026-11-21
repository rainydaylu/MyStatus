import StatusDeckKit
import SwiftUI

struct BatteryCalibrationSettings: View {
    @ObservedObject var store: SystemStore
    @AppStorage(BatteryCalibrationPreference.key) private var enabled = true
    @AppStorage(BatteryCalibrationMethod.key) private var method = BatteryCalibrationMethod.global.rawValue
    @State private var showsDetails = false

    private var status: BatteryCalibrationStatus { store.batteryCalibration }
    private var perApp: Bool { method == BatteryCalibrationMethod.perApp.rawValue }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 28)).foregroundStyle(Color.accentColor)
                    .frame(width: 52, height: 52)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(DeckL("耗电估算校准", "Battery drain calibration")).font(.headline)
                    Text(DeckL("每分钟记录 · 每天校准", "Record each minute · calibrate daily"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(DeckL("启用耗电估算校准", "Enable battery drain calibration"), isOn: $enabled)
                    .labelsHidden().toggleStyle(.switch)
                    .accessibilityIdentifier("battery.calibration.enabled")
            }
            Text(DeckL("根据真实放电记录调整 %/h 换算。关闭后暂停记录与校准，保留已有数据，并使用基础估算。", "Adjust %/h conversion from measured discharge. Turning this off pauses recording and calibration, keeps existing data, and uses the base estimate."))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                methodChoice(.global, title: DeckL("简易", "Simple"), symbol: "slider.horizontal.3",
                             subtitle: DeckL("一个整体系数", "One global factor"))
                methodChoice(.perApp, title: DeckL("精准", "Precise"), symbol: "chart.xyaxis.line",
                             subtitle: DeckL("每个 App 独立拟合", "Fit each app separately"))
            }.accessibilityLabel(DeckL("校准方法", "Calibration method"))
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(stateText, systemImage: enabled ? "circle.inset.filled" : "pause.circle")
                        .foregroundStyle(enabled ? Color.accentColor : .secondary)
                    Spacer()
                    Text(DeckLF("近 7 天 · %ld 条记录", "Last 7 days · %ld records", status.recordCount))
                        .foregroundStyle(.secondary)
                }.font(.caption)
                ProgressView(value: perApp ? min(1, Double(status.appWindowCount) / Double(AppCalibrationFit.minimumRows)) : status.evidence.progress)
                    .tint(enabled ? Color.accentColor : .gray)
                    .accessibilityLabel(DeckL("校准样本积累进度", "Calibration data collection progress"))
                Text(DeckL("校准可能需要一天。", "Calibration may take a day."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), alignment: .leading, spacing: 12) {
                if perApp {
                    metric(DeckL("有效窗口", "Valid windows"), "\(status.appWindowCount)")
                    metric(DeckL("已拟合 App", "Fitted apps"), "\(status.model.perApp?.coefficients.count ?? 0)")
                    metric(DeckL("缺省系数", "Default factor"), "1.000×")
                } else {
                    metric(DeckL("有效放电", "Usable discharge"), String(format: "%.0f min", status.evidence.seconds / 60))
                    metric(DeckL("实际下降", "Measured drop"), String(format: "%.2f%%", status.evidence.actual))
                    metric(DeckL("当前换算系数", "Applied factor"), String(format: "%.3f×", enabled ? status.model.factor : 1.0))
                }
            }
            if perApp { appCoefficients }
            Divider()
            DisclosureGroup(DeckL("校准详情", "Calibration details"), isExpanded: $showsDetails) {
                VStack(spacing: 9) {
                    row(DeckL("模型", "Model"), perApp ? DeckL("线性拟合 · 每个 App 一个系数", "Linear fit · one factor per app") : DeckL("单参数比例校准", "Single proportional factor"))
                    row(DeckL("拟合窗口", "Fit window"), DeckL("前 7 个完整自然日", "Previous 7 complete days"))
                    row(DeckL("最近记录", "Last record"), dateText(status.lastRecordedAt))
                    row(DeckL("最近检查", "Last check"), status.model.attemptedDay ?? "—")
                    row(DeckL("最近成功校准", "Last successful calibration"), dateText(perApp ? status.model.perApp?.fittedAt : status.model.fittedAt))
                    if perApp, let fit = status.model.perApp {
                        row(DeckL("拟合 / 验证窗口", "Training / validation windows"), "\(fit.trainingCount) / \(fit.validationCount)")
                        row(DeckL("验证误差（%/h）", "Validation error (%/h)"), String(format: "%.2f → %.2f", fit.baselineRMSE, fit.fittedRMSE))
                        row(DeckL("拟合基线（共享负载）", "Fitted baseline (shared load)"), String(format: "%.2f%%/h", fit.backgroundRate))
                    } else if !perApp, status.model.fittedAt != nil {
                        row(DeckL("系数变化", "Factor change"), String(format: "%.3f → %.3f", status.model.previousFactor, status.model.factor))
                        row(DeckL("上次拟合放电时长", "Last fit discharge duration"), String(format: "%.0f min", status.model.usableSeconds / 60))
                        row(DeckL("上次实际 / 估计下降", "Last measured / estimated drop"), String(format: "%.2f%% / %.2f%%", status.model.observedDrop, status.model.predictedDrop))
                    }
                    Text(perApp
                         ? DeckL("整机掉电率 = 共享基线 + 各 App 耗电率 × 各自系数。系数范围 0.5–1.5；负载高度同步的 App 暂不调整，留出数据验证误差下降后才更新。这些系数是估算值。", "Total drain = shared baseline + app rates × individual factors. Factors stay within 0.5–1.5. Highly correlated apps remain unchanged; updates require lower error on held-out data. Factors are estimates.")
                         : DeckL("系数 = 真实掉电量 ÷ 基础估计掉电量。只使用连续、未接电的放电区间；样本不足或结果异常时保留原系数。", "Factor = measured charge drop ÷ base estimated drop. Only continuous unplugged discharge intervals are used; insufficient or implausible data keeps the previous factor."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.top, 10)
            }
            .accessibilityIdentifier("battery.calibration.details")
            HStack {
                Text(DeckL("记录仅保存在本机", "Records stay on this Mac")).foregroundStyle(.secondary)
                Spacer()
                Button(DeckL("查看电量记录…", "Show battery records…")) {
                    NSWorkspace.shared.open(BatteryLearningStore.standardFolder)
                }.buttonStyle(.link)
            }.font(.caption)
        }
        .padding(.vertical, 8)
        .onAppear { store.sampler.setBatteryCalibrationDetailsVisible(true) }
        .onDisappear { store.sampler.setBatteryCalibrationDetailsVisible(false) }
        .onChange(of: enabled) { store.sampler.setBatteryCalibrationEnabled($0) }
        .onChange(of: method) { store.sampler.setBatteryCalibrationMethod(BatteryCalibrationMethod(rawValue: $0) ?? .global) }
    }

    private var stateText: String {
        if !enabled { return DeckL("已暂停记录与校准", "Recording and calibration paused") }
        if perApp {
            return status.model.perApp == nil
                ? DeckL("正在积累 App 独立拟合样本", "Collecting per-app fitting data")
                : DeckL("App 独立系数已生效", "Per-app factors applied")
        }
        if status.evidence.result != nil { return DeckL("样本已就绪，等待每日校准", "Data ready for daily calibration") }
        if status.evidence.progress >= 1 { return DeckL("样本结果异常，保留原系数", "Implausible result; keeping previous factor") }
        return DeckL("正在积累放电样本", "Collecting discharge data")
    }

    private var appCoefficients: some View {
        let learned = status.model.perApp?.coefficients ?? [:]
        let current = store.snapshot.appEnergy.allEntries ?? store.snapshot.appEnergy.entries
        let paths = Set(learned.keys).union(current.prefix(5).map(\.bundlePath)).sorted()
        return VStack(alignment: .leading, spacing: 10) {
            Text(DeckL("App 独立系数", "Per-app factors")).font(.subheadline.weight(.medium))
            ForEach(paths, id: \.self) { path in
                HStack(spacing: 8) {
                    Image(nsImage: DeckAppIcon.image(forPath: path)).resizable().frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(learned[path]?.name ?? current.first { $0.bundlePath == path }?.name ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
                            .font(.callout).lineLimit(1)
                        Text(learned[path] == nil ? DeckL("等待足够的独立负载样本", "Waiting for independent workload data") : DeckL("已通过留出数据验证", "Validated on held-out data"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(String(format: "%.3f×", enabled ? learned[path]?.factor ?? 1.0 : 1.0)).monospacedDigit()
                }
            }
            if paths.isEmpty {
                Text(DeckL("下一次 App 能耗采样后显示条目；尚未拟合时系数为 1。", "Apps appear after the next energy sample; unfitted factors are 1."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.accessibilityIdentifier("battery.calibration.app-factors")
    }

    private func methodChoice(_ value: BatteryCalibrationMethod, title: String, symbol: String, subtitle: String) -> some View {
        let selected = method == value.rawValue
        return Button { method = value.rawValue } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 28))
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.15)))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
            .accessibilityLabel(title + " · " + subtitle)
            .accessibilityValue(selected ? DeckL("已选择", "Selected") : "")
            .accessibilityIdentifier("battery.calibration.method.\(value.rawValue)")
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 19, weight: .medium, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }.font(.callout)
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(.dateTime.month().day().hour().minute().locale(DeckLanguage.current.locale))
    }
}
