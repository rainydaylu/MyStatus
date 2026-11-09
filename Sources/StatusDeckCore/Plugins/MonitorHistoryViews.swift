import StatusDeckKit
import SwiftUI

struct HistoryRangePicker: View {
    @Binding var selection: HistoryRange

    var body: some View {
        Picker(DeckL("时间范围", "Time range"), selection: $selection) {
            ForEach(HistoryRange.allCases, id: \.self) { range in
                Text(title(range)).tag(range)
            }
        }
        .labelsHidden()
        .controlSize(.small)
    }

    private func title(_ range: HistoryRange) -> String {
        switch range {
        case .oneMinute: DeckL("1 分钟", "1 minute")
        case .fiveMinutes: DeckL("5 分钟", "5 minutes")
        case .tenMinutes: DeckL("10 分钟", "10 minutes")
        case .thirtyMinutes: DeckL("30 分钟", "30 minutes")
        case .oneHour: DeckL("1 小时", "1 hour")
        case .fiveHours: DeckL("5 小时", "5 hours")
        }
    }
}

struct ChartHoverSession<Snapshot> {
    private(set) var pointer: CGPoint?
    private(set) var snapshot: Snapshot?

    mutating func move(to point: CGPoint, showing current: @autoclosure () -> Snapshot) {
        if pointer == nil { snapshot = current() }
        pointer = point
    }

    mutating func end() {
        pointer = nil
        snapshot = nil
    }
}

struct ChartHoverPosition {
    let cursor: CGFloat
    let fraction: CGFloat
    let tooltipX: CGFloat
    let tooltipWidth: CGFloat

    init(pointer: CGFloat, width: CGFloat, preferredTooltipWidth: CGFloat) {
        let gap: CGFloat = 6
        cursor = min(max(0, pointer), width)
        fraction = width > 0 ? cursor / width : 0
        let right = max(0, width - cursor - gap)
        let left = max(0, cursor - gap)
        tooltipWidth = min(preferredTooltipWidth, max(right, left))
        tooltipX = right >= preferredTooltipWidth || right >= left
            ? min(cursor + gap, width)
            : cursor - gap - tooltipWidth
    }
}

struct ChartHoverOverlay<Tooltip: View>: View {
    let pointer: CGPoint
    let tooltipWidth: CGFloat
    @ViewBuilder let tooltip: (CGFloat) -> Tooltip
    @Environment(\.deckTheme) private var theme

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let position = ChartHoverPosition(pointer: pointer.x, width: width, preferredTooltipWidth: tooltipWidth)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(theme.secondary.opacity(0.6))
                    .frame(width: 1, height: height)
                    .offset(x: min(position.cursor, max(0, width - 1)))
                tooltip(position.fraction)
                    .frame(width: position.tooltipWidth,
                           alignment: position.tooltipX >= position.cursor ? .leading : .trailing)
                    .alignmentGuide(.top) { size in
                        -min(max(0, pointer.y - size.height / 2), max(0, height - size.height))
                    }
                    .offset(x: position.tooltipX)
            }
            .frame(width: width, height: height, alignment: .topLeading)
        }
        .allowsHitTesting(false)
    }
}

struct MonitorChartSeries {
    let title: String
    let color: Color
    let format: (Double) -> String
}

struct MonitorHistoryCard<Value: Equatable>: View {
    let history: MonitorHistory<Value>
    let series: [MonitorChartSeries]
    let values: (Value) -> [Double]
    var maximum: Double? = nil
    var compact = false
    @State private var range = HistoryRange.oneMinute
    @State private var hover = ChartHoverSession<[MonitorHistory<Value>.Sample?]>()
    @Environment(\.deckTheme) private var theme

