import Foundation

enum HistoryRange: Int, CaseIterable {
    case oneMinute = 60
    case fiveMinutes = 300
    case tenMinutes = 600
    case thirtyMinutes = 1_800
    case oneHour = 3_600
    case fiveHours = 18_000

    static func prune<Sample>(_ samples: inout [Sample], at time: TimeInterval, timestamp: KeyPath<Sample, TimeInterval>) {
        // The fastest regular sampling interval is one second. Leave space for
        // extra event-driven samples and trim in batches to avoid shifting the array every second.
        let batch = 512
        let limit = fiveHours.rawValue + 4 * batch
        let cutoff = time - Double(fiveHours.rawValue)
        let expired = samples.count >= batch && samples[batch - 1][keyPath: timestamp] < cutoff
            ? samples.prefix(while: { $0[keyPath: timestamp] < cutoff }).count : 0
        let overflow = samples.count > limit + batch ? samples.count - limit : 0
        let remove = max(expired, overflow)
        if remove > 0 { samples.removeFirst(remove) }
    }
}

/// The latest actual sample in each time slot. Missing intervals stay empty.
struct MonitorHistory<Value: Equatable>: Equatable {
    struct Sample: Equatable {
        let time: TimeInterval
        let date: Date
        let value: Value
    }

    private var samples: [Sample] = []

    mutating func append(_ value: Value, at time: TimeInterval, date: Date) {
        samples.append(Sample(time: time, date: date, value: value))
        HistoryRange.prune(&samples, at: time, timestamp: \.time)
    }

    func bins(seconds: Int, count: Int, endingAt end: TimeInterval? = nil) -> [Sample?] {
        guard seconds > 0, count > 0 else { return [] }
        var bins = [Sample?](repeating: nil, count: count)
        guard let end = end ?? samples.last?.time else { return bins }
        let start = end - Double(seconds)
        for sample in samples.reversed().prefix(while: { $0.time >= start }) where sample.time <= end {
            let index = min(count - 1, Int((sample.time - start) / Double(seconds) * Double(count)))
            if bins[index] == nil { bins[index] = sample }
        }
        return bins
    }
}
