import StatusDeckKit
import SwiftUI

struct TransferActivityCard: View {
    let title: String
    let firstLabel: String
    let secondLabel: String
    let first: Double
    let second: Double
    let history: TransferHistory
    let floor: Double

    @State private var seconds = 60
    @Environment(\.deckTheme) private var theme

    var body: some View {
        let chart = history.bins(seconds: seconds, count: History.capacity)
        DeckCard {
            VStack(spacing: 9) {
                HStack {
                    DeckTitle(title)
                    Spacer()
                    Picker(DeckL("时间范围", "Time range"), selection: $seconds) {
                        Text(DeckL("1 分钟", "1 minute")).tag(60)
                        Text(DeckL("5 分钟", "5 minutes")).tag(300)
                        Text(DeckL("1 小时", "1 hour")).tag(3600)
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                }
                HStack(spacing: 8) {
                    DeckStat(Format.speed(first), label: firstLabel, color: theme.magenta)
                    DeckStat(Format.speed(second), label: secondLabel, color: theme.accent)
                }
                DeckMirrorGraph(upper: chart.first, lower: chart.second, floor: floor, capacity: History.capacity)
                    .frame(height: 76)
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
    }
}

struct ProcessTransferBlock: View {
    let source: TransferSource
    let firstLabel: String
    let secondLabel: String

    @State private var rows: [ProcessTransfer] = []
    @State private var status = DeckL("采样中…", "Sampling…")
    @Environment(\.deckTheme) private var theme

    var body: some View {
        DeckCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    DeckTitle(DeckL("进程"))
                    Spacer(minLength: 0)
                    column(firstLabel)
                    column(secondLabel)
                }
                if rows.isEmpty {
                    Text(status).font(.caption).foregroundStyle(theme.secondary)
                }
                ForEach(rows) { row in
                    HStack(spacing: 6) {
                        Text(row.name).lineLimit(1).help(row.name)
                        Spacer(minLength: 0)
                        column(Format.speed(row.first))
                        column(Format.speed(row.second))
                    }
                    .font(.caption)
                }
            }
        }
        .task { await poll() }
    }

    private func column(_ value: String) -> some View {
        Text(value).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
            .frame(width: 72, alignment: .trailing)
    }

    private func poll() async {
        var reader = TransferRateReader()
        var hasBaseline = false
        while !Task.isCancelled {
            let counters = await Task.detached(priority: .utility) { [source] in source.counters() }.value
            guard !Task.isCancelled else { return }
            if let counters {
                rows = reader.read(counters, at: ProcessInfo.processInfo.systemUptime)
                if hasBaseline { status = DeckL("暂无可见进程活动", "No visible process activity") }
                hasBaseline = true
            } else {
                rows = []
                reader = TransferRateReader()
                hasBaseline = false
                status = DeckL("macOS 未提供进程统计", "Process statistics unavailable")
            }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
        }
    }
}
