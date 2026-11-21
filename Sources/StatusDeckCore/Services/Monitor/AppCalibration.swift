import Foundation

enum BatteryCalibrationMethod: String, CaseIterable, Sendable {
    case global, perApp
    static let key = "battery.calibration.method"
    static var current: Self { Self(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .global }
}

struct AppCalibrationSample: Codable {
    struct Feature: Codable { let name: String; let rate: Double }
    let start: Double
    let end: Double
    let apps: [String: Feature]
}

struct AppCalibrationModel: Codable, Equatable, Sendable {
    struct Coefficient: Codable, Equatable, Sendable { let name: String; let factor: Double }
    let coefficients: [String: Coefficient]
    let backgroundRate: Double
    let fittedAt: Date
    let trainingCount: Int
    let validationCount: Int
    let baselineRMSE: Double
    let fittedRMSE: Double
}

/// A small bounded linear fit: shared background + sum(app rate * app factor).
/// A weak ridge penalty shrinks factors toward 1. No external runtime or training
/// job. Correlated apps stay at 1; an unseen final fifth must improve before use.
enum AppCalibrationFit {
    struct Row { let time: Double; let actualRate: Double; let apps: [String: AppCalibrationSample.Feature] }
    static let minimumRows = 50

    static func rows(samples: [AppCalibrationSample], battery: [BatteryObservation]) -> [Row] {
        let points = battery.sorted { $0.time < $1.time }
        func gauge(_ time: Double) -> Double? {
            var low = 0, high = points.count
            while low < high {
                let middle = (low + high) / 2
                if points[middle].time < time { low = middle + 1 } else { high = middle }
            }
            if low < points.count, abs(points[low].time - time) < 0.001 {
                let p = points[low]
                return !p.external && !p.charging ? p.measuredPercent : nil
            }
            guard low > 0, low < points.count else { return nil }
            let a = points[low - 1], b = points[low]
            guard !a.external, !b.external, !a.charging, !b.charging,
                  (0.001...125).contains(b.time - a.time), abs(a.measuredPercent - b.measuredPercent) <= 5 else { return nil }
            return a.measuredPercent + (b.measuredPercent - a.measuredPercent) * (time - a.time) / (b.time - a.time)
        }
        return samples.sorted { $0.end < $1.end }.compactMap { sample in
            guard (55...75).contains(sample.end - sample.start),
                  sample.apps.count <= 256, !sample.apps.isEmpty,
                  sample.apps.values.allSatisfy({ $0.rate.isFinite && (0...1_000).contains($0.rate) }),
                  let a = gauge(sample.start), let b = gauge(sample.end), abs(a - b) <= 5,
                  !points.contains(where: { $0.time > sample.start && $0.time < sample.end && ($0.external || $0.charging) }) else { return nil }
            let rate = (a - b) / (sample.end - sample.start) * 3_600
            guard rate.isFinite, abs(rate) <= 200 else { return nil }
            return Row(time: sample.end, actualRate: rate, apps: sample.apps)
        }
    }

    static func fit(_ rows: [Row], previous: AppCalibrationModel? = nil, at date: Date) -> AppCalibrationModel? {
        let ordered = rows.sorted { $0.time < $1.time }
        guard ordered.count >= minimumRows else { return nil }
        let cut = ordered.count * 4 / 5
        let train = Array(ordered.prefix(cut)), check = Array(ordered.dropFirst(cut))
        let paths = Set(train.flatMap { $0.apps.keys })
        func values(_ path: String) -> [Double] { train.map { $0.apps[path]?.rate ?? 0 } }
        func mean(_ x: [Double]) -> Double { x.reduce(0, +) / Double(x.count) }
        func variance(_ x: [Double]) -> Double { let m = mean(x); return x.reduce(0) { $0 + ($1 - m) * ($1 - m) } }
        var eligible = paths.filter { path in
            let x = values(path)
            return x.filter { $0 >= 0.05 }.count >= 15 && variance(x) / Double(x.count) >= 0.01
        }.sorted { values($0).reduce(0, +) > values($1).reduce(0, +) }
        eligible = Array(eligible.prefix(32))
        // Do not assign independent coefficients to apps that always move together.
        var ambiguous: Set<String> = []
        for i in eligible.indices {
            for j in eligible.indices where j > i {
                let x = values(eligible[i]), z = values(eligible[j]), mx = mean(x), mz = mean(z)
                let covariance = zip(x, z).reduce(0.0) { $0 + ($1.0 - mx) * ($1.1 - mz) }
                let correlation = covariance / sqrt(variance(x) * variance(z))
                if abs(correlation) >= 0.95 { ambiguous.insert(eligible[i]); ambiguous.insert(eligible[j]) }
            }
        }
        eligible.removeAll { ambiguous.contains($0) }
        let selected = Array(eligible.prefix(16))
        guard !selected.isEmpty else { return nil }
        let x = train.map { row in selected.map { row.apps[$0]?.rate ?? 0 } }
        let y = train.map { row in
            row.actualRate - row.apps.filter { !selected.contains($0.key) }.values.reduce(0) { $0 + $1.rate }
        }
        var factors = Array(repeating: 1.0, count: selected.count)
        var background = max(0, mean(zip(y, x).map { $0.0 - $0.1.reduce(0, +) }))
        let penalties = selected.map { max(0.001, variance(values($0)) * 0.05) }
        for _ in 0..<80 {
            background = max(0, mean(train.indices.map { i in y[i] - zip(x[i], factors).reduce(0) { $0 + $1.0 * $1.1 } }))
            for j in selected.indices {
                var numerator = penalties[j], denominator = penalties[j]
                for i in train.indices {
                    let other = zip(x[i].indices, x[i]).reduce(0.0) { $0 + ($1.0 == j ? 0 : $1.1 * factors[$1.0]) }
                    numerator += x[i][j] * (y[i] - background - other)
                    denominator += x[i][j] * x[i][j]
                }
                factors[j] = min(1.5, max(0.5, numerator / denominator))
            }
        }
        func prediction(_ row: Row, _ coefficients: [String: Double]) -> Double {
            row.apps.reduce(0) { $0 + $1.value.rate * (coefficients[$1.key] ?? 1) }
        }
        func error(_ coefficients: [String: Double], background: Double) -> Double {
            sqrt(check.reduce(0) { $0 + pow($1.actualRate - background - prediction($1, coefficients), 2) } / Double(check.count))
        }
        let coefficients = Dictionary(uniqueKeysWithValues: zip(selected, factors))
        let baseBackground = max(0, mean(train.map { $0.actualRate - prediction($0, [:]) }))
        let before = error([:], background: baseBackground), after = error(coefficients, background: background)
        guard before.isFinite, after.isFinite, before > 0.01, after <= before * 0.95 else { return nil }
        if let previous {
            let old = previous.coefficients.mapValues(\.factor)
            let oldBackground = max(0, mean(train.map { $0.actualRate - prediction($0, old) }))
            guard after <= error(old, background: oldBackground) * 0.98 else { return nil }
        }
        let learned = Dictionary(uniqueKeysWithValues: zip(selected, factors).map { path, factor in
            (path, AppCalibrationModel.Coefficient(name: train.compactMap { $0.apps[path]?.name }.first ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent, factor: factor))
        })
        return AppCalibrationModel(coefficients: learned, backgroundRate: background, fittedAt: date,
                                   trainingCount: train.count, validationCount: check.count,
                                   baselineRMSE: before, fittedRMSE: after)
    }
}
