import StatusDeckKit
import SwiftUI

struct TransferActivityCard: View {
    private typealias Chart = (history: TransferHistory, bars: (first: [Double?], second: [Double?]))

    let title: String
    let firstLabel: String
    let secondLabel: String
    let first: Double
    let second: Double
    let history: TransferHistory
    let floor: Double
    var expanded = false

    @State private var range = HistoryRange.oneMinute
    @State private var hover = ChartHoverSession<Chart>()
    @Environment(\.deckTheme) private var theme

    var body: some View {
        let seconds = range.rawValue
        let shown: Chart = hover.snapshot ?? (history, history.measuredBins(seconds: seconds, count: History.capacity))
        let chart = shown.bars
        DeckCard {
            VStack(spacing: 9) {
                HStack {
                    if !expanded { DeckTitle(title) }
                    Spacer()
                    if expanded {
                        HistoryRangePicker(selection: $range).fixedSize()
                    }
                }
                if !expanded {
                    HStack(spacing: 8) {
                        DeckStat(Format.speed(first), label: firstLabel, color: theme.magenta)
                        DeckStat(Format.speed(second), label: secondLabel, color: theme.accent)
                    }
                }
                if expanded {
                    TransferHistoryGraph(history: shown.history, seconds: seconds, floor: floor,
                                         firstLabel: firstLabel, secondLabel: secondLabel,
                                         upper: chart.first, lower: chart.second, pointer: hover.pointer)
                        .frame(height: 190)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let point): hover.move(to: point, showing: shown)
                            case .ended: hover.end()
                            }
                        }
                } else {
                    TransferRatePlot(upper: chart.first, lower: chart.second, floor: floor)
                        .frame(height: 118)
                }
                HStack {
                    Text(DeckL("峰值", "Peak"))
                    Spacer()
                    Text(Format.speed(chart.first.compactMap { $0 }.max() ?? 0)).foregroundStyle(theme.magenta)
                    Text(Format.speed(chart.second.compactMap { $0 }.max() ?? 0)).foregroundStyle(theme.accent)
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(theme.secondary)
            }
        }
        .onChange(of: range) { _ in hover.end() }
    }
}

private struct TransferHistoryGraph: View {
    let history: TransferHistory
    let seconds: Int
    let floor: Double
    let firstLabel: String
    let secondLabel: String
    let upper: [Double?]
    let lower: [Double?]
    let pointer: CGPoint?
    @Environment(\.deckTheme) private var theme

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Label(firstLabel, systemImage: "arrow.up").foregroundStyle(theme.magenta)
                Label(secondLabel, systemImage: "arrow.down").foregroundStyle(theme.accent)
                Spacer(minLength: 0)
                Text(DeckL("独立刻度", "Separate scales")).foregroundStyle(theme.secondary)
            }
            .font(.caption2)
            TransferRatePlot(upper: upper, lower: lower, floor: floor, history: history,
                             seconds: seconds, firstLabel: firstLabel, secondLabel: secondLabel,
                             pointer: pointer.map { CGPoint(x: $0.x, y: max(0, $0.y - 20)) })
            HStack {
                Text(DeckL("较早", "Earlier"))
                Spacer()
                Text(DeckL("现在", "Now"))
            }
            .font(.system(size: 9))
            .foregroundStyle(theme.secondary)
        }
    }
}

/// Independent, rounded ranges keep uploads/reads visible beside larger downloads/writes.
struct TransferRateScale {
    let maximum: Double

    init(values: [Double], floor: Double) {
        let peak = max(1, floor.isFinite ? floor : 1, values.filter { $0.isFinite }.max() ?? 0)
        let unit = pow(10, Foundation.floor(log10(peak)))
        let fraction = peak / unit
        let step = [1.0, 2, 5, 10].first { $0 >= fraction } ?? 10
        maximum = step * unit
    }
}

struct TransferRatePlot: View {
    let upper: [Double?]
    let lower: [Double?]
    let floor: Double
    var history: TransferHistory? = nil
    var seconds = 60
    var firstLabel = ""
    var secondLabel = ""
    var pointer: CGPoint? = nil
    @Environment(\.deckTheme) private var theme
    private let axisWidth: CGFloat = 58

