import AppKit
import Combine
import Darwin
import StatusDeckKit

struct FanTarget: Decodable, Identifiable, Sendable {
    let id: Int
    let name: String
    let currentSpeed: Int?
    let minSpeed: Int
    let maxSpeed: Int
    let targetSpeed: Int
    let mode: Int

    var bounds: ClosedRange<Int>? {
        guard minSpeed > 0, maxSpeed > minSpeed, maxSpeed <= 20_000 else { return nil }
        return minSpeed...maxSpeed
    }

    var isManual: Bool { mode == 1 }

    func clamp(_ rpm: Int) -> Int? {
        bounds.map { min($0.upperBound, max($0.lowerBound, rpm)) }
    }
}

/// The bundled fan helper is installed only after explicit administrator approval.
@MainActor
final class FanController: ObservableObject {
    @Published private(set) var targets: [FanTarget] = []
    @Published private(set) var isBusy = false
    @Published private(set) var message: String?
    private let queue = DispatchQueue(label: "statusdeck.fan", qos: .utility)
    let authorization: SystemControlAuthorization
    @Published private(set) var didReadFans = false
    private var isReading = false
    private var owned: [Int: String] = [:]
    private var thermalObserver: AnyCancellable?

    init(authorization: SystemControlAuthorization) {
        self.authorization = authorization
        thermalObserver = NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    if ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue {
                        self?.restoreOwnedFans()
                    }
                }
            }
    }

    func refresh() {
        guard !isReading, !isBusy else { return }
        let path = authorization.isAuthorized ? authorization.helperPath : authorization.bundledHelper?.path
        isReading = true
        queue.async { [weak self] in
            let targets = path.flatMap(Self.read) ?? Self.readWithoutHelper()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isReading = false
                    self.didReadFans = targets != nil
                    self.targets = targets ?? []
                }
            }
        }
    }

    private nonisolated static func readWithoutHelper() -> [FanTarget]? {
        guard let smc = SMCClient(), let count = smc.read("FNum"), count.isFinite, (0...8).contains(count) else { return nil }
        func integer(_ value: Double?) -> Int? {
            guard let value, value.isFinite, (0...65_535).contains(value) else { return nil }
            return Int(value.rounded())
        }
        return (0..<Int(count)).map { id in
            let key = "F\(id)"
            return FanTarget(id: id, name: "Fan \(id + 1)",
                             currentSpeed: integer(smc.read(key + "Ac")),
                             minSpeed: integer(smc.read(key + "Mn")) ?? 0,
                             maxSpeed: integer(smc.read(key + "Mx")) ?? 0,
                             targetSpeed: integer(smc.read(key + "Tg")) ?? 0,
                             mode: integer(smc.read(key + "md") ?? smc.read(key + "Md")) ?? -1)
        }
    }

    func apply(_ fan: FanTarget, rpm: Int) {
        guard !isBusy, let speed = fan.clamp(rpm) else { return }
        withAuthorization { [weak self] in
            guard let self else { return }
            guard ProcessInfo.processInfo.thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue else {
                self.message = DeckL("当前温度较高，风扇交由系统管理。", "The system manages the fans while thermal pressure is high.")
                return
            }
            self.owned[fan.id] = self.authorization.helperPath
            self.command(fanID: fan.id, speed: speed)
        }
    }

    func automatic(_ fan: FanTarget) {
        guard !isBusy else { return }
        withAuthorization { [weak self] in self?.command(fanID: fan.id, speed: nil) }
    }

    func authorizeAndRefresh() {
        guard !isBusy else { return }
        withAuthorization { [weak self] in self?.refresh() }
    }

    private func withAuthorization(_ operation: @escaping () -> Void) {
        isBusy = true
        authorization.authorize { [weak self] authorized in
            guard let self else { return }
            self.isBusy = false
            if authorized { operation() }
            else { self.message = self.authorization.error }
        }
    }

    private func command(fanID: Int, speed: Int?) {
        let path = authorization.helperPath
        isBusy = true
        queue.async { [weak self] in
            var ok = Self.set(path, fanID: fanID, speed: speed)
            var updated = Self.read(path)
            if let speed {
                ok = ok && updated?.contains { $0.id == fanID && $0.isManual && abs($0.targetSpeed - speed) < 30 } == true
            } else {
                ok = ok && updated?.contains { $0.id == fanID && !$0.isManual } == true
            }
            // A failed speed write can leave the mode in manual.
            let restored = !ok && speed != nil && Self.set(path, fanID: fanID, speed: nil)
            if restored { updated = Self.read(path) }
            let result = (ok, restored, updated)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isBusy = false
                    if let targets = result.2 { self.targets = targets }
                    if result.1 || (result.0 && speed == nil) { self.owned.removeValue(forKey: fanID) }
                    self.message = result.0 ? nil : DeckL("风扇未确认目标转速，请检查辅助程序和机型支持。", "The fan did not confirm the target. Check helper authorization and model support.")
                }
            }
        }
    }

    /// Flush writes before returning the fans owned by this session to macOS.
    func restoreOwnedFans() {
        let pending = owned
        guard !pending.isEmpty else { return }
        let failed = queue.sync {
            pending.filter { !Self.set($0.value, fanID: $0.key, speed: nil) }
        }
        owned = failed
        if !failed.isEmpty {
            message = DeckL("有风扇未能恢复自动，请在传感器设置中重试。", "Some fans did not return to Auto. Retry in Sensors settings.")
        } else {
            targets = []
        }
    }

    private struct Status: Decodable { let fans: [FanTarget] }

    private nonisolated static func read(_ path: String) -> [FanTarget]? {
        guard let output = Subprocess.output(path, ["get"], timeout: 5) else { return nil }
        return try? JSONDecoder().decode(Status.self, from: output).fans
    }

    private nonisolated static func set(_ path: String, fanID: Int, speed: Int?) -> Bool {
        let args = speed.map { ["set", String(fanID), "1", String($0)] } ?? ["set", String(fanID), "0"]
        guard let output = SystemControlAuthorization.run(path, args, timeout: 18),
              let text = String(data: output, encoding: .utf8) else { return false }
        return text.split(whereSeparator: \.isNewline).contains { $0.hasPrefix("SUCCESS:") }
    }
}
