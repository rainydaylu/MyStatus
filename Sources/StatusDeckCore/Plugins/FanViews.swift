import StatusDeckKit
import SwiftUI

struct FanControls: View {
    @ObservedObject var controller: FanController
    let detailed: Bool
    var readings: [FanReading] = []
    @Environment(\.deckTheme) private var theme

    var body: some View {
        let ids = Set(controller.targets.map(\.id) + readings.map(\.id)).sorted()
        VStack(alignment: .leading, spacing: 10) {
            DeckTitle(detailed ? DeckL("风扇控制", "Fan control") : DeckL("风扇"))
            if !controller.authorization.isAuthorized {
                Text(DeckL("首次调速时会申请管理员授权，与低电量模式共用。", "The first adjustment asks for administrator approval, shared with Low Power Mode."))
                    .font(.caption)
                    .foregroundStyle(theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(ids, id: \.self) { id in
                let reading = readings.first { $0.id == id }
                if let fan = controller.targets.first(where: { $0.id == id }), let range = fan.bounds {
                    FanSpeedRow(fan: fan, range: range, controller: controller, detailed: detailed)
                } else if let reading {
                    DeckMeterRow(reading.name, value: reading.fraction, text: "\(Int(reading.rpm)) RPM")
                } else {
                    let rpm = controller.targets.first { $0.id == id }?.currentSpeed
                    DeckInfoRow(DeckLF("风扇 %ld", "Fan %ld", id + 1), rpm.map { "\($0) RPM" } ?? "—")
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
}

private struct FanSpeedRow: View {
    let fan: FanTarget
    let range: ClosedRange<Int>
    @ObservedObject var controller: FanController
    let detailed: Bool
    @State private var draft: Double?
    @Environment(\.deckTheme) private var theme

    private var target: Double {
        Double(fan.clamp(fan.isManual ? fan.targetSpeed : (fan.currentSpeed ?? range.lowerBound)) ?? range.lowerBound)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            DeckInfoRow(DeckLF("风扇 %ld", "Fan %ld", fan.id + 1), fan.currentSpeed.map { "\($0) RPM" } ?? "—")
            if detailed {
                DeckInfoRow(DeckL("控制方式", "Control mode"), fan.isManual ? DeckL("固定转速", "Fixed speed") : DeckL("系统自动", "System Auto"))
                if fan.isManual {
                    DeckInfoRow(DeckL("已设目标", "Current target"), "\(fan.targetSpeed) RPM")
                }
            }
            Slider(value: Binding(get: { draft ?? target }, set: { draft = $0 }),
                   in: Double(range.lowerBound)...Double(range.upperBound)) {
                Text(DeckLF("风扇 %ld 目标转速", "Fan %ld target speed", fan.id + 1))
            }
            .labelsHidden()
            if detailed {
                HStack {
                    Text("\(range.lowerBound) RPM")
                    Spacer()
                    Text("\(range.upperBound) RPM")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(theme.secondary)
                HStack {
                    Button(DeckL("最低", "Min")) { draft = Double(range.lowerBound) }
                    Button("50%") { draft = Double(range.lowerBound + (range.upperBound - range.lowerBound) / 2) }
                    Button(DeckL("最高", "Max")) { draft = Double(range.upperBound) }
                }
                .controlSize(.small)
            }
            HStack {
                Button(DeckL("恢复自动", "Return to Auto")) {
                    controller.automatic(fan)
                    draft = nil
                }
                Spacer()
                Button(DeckLF("应用 %ld RPM", "Apply %ld RPM", Int((draft ?? target).rounded()))) {
                    controller.apply(fan, rpm: Int((draft ?? target).rounded()))
                    draft = nil
                }
                .disabled(draft == nil)
            }
            .controlSize(.small)
        }
        .disabled(controller.isBusy)
        .padding(.vertical, 4)
    }
}
