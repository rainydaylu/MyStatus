import AppKit
import Combine
import Foundation
import LogoLightCore
import StatusDeckKit
import SwiftUI

@MainActor final class LogoRuntime: ObservableObject {
    @Published var settings: LogoPreferences { didSet { changed(previous: oldValue) } }
    @Published private(set) var supported: Bool
    @Published private(set) var active = false
    @Published private(set) var connecting = false
    @Published private(set) var output = 0.0
    @Published private(set) var inputStatus = ""
    @Published private(set) var agent = CodingLightState.idle
    @Published private(set) var sessions = 0
    @Published var error: String?
    private let device: any LogoOutputDevice
    private let defaults: PluginDefaults
    private let inputs = LogoInputs()
    private let sound: SoundLevelSource?
    private weak var host: (any DeckHost)?
    private var timer: Timer?
    private(set) var pollingInterval: TimeInterval = 1
    private var batteryObserver: BatteryObserver?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var agentObserver: NSObjectProtocol?
    private var keys: [any DeckHotKeyToken] = []
    private var audioStarted = false
    private var audioAttempted = false
    private var configuredInput: LogoMode?
    private var paused = false
    private var pauseReasons: Set<LogoPauseReason> = []
    private var lidPaused = false
    private var lockObservers: [NSObjectProtocol] = []
    private var stopped = false
    private var nativeStart: Task<Void, Never>?
    private var closedDeadline: Date?
    private var lastBatteryRead = Date.distantPast
    private var batteryLevel = 1.0
    private var power: Battery.PowerState?
    private var savedMode: LogoMode?
    private var smoothedSound = 0.0
    private let started = ProcessInfo.processInfo.systemUptime
    private let observesSystemEvents: Bool
    private let powerAllowsClosed: (() -> Bool)?

    init(device: (any LogoOutputDevice)? = nil, store: UserDefaults = .standard, sound: SoundLevelSource? = nil, observesSystemEvents: Bool = true, powerAllowsClosed: (() -> Bool)? = nil) {
        let selected = device ?? LogoHardware()
        self.device = selected; self.sound = sound ?? SystemSound.source()
        self.observesSystemEvents = observesSystemEvents
        self.powerAllowsClosed = powerAllowsClosed
        defaults = PluginDefaults(pluginID: LogoPaths.id, store: store)
        settings = defaults.data("configuration").flatMap { try? JSONDecoder().decode(LogoPreferences.self, from: $0) }?.normalized() ?? LogoPreferences()
        supported = selected.supported
    }

    var needsRecovery: Bool { device.hasRecovery }

