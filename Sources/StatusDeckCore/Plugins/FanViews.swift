import StatusDeckKit
import SwiftUI

struct FanControls: View {
    @ObservedObject var controller: FanController
    let detailed: Bool
    var readings: [FanReading] = []
    var historyStore: SystemStore? = nil
    @Environment(\.deckTheme) private var theme

    var body: some View {
        let ids = Set(controller.targets.map(\.id) + readings.map(\.id)).sorted()
        VStack(alignment: .leading, spacing: detailed ? 10 : 7) {
            DeckTitle(detailed ? DeckL("风扇控制", "Fan control") : DeckL("风扇"))
            if !controller.authorization.isAuthorized {
                Text(DeckL("首次调速时会申请管理员授权，与低电量模式共用。", "The first adjustment asks for administrator approval, shared with Low Power Mode."))
                    .font(.caption)
                    .foregroundStyle(theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(ids, id: \.self) { id in
                if id != ids.first { Divider().padding(.vertical, detailed ? 4 : 2) }
                let reading = readings.first { $0.id == id }
                if let fan = controller.targets.first(where: { $0.id == id }), let range = fan.bounds {
                    FanSpeedRow(fan: fan, range: range, controller: controller, compact: !detailed,
                                readingRPM: reading?.rpm, historyStore: historyStore) {
                        historyLabel(id: id) { title in
                            FanReadout(title: title, rpm: fan.currentSpeed.map(Double.init) ?? reading?.rpm,
                                       fraction: Double(fan.currentSpeed ?? 0) / Double(range.upperBound),
                                       mode: fan.isManual ? DeckL("固定转速", "Fixed speed") : DeckL("系统自动", "System Auto"), compact: !detailed)
                        }
                    }
                } else if let reading {
                    historyLabel(id: id) { title in
                        FanReadout(title: title, rpm: reading.rpm, fraction: reading.fraction, mode: DeckL("实时转速", "Live speed"), compact: !detailed)
                    }
                } else {
                    let rpm = controller.targets.first { $0.id == id }?.currentSpeed
                    historyLabel(id: id) { title in
                        FanReadout(title: title, rpm: rpm.map(Double.init), fraction: 0, mode: DeckL("实时转速", "Live speed"), compact: !detailed)
                    }
                }
            }
            if !controller.didReadFans {
                Text(DeckL("暂未读取到 SMC 风扇数据。", "SMC fan data is unavailable."))
                    .font(.caption).foregroundStyle(theme.secondary)
                if detailed && !controller.authorization.isAuthorized {
                    Button(DeckL("授权并重新检测…", "Authorize and detect again…"), action: controller.authorizeAndRefresh)
                        .disabled(controller.isBusy)
                }
            } else if ids.isEmpty {
                Text(DeckL("此 Mac 未报告风扇。", "This Mac reported no fans."))
                    .font(.caption).foregroundStyle(theme.secondary)
            } else if !controller.targets.contains(where: { $0.bounds != nil }) {
                Text(DeckL("此 Mac 未报告有效的转速范围，风扇由系统管理。", "This Mac did not report a usable speed range. macOS manages the fans."))
                    .font(.caption).foregroundStyle(theme.secondary)
            }
            if let message = controller.message {
                Text(message).font(.caption).foregroundStyle(theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task {
            while !Task.isCancelled {
                controller.refresh()
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
    }

    @ViewBuilder
    private func historyLabel<Label: View>(id: Int, @ViewBuilder label: (String) -> Label) -> some View {
        let title = DeckLF("风扇 %ld", "Fan %ld", id + 1)
        let row = label(title)
        if let historyStore {
            PanelDrilldownLink(id: "fan.rpm.\(id)", title: title) {
                row
            } detail: {
                SensorHistoryView(store: historyStore, title: title, source: \.sensors,
                                  measure: { $0.fans.first { $0.id == id }?.rpm }, format: rpmText)
            }
        } else {
            row
        }
    }

    private func rpmText(_ rpm: Double?) -> String {
        rpm.map { "\(Int($0.rounded())) RPM" } ?? "—"
    }
}

private struct FanSpeedRow<Label: View>: View {
    let fan: FanTarget
    let range: ClosedRange<Int>
    @ObservedObject var controller: FanController
    let compact: Bool
    let readingRPM: Double?
    let historyStore: SystemStore?
    @ViewBuilder let label: () -> Label
    @State private var draft: Double?
    @State private var isEditing = false
    @Environment(\.deckTheme) private var theme

    private var target: Double {
        Double(fan.clamp(fan.isManual ? fan.targetSpeed : (fan.currentSpeed ?? range.lowerBound)) ?? range.lowerBound)
    }

    private var showsRestore: Bool { isEditing || draft != nil || fan.isManual }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 10) {
            if compact { compactHeader } else { label() }
            HStack {
                Text(DeckL("目标转速", "Target speed")).font(.system(size: compact ? 10 : 11)).foregroundStyle(theme.secondary)
                Spacer()
                Text("\(Int((draft ?? target).rounded())) RPM")
                    .font(.system(size: compact ? 11 : 12, weight: .medium)).monospacedDigit().foregroundStyle(theme.primary)
            }
            Slider(value: Binding(get: { draft ?? target }, set: { draft = $0 }),
                   in: Double(range.lowerBound)...Double(range.upperBound), onEditingChanged: { isEditing = $0 }) {
                Text(DeckLF("风扇 %ld 目标转速", "Fan %ld target speed", fan.id + 1))
            }
            .labelsHidden()
            .tint(theme.accent)
            .controlSize(compact ? .small : .regular)
            HStack {
                Text("\(range.lowerBound) RPM")
                Spacer()
                Text("\(range.upperBound) RPM")
            }
            .font(.system(size: 9).monospacedDigit()).foregroundStyle(theme.secondary)
            if !compact, showsRestore { restoreButton }
        }
        .disabled(controller.isBusy)
        .padding(.vertical, compact ? 1 : 4)
        .task(id: isEditing ? nil : draft) {
            guard let value = draft, !isEditing else { return }
            do {
                // Coalesce clicks/keyboard changes; a drag commits on release.
                try await Task.sleep(for: .milliseconds(150))
                while controller.isBusy { try await Task.sleep(for: .milliseconds(100)) }
                guard !Task.isCancelled, draft == value, !isEditing else { return }
                controller.apply(fan, rpm: Int(value.rounded()))
                while controller.isBusy { try await Task.sleep(for: .milliseconds(100)) }
                guard !Task.isCancelled, draft == value else { return }
                draft = nil
            } catch { /* A newer gesture or leaving the view cancels the pending change. */ }
        }
    }

    private var compactHeader: some View {
        HStack(spacing: 7) {
            Text(DeckLF("风扇 %ld", "Fan %ld", fan.id + 1))
                .font(.system(size: 11, weight: .medium)).foregroundStyle(theme.primary)
            if showsRestore {
                restoreButton
            } else {
                Text(DeckL("系统自动", "System Auto"))
                    .font(.system(size: 10)).foregroundStyle(theme.secondary)
            }
            Spacer(minLength: 4)
            compactReading
        }.frame(height: 24)
    }

    @ViewBuilder
    private var compactReading: some View {
        if let historyStore {
            PanelDrilldownLink(id: "fan.rpm.\(fan.id)", title: DeckLF("风扇 %ld", "Fan %ld", fan.id + 1)) {
                rpmLabel
            } detail: {
                SensorHistoryView(store: historyStore, title: DeckLF("风扇 %ld", "Fan %ld", fan.id + 1),
                                  source: \.sensors, measure: { $0.fans.first { $0.id == fan.id }?.rpm },
                                  format: { $0.map { "\(Int($0.rounded())) RPM" } ?? "—" })
            }.fixedSize()
        } else {
            rpmLabel
        }
    }

    private var rpmLabel: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text((fan.currentSpeed.map(Double.init) ?? readingRPM).map { "\(Int($0.rounded()))" } ?? "—")
                .font(.system(size: 15, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(theme.primary)
            Text("RPM").font(.system(size: 9)).foregroundStyle(theme.secondary)
        }
    }

    private var restoreButton: some View {
        Button {
            draft = nil
            controller.automatic(fan)
        } label: {
            if compact {
                Text(DeckL("恢复自动", "Return to Auto")).font(.system(size: 10, weight: .medium))
            } else {
                SwiftUI.Label(DeckL("恢复自动", "Return to Auto"), systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity).padding(.vertical, 5)
            }
        }
        .buttonStyle(.bordered).controlSize(compact ? .small : .large)
        .accessibilityIdentifier("fan.\(fan.id).automatic")
    }
}

private struct FanReadout: View {
    let title: String
    let rpm: Double?
    let fraction: Double
    let mode: String
    let compact: Bool
    @Environment(\.deckTheme) private var theme

    var body: some View {
        HStack(spacing: compact ? 7 : 10) {
            if !compact {
                DeckRing(value: fraction, color: theme.accent, lineWidth: 3) {
                    Image(systemName: "fanblades.fill").font(.system(size: 20)).foregroundStyle(theme.accent)
                }.frame(width: 44, height: 44)
            }
            if compact {
                Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(theme.primary)
                Text(mode).font(.system(size: 10)).foregroundStyle(theme.secondary)
            } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: compact ? 11 : 12, weight: .medium)).foregroundStyle(theme.primary)
                Text(mode).font(.system(size: compact ? 9 : 10)).foregroundStyle(theme.secondary)
            }
            }
            Spacer(minLength: 5)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(rpm.map { "\(Int($0.rounded()))" } ?? "—")
                    .font(.system(size: compact ? 15 : 23, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(theme.primary)
                Text("RPM").font(.system(size: 9)).foregroundStyle(theme.secondary)
            }
        }.padding(.vertical, 2)
    }
}