    var body: some View {
        let firstScale = TransferRateScale(values: upper.compactMap { $0 }, floor: floor)
        let secondScale = TransferRateScale(values: lower.compactMap { $0 }, floor: floor)
        HStack(spacing: 5) {
            GeometryReader { proxy in
                ForEach(0..<5) { index in
                    let value = index < 2 ? firstScale.maximum * (1 - Double(index) / 2)
                        : index == 2 ? 0 : secondScale.maximum * Double(index - 2) / 2
                    Text(Format.speed(value))
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(index < 2 ? theme.magenta : index > 2 ? theme.accent : theme.secondary)
                        .frame(width: axisWidth, alignment: .trailing)
                        .position(x: axisWidth / 2, y: 6 + (proxy.size.height - 12) * CGFloat(index) / 4)
                }
            }
            .frame(width: axisWidth)
            Canvas { context, size in
                let middle = size.height / 2
                let half = max(1, middle - 6)
                var grid = Path()
                grid.move(to: CGPoint(x: 0, y: 0))
                grid.addLine(to: CGPoint(x: 0, y: size.height))
                for fraction in [-1.0, -0.5, 0, 0.5, 1] {
                    let y = middle + fraction * half
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(grid, with: .color(theme.secondary.opacity(0.22)), lineWidth: 0.5)
                for (values, scale, direction, color) in [(upper, firstScale.maximum, -1.0, theme.magenta),
                                                         (lower, secondScale.maximum, 1.0, theme.accent)] {
                    var line = Path()
                    var area = Path()
                    var lastPoint: CGPoint?
                    for (index, value) in values.enumerated() {
                        guard let value else { continue }
                        let x = size.width * CGFloat(index) / CGFloat(max(1, values.count - 1))
                        let normalized = value.isFinite ? min(1, max(0, value / scale)) : 0
                        let point = CGPoint(x: x, y: middle + direction * normalized * half)
                        if lastPoint == nil {
                            line.move(to: point)
                            area.move(to: CGPoint(x: x, y: middle))
                        } else { line.addLine(to: point) }
                        area.addLine(to: point)
                        lastPoint = point
                    }
                    guard let lastPoint else { continue }
                    area.addLine(to: CGPoint(x: lastPoint.x, y: middle))
                    area.closeSubpath()
                    context.fill(area, with: .color(color.opacity(0.18)))
                    context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
                }
            }
            .overlay {
                if let pointer, pointer.x >= axisWidth + 5, let history {
                    let plotPointer = CGPoint(x: pointer.x - axisWidth - 5, y: pointer.y)
                    ChartHoverOverlay(pointer: plotPointer, tooltipWidth: 143) { fraction in
                        tooltip(history.sample(at: fraction, seconds: seconds, count: History.capacity))
                    }
                }
            }
        }
        .accessibilityLabel(DeckL("上下两组曲线各用独立的纵轴刻度", "Each series uses its own vertical scale"))
    }

    private func tooltip(_ sample: TransferHistory.Sample?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let sample {
                Text(sample.date, format: .dateTime.hour().minute().second())
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                tooltipRate(firstLabel, sample.first, color: theme.magenta)
                tooltipRate(secondLabel, sample.second, color: theme.accent)
            } else {
                Text(DeckL("这一时段无样本", "No sample in this interval"))
                    .frame(maxWidth: .infinity)
            }
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .allowsHitTesting(false)
    }

    private func tooltipRate(_ label: String, _ value: Double, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).lineLimit(1)
            Spacer(minLength: 1)
            Text(Format.speed(value)).fixedSize()
        }
    }
}

struct ProcessTransferBlock: View {
    @ObservedObject var monitor: ProcessTransferMonitor
    let source: TransferSource
    let firstLabel: String
    let secondLabel: String

    @Environment(\.deckTheme) private var theme
    private let rowHeight: CGFloat = 16
    private let rowSpacing: CGFloat = 6

    var body: some View {
        DeckCard {
            VStack(alignment: .leading, spacing: rowSpacing) {
                HStack {
                    DeckTitle(DeckL("进程"))
                    Spacer(minLength: 0)
                    column(firstLabel)
                    column(secondLabel)
                }
                processRows
                    .frame(minHeight: source == .network ? CGFloat(ProcessTransfer.limit) * (rowHeight + rowSpacing) - rowSpacing : nil,
                           alignment: .topLeading)
                    .transaction { transaction in
                        if source == .network { transaction.animation = nil }
                    }
            }
        }
    }

    private var processRows: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            switch monitor.source == source ? monitor.result : .sampling {
            case .sampling:
                note(DeckL("采样中…", "Sampling…"))
            case .unavailable:
                note(DeckL("macOS 未提供进程统计", "Process statistics unavailable"))
            case .rows(let rows) where rows.isEmpty:
                note(DeckL("暂无可见进程活动", "No visible process activity"))
            case .rows(let rows):
                ForEach(rows) { row in
                    HStack(spacing: rowSpacing) {
                        if let path = row.bundlePath {
                            Image(nsImage: DeckAppIcon.image(forPath: path)).resizable().frame(width: rowHeight, height: rowHeight)
                        } else {
                            Image(systemName: "terminal").frame(width: rowHeight, height: rowHeight)
                        }
                        Text(row.name).lineLimit(1).help(row.name)
                        Spacer(minLength: 0)
                        column(Format.speed(row.first))
                        column(Format.speed(row.second))
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func note(_ message: String) -> some View {
        Text(message).font(.caption).foregroundStyle(theme.secondary)
    }

    private func column(_ value: String) -> some View {
        Text(value).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
            .frame(width: 72, alignment: .trailing)
    }

}
