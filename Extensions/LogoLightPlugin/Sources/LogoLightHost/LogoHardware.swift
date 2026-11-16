import AppKit
import Darwin
import Foundation
import IOKit
import IOKit.pwr_mgt
import LogoLightCore

enum LogoPaths {
    static let id = "com.statusdeck.logolight"
    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/StatusDeck/PluginData/" + id, isDirectory: true)
    }
    static var helper: URL? {
        var location = Dl_info()
        let anchor: @convention(c) () -> Void = logoLibraryAnchor
        guard dladdr(unsafeBitCast(anchor, to: UnsafeRawPointer.self), &location) != 0,
              let name = location.dli_fname else { return nil }
        let binary = URL(fileURLWithPath: String(cString: name))
        return binary.lastPathComponent == "logo-light-helper" ? binary : binary.deletingLastPathComponent().appendingPathComponent("logo-light-helper")
    }
}

@_cdecl("statusdeck_logolight_anchor")
private func logoLibraryAnchor() {}

enum LogoProblem: Error, LocalizedError {
    case unsupported, occupied, helperUnavailable, recoveryPending, rejected, invalidCommand
    var errorDescription: String? {
        switch self {
        case .unsupported: return "当前 Mac 没有兼容的发光标志或控制接口不可用。"
        case .occupied: return "标志灯光正由其他控制程序使用，请先退出该程序。"
        case .helperUnavailable: return "无法启动灯光恢复辅助程序；未接管灯光。"
        case .recoveryPending: return "上次灯光会话尚未完成恢复，请先恢复原配置。"
        case .rejected: return "系统没有接受灯光设置，控制已停止。"
        case .invalidCommand: return "灯光命令无效。"
        }
    }
}

struct LogoRecoveryNote: Codable, Equatable {
    let token: UUID
    let owner: Int32
    let originalOn: Bool
    var closedOverride = false
    var deadline: Date?

    static func load(from directory: URL) throws -> Self {
        let file = directory.appendingPathComponent("session.json")
        let info = try FileManager.default.attributesOfItem(atPath: file.path)
        guard info[.type] as? FileAttributeType == .typeRegular,
              (info[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid(),
              ((info[.size] as? NSNumber)?.intValue ?? 0) < 4096 else { throw LogoProblem.recoveryPending }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: file))
    }
    func save(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = directory.appendingPathComponent("session.json")
        try JSONEncoder().encode(self).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    func marker(_ suffix: String, in directory: URL) -> URL { directory.appendingPathComponent(token.uuidString + suffix) }
}

@MainActor protocol LogoOutputDevice: AnyObject {
    var supported: Bool { get }
    var hasRecovery: Bool { get }
    var closed: Bool { get }
    var onFailure: ((String) -> Void)? { get set }
    func begin() async throws
    func output(_ level: Double, response: Double)
    func pause()
    func resume()
    func allowClosed(_ enabled: Bool, until deadline: Date?) throws
    func end()
    func recover() async throws
}

/// A new host/session implementation. Hardware fade mechanics come from MIT LogoLight.
@MainActor final class LogoHardware: LogoOutputDevice {
    private let directory: URL
    private let reader = LogoStatusReader()
    private let native: CoreBrightnessService?
    private let emitter: LightEmitter?
    private var child: Process?
    private var record: LogoRecoveryNote?
    private var lock: Int32 = -1
    private var worker: Task<Void, Never>?
    private var running = false
    private var suspended = false
    private var revision = 0
    private var completedRevision = -1
    private var desired = Double.nan
    private var fadeSeconds = 0.15
    private var powerAssertion: IOPMAssertionID = 0
    var onFailure: ((String) -> Void)?

    init(directory: URL = LogoPaths.folder) {
        self.directory = directory
        native = CoreBrightnessService()
        emitter = native.map { LightEmitter(service: $0, clock: { ProcessInfo.processInfo.systemUptime }) }
    }
    var supported: Bool { reader.read().isSupported && native != nil }
    var hasRecovery: Bool { FileManager.default.fileExists(atPath: directory.appendingPathComponent("session.json").path) && record == nil }
    var closed: Bool { reader.isLidClosed() ?? true }

