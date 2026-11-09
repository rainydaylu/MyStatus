import StatusDeckKit
import SwiftUI

struct TransferActivityCard: View {
    private typealias Chart = (history: TransferHistory, bars: (first: [Double], second: [Double]))

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
        let shown: Chart = hover.snapshot ?? (history, history.bins(seconds: seconds, count: History.capacity))
        let chart = shown.bars
        DeckCard {
            VStack(spacing: 9) {
                HStack {
                    DeckTitle(title)
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
                        .frame(height: 146)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let point): hover.move(to: point, showing: shown)
                            case .ended: hover.end()
                            }
                        }
                } else {
                    DeckMirrorGraph(upper: chart.first, lower: chart.second, floor: floor, capacity: History.capacity)
                        .frame(height: 76)
                }
                HStack {
                    Text(DeckL("峰值", "Peak"))
                    Spacer()
                    Text(Format.speed(chart.first.max() ?? 0)).foregroundStyle(theme.magenta)
                    Text(Format.speed(chart.second.max() ?? 0)).foregroundStyle(theme.accent)
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
    let upper: [Double]
    let lower: [Double]
    let pointer: CGPoint?
    @Environment(\.deckTheme) private var theme

    var body: some View {
        DeckMirrorGraph(upper: upper, lower: lower, floor: floor, capacity: History.capacity)
            .overlay {
                if let pointer {
                    ChartHoverOverlay(pointer: pointer, tooltipWidth: 143) { fraction in
                        tooltip(history.sample(at: fraction, seconds: seconds, count: History.capacity))
                    }
                }
            }
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
