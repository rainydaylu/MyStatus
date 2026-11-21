import Foundation

enum BatteryCalibrationPreference {
    static let key = "battery.calibration.enabled"
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }
}

/// Observed charge and battery-terminal power, not an app-attribution guess.
struct BatteryObservation {
    let time: TimeInterval
    let external: Bool
    let charging: Bool
    let displayedPercent: Int
    let measuredPercent: Double
    let currentMAH: Int?
    let fullMAH: Int?
    let volts: Double?
    let amps: Double?
    let watts: Double?
    let baselinePercentPerHour: Double?

    init(battery: BatteryStats, at date: Date) {
        time = date.timeIntervalSince1970
        external = battery.isExternalPowerConnected
        charging = battery.isCharging
        displayedPercent = battery.percent
        measuredPercent = battery.measuredPercent
        currentMAH = battery.currentChargeCapacity
        fullMAH = battery.rawFullChargeCapacity
        volts = battery.volts
        amps = battery.amps
        watts = battery.watts
        if let watts = battery.watts, let capacity = battery.estimatedFullChargeWattHours,
           watts.isFinite, (-1_000..<0).contains(watts) {
            // Deliberately uncalibrated: never fit against our previous output.
            baselinePercentPerHour = -watts / capacity * 100
        } else { baselinePercentPerHour = nil }
    }

    static let csvHeader = "unix_seconds,external_power,charging,displayed_percent,gauge_percent,current_mAh,full_mAh,volts,amps,battery_watts,baseline_pct_per_hour\n"
    var csv: String {
        func number<T>(_ value: T?) -> String { value.map { String(describing: $0) } ?? "" }
        return [String(time), external ? "1" : "0", charging ? "1" : "0", String(displayedPercent),
                String(measuredPercent), number(currentMAH), number(fullMAH), number(volts), number(amps),
                number(watts), number(baselinePercentPerHour)].joined(separator: ",") + "\n"
    }

    init?(csv: Substring) {
        let p = csv.split(separator: ",", omittingEmptySubsequences: false)
        guard p.count == 11, let time = Double(p[0]), let percent = Int(p[3]), let measured = Double(p[4]),
              time.isFinite, measured.isFinite, (0...100).contains(measured) else { return nil }
        self.time = time; external = p[1] == "1"; charging = p[2] == "1"
        displayedPercent = percent; measuredPercent = measured
        currentMAH = Int(p[5]); fullMAH = Int(p[6]); volts = Double(p[7]); amps = Double(p[8])
        watts = Double(p[9]); baselinePercentPerHour = Double(p[10])
    }
}

/// The entire model is one proportional coefficient: actual drop / baseline drop.
enum BatteryProportionFit {
    struct Result { let factor: Double; let seconds: Double; let actual: Double; let predicted: Double }
    struct Evidence: Equatable, Sendable {
        var seconds = 0.0
        var actual = 0.0
        var predicted = 0.0
        var intervalCount = 0

        var result: Result? {
            guard seconds >= 900, actual >= 3, predicted >= 1 else { return nil }
            let factor = actual / predicted
            guard factor.isFinite, (0.5...1.5).contains(factor) else { return nil }
            return Result(factor: factor, seconds: seconds, actual: actual, predicted: predicted)
        }

        /// Minimum-data progress, not a confidence or accuracy score.
        var progress: Double { max(0, min(1, min(seconds / 900, min(actual / 3, predicted)))) }
    }

    static func fit(_ observations: [BatteryObservation]) -> Result? {
        evidence(observations).result
    }

    static func evidence(_ observations: [BatteryObservation]) -> Evidence {
        let points = observations.sorted { $0.time < $1.time }
        var result = Evidence()
        for (a, b) in zip(points, points.dropFirst()) {
            let dt = b.time - a.time
            guard (10...120).contains(dt), !a.external, !b.external, !a.charging, !b.charging,
                  let x = a.baselinePercentPerHour, let y = b.baselinePercentPerHour,
                  x.isFinite, y.isFinite, x > 0, y > 0 else { continue }
            let drop = a.measuredPercent - b.measuredPercent
            guard abs(drop) <= 5 else { continue } // reject gauge jumps; never clip small increases to zero
            result.seconds += dt
            result.actual += drop
            result.predicted += (x + y) / 2 * dt / 3_600
            result.intervalCount += 1
        }
        return result
    }
}