    func begin() async throws {
        guard !running else { return }
        guard supported, let emitter, let helper = LogoPaths.helper,
              FileManager.default.isExecutableFile(atPath: helper.path) else { throw LogoProblem.unsupported }
        let names: Set<String> = ["Backlit", "Backglow", "LidPulse", "LogoLight"]
        if NSWorkspace.shared.runningApplications.contains(where: { $0.processIdentifier != getpid() && names.contains($0.localizedName ?? "") }) { throw LogoProblem.occupied }
        guard !hasRecovery else { throw LogoProblem.recoveryPending }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let descriptor = open(directory.appendingPathComponent("owner.lock").path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw LogoProblem.occupied }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { close(descriptor); throw LogoProblem.occupied }
        lock = descriptor
        let note = LogoRecoveryNote(token: UUID(), owner: getpid(), originalOn: emitter.setting != .off)
        do {
            try note.save(to: directory)
            try Data().write(to: note.marker(".alive", in: directory), options: .atomic)
            record = note
            child = try Self.launch(helper, token: note.token)
            for _ in 0..<150 {
                if FileManager.default.fileExists(atPath: note.marker(".ready", in: directory).path) { break }
                guard child?.isRunning == true else { throw LogoProblem.helperUnavailable }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            guard FileManager.default.fileExists(atPath: note.marker(".ready", in: directory).path) else { throw LogoProblem.helperUnavailable }
            guard emitter.setSetting(.on) else { throw LogoProblem.rejected }
            running = true; suspended = false; desired = .nan
        } catch { end(); throw error }
    }

    func output(_ level: Double, response: Double) {
        guard running, !suspended, record != nil else { return }
        guard child?.isRunning == true else { end(); onFailure?(LogoProblem.recoveryPending.localizedDescription); return }
        let value = LogoPreferences.clamp(level)
        guard !desired.isFinite || abs(value - desired) > 0.003 else {
            if worker == nil && completedRevision != revision { schedule() }
            return
        }
        desired = value; fadeSeconds = LogoPreferences.bound(response, 0.03...1, 0.15); revision += 1
        schedule()
    }

    private func schedule() {
        guard worker == nil, let emitter else { return }
        worker = Task { [self] in
            defer {
                worker = nil
                if running && !suspended && completedRevision != revision { schedule() }
            }
            do {
                while running && !suspended && !Task.isCancelled {
                    let current = revision
                    try await emitter.fade(following: { self.desired * self.desired }, over: fadeSeconds, sleep: { seconds in
                        try Task.checkCancellation()
                        try await Task.sleep(for: .seconds(seconds), tolerance: .milliseconds(2))
                    })
                    completedRevision = current
                    if current == revision { break }
                }
            } catch is CancellationError {} catch { end(); onFailure?(error.localizedDescription) }
        }
    }

    func pause() {
        suspended = true; worker?.cancel()
        emitter?.restore(displayAwake: false); emitter?.displayDidChange(isAwake: false)
        desired = .nan
    }
    func resume() {
        suspended = false; emitter?.displayDidChange(isAwake: !closed)
        desired = .nan
    }

    func allowClosed(_ enabled: Bool, until deadline: Date?) throws {
        guard running, var note = record else { return }
        if note.closedOverride != enabled || note.deadline != (enabled ? deadline : nil) {
            if enabled {
                // Write ownership before enabling. On disable, retain that ownership
                // until the kernel confirms handback, so failed cleanup stays repairable.
                note.closedOverride = true; note.deadline = deadline
                try note.save(to: directory); record = note
                guard LogoLidPower.setSleepDisabled(true) else { throw LogoProblem.rejected }
            } else {
                guard LogoLidPower.setSleepDisabled(false) else { throw LogoProblem.rejected }
                note.closedOverride = false; note.deadline = nil
                try note.save(to: directory); record = note
            }
            if enabled && powerAssertion == 0 {
                _ = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                    IOPMAssertionLevel(kIOPMAssertionLevelOn), "MyStatus bounded logo light session" as CFString, &powerAssertion)
            } else if !enabled && powerAssertion != 0 {
                IOPMAssertionRelease(powerAssertion); powerAssertion = 0
            }
        }
        if enabled {
            guard child?.isRunning == true else { throw LogoProblem.helperUnavailable }
            if closed && emitter?.isLidOverridden != true { emitter?.overrideLid() }
        } else {
            if emitter?.isLidOverridden == true { emitter?.endLidOverride() }
        }
    }