    var body: some View {
        let seconds = (compact ? HistoryRange.oneHour : range).rawValue
        let bins = hover.snapshot ?? history.bins(seconds: seconds, count: History.capacity)
        let plotted = bins.map { sample in sample.map { values($0.value) } ?? [] }
        DeckCard {
            VStack(alignment: .leading, spacing: 7) {
                if compact {
                    DeckTitle(DeckL("电量历史", "Charge history"))
                } else {
                    HistoryRangePicker(selection: $range)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                if plotted.allSatisfy(\.isEmpty) {
                    Text(DeckL("这一时段无样本", "No sample in this interval"))
                        .font(.caption)
                        .foregroundStyle(theme.secondary)
                        .frame(maxWidth: .infinity, minHeight: compact ? 48 : 146)
                } else {
                    graph(plotted)
                        .overlay {
                            if let pointer = hover.pointer {
                                ChartHoverOverlay(pointer: pointer, tooltipWidth: 158) { fraction in
                                    let index = min(bins.count - 1, Int(fraction * Double(bins.count)))
                                    tooltip(date: bins[index]?.date, values: plotted[index])
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let point): hover.move(to: point, showing: bins)
                            case .ended: hover.end()
                            }
                        }
                        .frame(height: compact ? 68 : 154)
                }
                if series.count > 1 {
                    HStack(spacing: 8) {
                        ForEach(series.indices, id: \.self) { index in
                            Label {
                                Text(series[index].title).lineLimit(1).minimumScaleFactor(0.8)
                            } icon: {
                                Circle().fill(series[index].color).frame(width: 6, height: 6)
                            }
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(theme.secondary)
                }
            }
        }
        .onChange(of: range) { _ in hover.end() }
    }

    private func graph(_ bins: [[Double]]) -> some View {
        Canvas { context, size in
            let positive = bins.map { $0.reduce(0) { $0 + max(0, $1) } }.max() ?? 0
            let negative = bins.map { $0.reduce(0) { $0 + min(0, $1) } }.min() ?? 0
            let upper = max(maximum ?? 0, positive)
            let scale = size.height / max(upper - negative, 0.001)
            let baseline = upper * scale
            if negative < 0 {
                let line = CGRect(x: 0, y: min(baseline, size.height - 1), width: size.width, height: 1)
                context.fill(Path(line), with: .color(theme.secondary.opacity(0.35)))
            }
            let stride = size.width / CGFloat(bins.count)
            for (index, readings) in bins.enumerated() {
                var top = baseline
                var bottom = baseline
                for (value, style) in zip(readings, series) {
                    let height = abs(value) * scale
                    let y: CGFloat
                    if value < 0 {
                        y = bottom
                        bottom += height
                    } else {
                        top -= height
                        y = top
                    }
                    let bar = CGRect(x: CGFloat(index) * stride, y: y, width: max(1, stride - 1), height: height)
                    context.fill(Path(bar), with: .color(style.color))
                }
            }
        }
    }

    private func tooltip(date: Date?, values: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let date, !values.isEmpty {
                Text(date, format: .dateTime.hour().minute().second())
                    .fontWeight(.semibold)
                ForEach(Array(zip(values, series)).indices, id: \.self) { index in
                    HStack {
                        Text(series[index].title).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(series[index].format(values[index])).fixedSize()
                    }
                }
            } else {
                Text(DeckL("这一时段无样本", "No sample in this interval"))
            }
        }
        .font(.caption.monospacedDigit())
        .padding(7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .allowsHitTesting(false)
    }
}

struct MemoryHistoryView: View {
    @ObservedObject var store: SystemStore
    let isPressure: Bool
    @Environment(\.deckTheme) private var theme

    var body: some View {
        if isPressure {
            MonitorHistoryCard(history: store.history.memory,
                               series: [.init(title: DeckL("压力"), color: theme.accent, format: Format.percent)],
                               values: { [$0.pressure] }, maximum: 1)
        } else {
            MonitorHistoryCard(history: store.history.memory, series: [
                bytes(DeckL("App 内存"), color: theme.accent),
                bytes(DeckL("联动内存"), color: theme.magenta),
                bytes(DeckL("已压缩"), color: theme.amber)
            ], values: { [Double($0.app), Double($0.wired), Double($0.compressed)] },
               maximum: Double(store.snapshot.memory.total))
        }
    }

    private func bytes(_ title: String, color: Color) -> MonitorChartSeries {
        .init(title: title, color: color, format: { Format.bytes(UInt64($0), binary: true) })
    }
}

struct SensorHistoryLink<Value: Equatable>: View {
    let id: String
    let title: String
    let current: Double?
    let store: SystemStore
    let source: KeyPath<History, MonitorHistory<Value>>
    let measure: (Value) -> Double?
    let format: (Double?) -> String

    var body: some View {
        if current != nil {
            PanelDrilldownLink(id: id, title: title) {
                DeckInfoRow(title, format(current))
            } detail: {
                SensorHistoryView(store: store, title: title, source: source, measure: measure, format: format)
            }
        }
    }
}

struct SensorHistoryView<Value: Equatable>: View {
    @ObservedObject var store: SystemStore
    let title: String
    let source: KeyPath<History, MonitorHistory<Value>>
    let measure: (Value) -> Double?
    let format: (Double?) -> String
    @Environment(\.deckTheme) private var theme

    var body: some View {
        MonitorHistoryCard(history: store.history[keyPath: source],
                           series: [.init(title: title, color: theme.accent, format: { format($0) })],
                           values: { value in measure(value).map { [$0] } ?? [] })
    }
}