struct BatteryCalibrationStatus: Equatable, Sendable {
    var model = BatteryLearningStore.Model()
    var evidence = BatteryProportionFit.Evidence()
    var recordCount = 0
    var lastRecordedAt: Date?
    var appWindowCount = 0
}

/// Reuses existing battery samples. CSV rows are buffered for five minutes;
/// power transitions and day changes flush them. A daily fit uses the previous
/// seven complete days; insufficient data leaves the coefficient unchanged.
final class BatteryLearningStore {
    struct Model: Codable, Equatable, Sendable {
        var factor = 1.0
        var previousFactor = 1.0
        var attemptedDay: String?
        var fittedAt: Date?
        var observedDrop = 0.0
        var predictedDrop = 0.0
        var usableSeconds = 0.0
        var perApp: AppCalibrationModel?
    }
    let folder: URL
    private(set) var model: Model
    private(set) var isEnabled: Bool
    private let calendar: Calendar
    private var lastPoint: BatteryObservation?
    private var pending: [String: String] = [:]
    private var pendingCount = 0
    private var pendingApps: [String: String] = [:]
    private var lastAppRecordedAt: Date?

    static var standardFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("StatusDeck/BatteryHistory", isDirectory: true)
    }

    init(folder: URL = BatteryLearningStore.standardFolder, calendar: Calendar = .current,
         enabled: Bool = BatteryCalibrationPreference.isEnabled()) {
        self.folder = folder
        self.calendar = calendar
        self.isEnabled = enabled
        let file = folder.appendingPathComponent("calibration.json")
        if let data = try? Data(contentsOf: file), let loaded = try? JSONDecoder().decode(Model.self, from: data),
           loaded.factor.isFinite, (0.5...1.5).contains(loaded.factor) {
            model = loaded
        } else { model = Model() }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        flush()
        isEnabled = enabled
        lastPoint = nil
    }

    var appliedFactor: Double { isEnabled ? model.factor : 1 }

    func recordAppEnergy(_ energy: AppEnergyStats, battery: BatteryStats, at now: Date = Date()) {
        guard isEnabled, energy.state == .ready, let date = energy.sampledAt,
              (0...5).contains(now.timeIntervalSince(date)), date != lastAppRecordedAt,
              (55...75).contains(energy.seconds), let entries = energy.allEntries, !entries.isEmpty, entries.count <= 256,
              let capacity = battery.estimatedFullChargeWattHours else { return }
        let features = entries.reduce(into: [String: AppCalibrationSample.Feature]()) { result, entry in
            let rate = entry.watts / capacity * 100
            if rate.isFinite, (0...1_000).contains(rate) {
                result[entry.bundlePath] = .init(name: entry.name, rate: rate)
            }
        }
        let sample = AppCalibrationSample(start: date.timeIntervalSince1970 - energy.seconds,
                                          end: date.timeIntervalSince1970, apps: features)
        guard let data = try? JSONEncoder().encode(sample), let line = String(data: data, encoding: .utf8) else { return }
        pendingApps[dayKey(date), default: ""] += line + "\n"
        lastAppRecordedAt = date
    }

    func observe(_ battery: BatteryStats, at date: Date = Date()) {
        guard isEnabled, battery.isPresent else { return }
        let point = BatteryObservation(battery: battery, at: date)
        let changedPower = lastPoint.map { $0.external != point.external || $0.charging != point.charging } ?? true
        let changedDay = lastPoint.map { dayKey(Date(timeIntervalSince1970: $0.time)) != dayKey(date) } ?? true
        // A little scheduling tolerance prevents 59.99 s from becoming a two-minute gap.
        if let last = lastPoint, point.time >= last.time, point.time - last.time < 59, !changedPower, !changedDay { return }
        let day = dayKey(date)
        pending[day, default: ""] += point.csv
        pendingCount += 1
        lastPoint = point
        if pendingCount >= 5 || changedPower || changedDay { flush() }
        if model.attemptedDay != day { calibrate(at: date) }
    }

    /// Read only while the settings page is visible. Includes buffered rows and
    /// today's data, so progress describes the next daily calibration window.
    func status(at date: Date = Date()) -> BatteryCalibrationStatus {
        let points = observations(at: date, offsets: 0...6)
        return BatteryCalibrationStatus(model: model, evidence: BatteryProportionFit.evidence(points),
                                        recordCount: points.count,
                                        lastRecordedAt: points.map(\.time).max().map(Date.init(timeIntervalSince1970:)),
                                        appWindowCount: AppCalibrationFit.rows(samples: appSamples(at: date, offsets: 0...6), battery: points).count)
    }

    func flush() {
        guard !pending.isEmpty || !pendingApps.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            for (day, rows) in pending {
                let file = folder.appendingPathComponent("battery-\(day).csv")
                if !FileManager.default.fileExists(atPath: file.path) {
                    FileManager.default.createFile(atPath: file.path, contents: Data(BatteryObservation.csvHeader.utf8), attributes: [.posixPermissions: 0o600])
                }
                let handle = try FileHandle(forWritingTo: file)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(rows.utf8))
            }
            for (day, rows) in pendingApps {
                let file = folder.appendingPathComponent("apps-\(day).jsonl")
                if !FileManager.default.fileExists(atPath: file.path) {
                    FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
                }
                let handle = try FileHandle(forWritingTo: file)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(rows.utf8))
            }
            pending = [:]; pendingApps = [:]; pendingCount = 0
        } catch { /* Sampling continues in memory if local storage is unavailable. */ }
    }

    private func calibrate(at date: Date) {
        flush()
        let points = observations(at: date, offsets: 1...7)
        if let result = BatteryProportionFit.fit(points) {
            model.previousFactor = model.factor
            model.factor = result.factor
            model.fittedAt = date
            model.observedDrop = result.actual
            model.predictedDrop = result.predicted
            model.usableSeconds = result.seconds
        }
        let rows = AppCalibrationFit.rows(samples: appSamples(at: date, offsets: 1...7), battery: points)
        if let fitted = AppCalibrationFit.fit(rows, previous: model.perApp, at: date) { model.perApp = fitted }
        model.attemptedDay = dayKey(date)
        if let data = try? JSONEncoder().encode(model) {
            let file = folder.appendingPathComponent("calibration.json")
            try? data.write(to: file, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
    }

    private func appSamples(at date: Date, offsets: ClosedRange<Int>) -> [AppCalibrationSample] {
        var samples: [AppCalibrationSample] = []
        let today = calendar.startOfDay(for: date)
        for offset in offsets {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = dayKey(day)
            let text = ((try? String(contentsOf: folder.appendingPathComponent("apps-\(key).jsonl"), encoding: .utf8)) ?? "") + (pendingApps[key] ?? "")
            samples += text.split(separator: "\n").compactMap {
                try? JSONDecoder().decode(AppCalibrationSample.self, from: Data($0.utf8))
            }.filter { $0.start.isFinite && $0.end.isFinite }
        }
        return Array(Dictionary(samples.map { ($0.end, $0) }, uniquingKeysWith: { first, _ in first }).values)
    }

    private func observations(at date: Date, offsets: ClosedRange<Int>) -> [BatteryObservation] {
        let day = calendar.startOfDay(for: date)
        var points: [BatteryObservation] = []
        for offset in offsets {
            guard let prior = calendar.date(byAdding: .day, value: -offset, to: day) else { continue }
            let key = dayKey(prior)
            let file = folder.appendingPathComponent("battery-\(key).csv")
            if let text = try? String(contentsOf: file, encoding: .utf8) {
                points += text.split(separator: "\n").dropFirst().compactMap(BatteryObservation.init(csv:))
            }
            if let rows = pending[key] {
                points += rows.split(separator: "\n").compactMap(BatteryObservation.init(csv:))
            }
        }
        return points
    }

    private func dayKey(_ date: Date) -> String {
        let p = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", p.year ?? 0, p.month ?? 0, p.day ?? 0)
    }
}