    func start(host: any DeckHost) {
        guard !host.isDryRun, !stopped else { return }
        self.host = host
        guard supported else { return }
        if observesSystemEvents {
            observeLifecycle()
            batteryObserver = BatteryObserver { [weak self] in
                guard let self else { return }
                self.lastBatteryRead = .distantPast
                self.pump()
            }
        }
        agentObserver = NotificationCenter.default.addObserver(forName: .init("com.statusdeck.codingLight.changed"), object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let state = note.userInfo?["state"] as? String else { return }
                self.agent = CodingLightState(rawValue: state) ?? .idle
                self.sessions = note.userInfo?["sessions"] as? Int ?? 0
                self.pump()
            }
        }
        NotificationCenter.default.post(name: .init("com.statusdeck.codingLight.request"), object: nil)
        connect()
    }

    func connect() {
        guard !stopped, supported, !connecting else { return }
        error = nil; connecting = true
        nativeStart = Task { [self] in
            defer { connecting = false; nativeStart = nil }
            do {
                try await device.begin()
                guard !stopped, !Task.isCancelled else { device.end(); return }
                active = true
                if settings.keepClosed { closedDeadline = Date().addingTimeInterval(Double(settings.closedMinutes) * 60) }
                syncShortcuts(); configureSources(); startTimer(); pump()
            } catch { self.error = error.localizedDescription; device.end() }
        }
        device.onFailure = { [weak self] text in self?.error = text; self?.active = false; self?.stopSources() }
    }

    func recover() {
        guard !connecting else { return }
        connecting = true
        Task { [self] in
            do { try await device.recover(); error = nil; objectWillChange.send() }
            catch { self.error = error.localizedDescription }
            connecting = false
        }
    }

    private func changed(previous: LogoPreferences) {
        let normalized = settings.normalized()
        guard settings == normalized else { settings = normalized; return }
        if let bytes = try? JSONEncoder().encode(settings) { defaults.set(bytes, forKey: "configuration") }
        guard !stopped, active else { return }
        if settings.keepClosed, closedDeadline == nil || previous.closedMinutes != settings.closedMinutes {
            closedDeadline = Date().addingTimeInterval(Double(settings.closedMinutes) * 60)
        }
        if !settings.keepClosed { closedDeadline = nil }
        if savedMode != settings.mode { audioAttempted = false; smoothedSound = 0 }
        syncShortcuts(); configureSources(); startTimer(); pump()
    }

    private func configureSources(authorizeTyping: Bool = false) {
        guard active, !stopped, !paused, pauseReasons.isEmpty, settings.enabled else { stopSources(); return }
        if configuredInput != settings.mode || authorizeTyping {
            let available = inputs.configure(mode: settings.mode, authorize: authorizeTyping)
            configuredInput = settings.mode
            if settings.mode == .typing {
                inputStatus = available ? DeckL("正在监听按键时序，不读取输入文字。", "Listening to timing only; no characters are read.") : DeckL("请按下方按钮开启输入监控权限。", "Enable Input Monitoring using the button below.")
            } else if settings.mode == .trackpad {
                inputStatus = available ? DeckL("触控板已连接。", "Trackpad connected.") : DeckL("未找到兼容的触控板。", "No compatible trackpad found.")
            } else { inputStatus = "" }
        }
        if settings.mode == .music {
            if !audioAttempted {
                audioAttempted = true
                do { guard let sound else { throw SoundError.unsupportedSystem }; try sound.start(); audioStarted = true }
                catch { self.error = DeckL("系统音频不可用，请检查隐私设置后重试。", "System audio is unavailable. Check privacy settings and retry.") + " " + error.localizedDescription }
            }
        } else { sound?.stop(); audioStarted = false; audioAttempted = false }
        savedMode = settings.mode
    }

    func retryInput() { configureSources(authorizeTyping: true) }
    func retryAudio() { audioAttempted = false; error = nil; configureSources(); startTimer() }

    private func stopSources() {
        inputs.stop(); configuredInput = nil
        sound?.stop(); audioStarted = false; audioAttempted = false
    }

    private func startTimer() {
        let animating: Bool
        switch settings.mode {
        case .steady, .morse: animating = false
        case .music: animating = audioStarted
        case .battery: animating = power?.isPluggedIn == true && power?.isCharging == true && batteryLevel < 0.995
        case .agents: animating = agent != .idle
        case .breathing, .trackpad, .typing: animating = true
        }
        let interval = settings.enabled && !paused && !lidPaused && animating ? 0.05 : 1.0
        guard timer == nil || pollingInterval != interval else { return }
        timer?.invalidate()
        pollingInterval = interval
        let next = Timer(timeInterval: interval, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.pump() } }
        next.tolerance = interval * 0.1
        RunLoop.main.add(next, forMode: .common); timer = next
    }

    func pump() {
        guard active, !stopped else { return }
        let now = ProcessInfo.processInfo.systemUptime
        // Power-source notifications update immediately; a slow fallback covers
        // missed notifications without querying IOKit on every animation frame.
        if Date().timeIntervalSince(lastBatteryRead) > 5 {
            batteryLevel = Battery.charge() ?? 0
            power = Battery.powerState(); lastBatteryRead = Date()
        }
        let safePower = powerAllowsClosed?() ?? (power?.isPluggedIn == true && !ProcessInfo.processInfo.isLowPowerModeEnabled &&
            ProcessInfo.processInfo.thermalState != .serious && ProcessInfo.processInfo.thermalState != .critical)
        if settings.keepClosed, let deadline = closedDeadline, Date() >= deadline { settings.keepClosed = false; return }
        let allowClosed = settings.enabled && settings.keepClosed && safePower && closedDeadline != nil
        // Screen-sleep can precede the physical lid event. Locking and switching
        // users still pause unconditionally, even when closed-lid mode is armed.
        let shouldPause = LogoLifecycle.pausesOutput(reasons: pauseReasons, closedSessionAllowed: allowClosed)
        if shouldPause {
            stopSources()
            do { try device.allowClosed(false, until: nil) } catch { self.error = error.localizedDescription }
            if !paused { device.pause() }
            paused = true
            startTimer()
            return
        }
        if paused { paused = false; device.resume(); configureSources() }
        do { try device.allowClosed(allowClosed, until: allowClosed ? closedDeadline : nil) }
        catch { self.error = error.localizedDescription; return }
        if device.closed && !allowClosed {
            if !lidPaused { device.pause(); stopSources(); lidPaused = true }
            startTimer()
            return
        }
        if lidPaused { lidPaused = false; device.resume(); configureSources() }
        startTimer()
        if settings.enabled && settings.mode == .morse {
            let text = LogoMorse.transmittedText(settings.morseText)
            device.playMorse(MorseCode.canSend(text) ? text : nil)
            if !MorseCode.canSend(text) { device.output(0, response: 0.04) }
            return
        }
        device.playMorse(nil)
        if audioStarted {
            let next = LogoPreferences.clamp(sound?.loudness ?? 0)
            let mix = min(1, 0.05 / settings.musicResponse)
            smoothedSound += (next - smoothedSound) * mix
        }
        var signals = LogoSignals()
        signals.seconds = now - started; signals.battery = batteryLevel
        signals.pluggedIn = power?.isPluggedIn == true; signals.charging = power?.isCharging == true
        signals.music = smoothedSound; signals.contacts = inputs.contacts
        signals.clicked = now < inputs.clickUntil; signals.recentlyTyped = now < inputs.typingUntil
        signals.agent = agent
        let value = signals.output(for: settings)
        if abs(output - value) > 0.01 { output = value }
        device.output(value, response: settings.mode == .music ? 0.06 : 0.12)
    }

    private func syncShortcuts() {
        guard settings.shortcuts, active, !stopped, let host else { keys.removeAll(); return }
        guard keys.isEmpty else { return }
        for (code, label, change) in [(UInt32(11), "⌃⌘B", 0), (125, "⌃⌘↓", -1), (126, "⌃⌘↑", 1)] {
            if let token = host.registerHotKey(.init(keyCode: code, modifiers: 4352, label: label), handler: { [weak self] in
                guard let self else { return }
                if change == 0 { self.settings.enabled.toggle() }
                else if self.settings.mode != .battery { self.settings.brightness = LogoPreferences.clamp(self.settings.brightness + Double(change) * 0.05) }
            }) { keys.append(token) }
        }
    }

    private func observeLifecycle() {
        let center = NSWorkspace.shared.notificationCenter
        for (name, reason) in [(NSWorkspace.willSleepNotification, LogoPauseReason.systemSleep),
                               (NSWorkspace.sessionDidResignActiveNotification, .sessionInactive)] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setPaused(true, reason: reason) }
            })
        }
        for (name, reason) in [(NSWorkspace.didWakeNotification, LogoPauseReason.systemSleep),
                               (NSWorkspace.sessionDidBecomeActiveNotification, .sessionInactive)] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.setPaused(false, reason: reason)
                }
            })
        }
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.setPaused(true, reason: .screenSleep)
            }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setPaused(false, reason: .screenSleep) }
        })
        for (name, value) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            lockObservers.append(DistributedNotificationCenter.default().addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setPaused(value, reason: .locked) }
            })
        }
    }

    func setPaused(_ value: Bool, reason: LogoPauseReason) {
        if value { pauseReasons.insert(reason) } else { pauseReasons.remove(reason) }
        if !pauseReasons.isEmpty { stopSources() }
        pump()
        if !paused { configureSources() }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true; nativeStart?.cancel(); timer?.invalidate(); timer = nil; batteryObserver = nil; keys.removeAll(); stopSources()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }; workspaceObservers.removeAll()
        if let agentObserver { NotificationCenter.default.removeObserver(agentObserver) }; agentObserver = nil
        lockObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }; lockObservers.removeAll()
        device.end(); device.onFailure = nil; active = false; host = nil
    }
}