    func end() {
        running = false; suspended = true; worker?.cancel()
        if powerAssertion != 0 { IOPMAssertionRelease(powerAssertion); powerAssertion = 0 }
        if let note = record {
            try? FileManager.default.removeItem(at: note.marker(".alive", in: directory))
            record = nil
        }
        if lock >= 0 { _ = flock(lock, LOCK_UN); close(lock); lock = -1 }
        // The acknowledged unprivileged helper performs native handback even if
        // MyStatus's termination leaves no time for async work on the main actor.
    }

    func recover() async throws {
        guard !running, let helper = LogoPaths.helper else { throw LogoProblem.recoveryPending }
        let note = try LogoRecoveryNote.load(from: directory)
        let lease = note.marker(".alive", in: directory)
        guard !FileManager.default.fileExists(atPath: lease.path) || kill(note.owner, 0) != 0 else { throw LogoProblem.occupied }
        let process = try Self.launch(helper, token: note.token)
        for _ in 0..<250 {
            if !process.isRunning { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard !hasRecovery else { throw LogoProblem.recoveryPending }
    }

    private static func launch(_ helper: URL, token: UUID) throws -> Process {
        let process = Process(); process.executableURL = helper
        process.arguments = ["--recover", token.uuidString]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run(); return process
    }
}

@MainActor enum LogoRecoveryWorker {
    static func run(token: UUID, directory: URL = LogoPaths.folder) async -> Int32 {
        do {
            let note = try LogoRecoveryNote.load(from: directory)
            guard note.token == token else { return 2 }
            guard let service = CoreBrightnessService() else {
                if note.closedOverride { _ = LogoLidPower.setSleepDisabled(false) }
                return 2
            }
            let emitter = LightEmitter(service: service, clock: { ProcessInfo.processInfo.systemUptime })
            // One helper at a time, including an explicit repair racing with normal cleanup.
            let fd = open(directory.appendingPathComponent("restore.lock").path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
            guard fd >= 0 else { return 2 }
            defer { close(fd) }
            guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { return 0 }
            defer { _ = flock(fd, LOCK_UN) }
            try Data().write(to: note.marker(".ready", in: directory), options: .atomic)
            while FileManager.default.fileExists(atPath: note.marker(".alive", in: directory).path) && kill(note.owner, 0) == 0 {
                let current = try LogoRecoveryNote.load(from: directory)
                guard current.token == token else { return 2 }
                if current.closedOverride, let deadline = current.deadline, Date() >= deadline { break }
                if current.closedOverride && (Battery.powerState()?.isPluggedIn != true || ProcessInfo.processInfo.isLowPowerModeEnabled || ProcessInfo.processInfo.thermalState == .critical || ProcessInfo.processInfo.thermalState == .serious) { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            try await Task.sleep(nanoseconds: 60_000_000)
            let last = try LogoRecoveryNote.load(from: directory)
            guard last.token == token else { return 2 }
            if last.closedOverride, !LogoLidPower.setSleepDisabled(false) { return 3 }
            emitter.endLidOverride()
            let awake = LogoStatusReader().isBuiltInDisplayAwakeForRecovery
            emitter.restore(displayAwake: awake)
            guard emitter.setSetting(note.originalOn ? .on : .off), emitter.setting == (note.originalOn ? .on : .off) else { return 3 }
            try FileManager.default.removeItem(at: directory.appendingPathComponent("session.json"))
            for suffix in [".ready", ".alive"] { try? FileManager.default.removeItem(at: note.marker(suffix, in: directory)) }
            return 0
        } catch { return 3 }
    }
}

private extension LogoStatusReader {
    var isBuiltInDisplayAwakeForRecovery: Bool { isLidClosed() == false && isDisplayAwake() == true }
}