@MainActor final class LogoPlugin: DeckPlugin {
    let manifest = PluginManifest(id: LogoPaths.id, name: "标志灯光", summary: "Apple 标志亮度、呼吸、电池、音乐、编程状态与输入互动。",
                                  symbol: "lightbulb", version: "1.0.3", category: .tools, enabledByDefault: false, sortOrder: 400)
    private(set) var runtime: LogoRuntime?
    func activate(host: any DeckHost) {
        guard !host.isDryRun, runtime == nil else { return }
        let runtime = LogoRuntime(); self.runtime = runtime; runtime.start(host: host)
    }
    func deactivate() { runtime?.stop(); runtime = nil }
    var sections: [DeckSection] { [] }
    var settingsView: AnyView? {
        guard let runtime else { return AnyView(Text(DeckL("灯光控制均位于此设置页。", "All light controls live in this settings page."))) }
        return AnyView(LogoSettingsView(runtime: runtime))
    }
}

public enum MyStatusLogoPlugin {
    public static func make() -> UnsafeMutableRawPointer { DeckPluginExport.retained { LogoPlugin() } }
    public static func runHelper(_ arguments: [String]) -> Never {
        let flags = Array(arguments.dropFirst())
        if flags.count == 2, flags[0] == "--recover", let token = UUID(uuidString: flags[1]) {
            Task { @MainActor in exit(await LogoRecoveryWorker.run(token: token)) }; dispatchMain()
        }
        if flags == ["--diagnose"] {
            Task { @MainActor in
                let hardware = LogoHardware()
                let info: [String: Any] = ["supported": hardware.supported, "recovery_required": hardware.hasRecovery,
                    "helper": LogoPaths.helper?.path ?? "", "read_only": true, "modes": LogoMode.allCases.map(\.rawValue)]
                if let bytes = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]) { FileHandle.standardOutput.write(bytes + Data([10])) }
                exit(0)
            }; dispatchMain()
        }
        if flags == ["--hardware-smoke"] {
            Task { @MainActor in exit(await LogoNativeCheck.run()) }; dispatchMain()
        }
        FileHandle.standardError.write(Data("Use --diagnose, or an internal --recover token.\n".utf8)); exit(2)
    }
}
