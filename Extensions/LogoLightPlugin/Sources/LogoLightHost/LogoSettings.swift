import Foundation
import LogoLightCore
import StatusDeckKit

enum LogoMode: String, Codable, CaseIterable, Identifiable {
    case steady, breathing, battery, music, agents, trackpad, typing, morse
    var id: String { rawValue }
    var title: String {
        switch self {
        case .steady: return DeckL("常亮", "Steady")
        case .breathing: return DeckL("呼吸灯", "Breathe")
        case .battery: return DeckL("电池状态", "Battery")
        case .music: return DeckL("音乐律动", "Music")
        case .agents: return DeckL("AI 编程状态", "AI coding status")
        case .trackpad: return DeckL("触控板互动", "Trackpad")
        case .typing: return DeckL("打字互动", "Typing")
        case .morse: return DeckL("摩斯电码", "Morse code")
        }
    }

    var symbol: String {
        switch self {
        case .steady: return "lightbulb.fill"
        case .breathing: return "wind"
        case .battery: return "battery.75percent"
        case .music: return "waveform"
        case .agents: return "terminal"
        case .trackpad: return "hand.point.up.left"
        case .typing: return "keyboard"
        case .morse: return "ellipsis"
        }
    }

    var caption: String {
        switch self {
        case .steady: return DeckL("保持固定亮度", "Hold a fixed brightness")
        case .breathing: return DeckL("柔和渐亮、渐暗", "Gently fade in and out")
        case .battery: return DeckL("电量显示与充电提示", "Charge level and charging pulse")
        case .music: return DeckL("跟随正在播放的音乐", "Follow system playback")
        case .agents: return DeckL("跟随 CodeIsland 会话", "Follow CodeIsland sessions")
        case .trackpad: return DeckL("手指接触时亮起", "Light on finger contact")
        case .typing: return DeckL("随键盘输入亮起", "Light while typing")
        case .morse: return DeckL("把一行文字循环闪烁", "Loop a message in light")
        }
    }
}

struct LogoPreferences: Codable, Equatable {
    var enabled = true
    var mode = LogoMode.steady
    var brightness = 0.7
    var cycleSeconds = 6.0
    var dimFloor = 0.0
    var musicGain = 1.0
    var musicResponse = 0.12
    var darkBetweenBeats = false
    var clickFlash = false
    var keepClosed = false
    var closedMinutes = 10
    var shortcuts = false
    var morseText = "SOS"

    init() {}

    // New modes must not discard the user's brightness, music, or lid settings.
    private enum CodingKeys: String, CodingKey {
        case enabled, mode, brightness, cycleSeconds, dimFloor, musicGain, musicResponse
        case darkBetweenBeats, clickFlash, keepClosed, closedMinutes, shortcuts, morseText
    }
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        mode = try c.decodeIfPresent(LogoMode.self, forKey: .mode) ?? mode
        brightness = try c.decodeIfPresent(Double.self, forKey: .brightness) ?? brightness
        cycleSeconds = try c.decodeIfPresent(Double.self, forKey: .cycleSeconds) ?? cycleSeconds
        dimFloor = try c.decodeIfPresent(Double.self, forKey: .dimFloor) ?? dimFloor
        musicGain = try c.decodeIfPresent(Double.self, forKey: .musicGain) ?? musicGain
        musicResponse = try c.decodeIfPresent(Double.self, forKey: .musicResponse) ?? musicResponse
        darkBetweenBeats = try c.decodeIfPresent(Bool.self, forKey: .darkBetweenBeats) ?? darkBetweenBeats
        clickFlash = try c.decodeIfPresent(Bool.self, forKey: .clickFlash) ?? clickFlash
        keepClosed = try c.decodeIfPresent(Bool.self, forKey: .keepClosed) ?? keepClosed
        closedMinutes = try c.decodeIfPresent(Int.self, forKey: .closedMinutes) ?? closedMinutes
        shortcuts = try c.decodeIfPresent(Bool.self, forKey: .shortcuts) ?? shortcuts
        morseText = try c.decodeIfPresent(String.self, forKey: .morseText) ?? morseText
    }

    func normalized() -> Self {
        var value = self
        value.brightness = Self.clamp(brightness)
        value.cycleSeconds = Self.bound(cycleSeconds, 3...10, 6)
        value.dimFloor = Self.clamp(dimFloor)
        value.musicGain = Self.bound(musicGain, 0.25...3, 1)
        value.musicResponse = Self.bound(musicResponse, 0.05...0.5, 0.12)
        value.closedMinutes = min(30, max(1, closedMinutes))
        value.morseText = String(morseText.components(separatedBy: .newlines).joined(separator: " ").prefix(MorseCode.maxLength))
        return value
    }
    static func clamp(_ x: Double) -> Double { bound(x, 0...1, 0) }
    static func bound(_ x: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
        x.isFinite ? min(range.upperBound, max(range.lowerBound, x)) : fallback
    }
}

enum CodingLightState: String { case idle, working, attention }

struct LogoSignals {
    var seconds = 0.0
    var battery = 1.0
    var pluggedIn = false
    var charging = false
    var music = 0.0
    var contacts = 0
    var clicked = false
    var recentlyTyped = false
    var agent = CodingLightState.idle

    func output(for raw: LogoPreferences) -> Double {
        let p = raw.normalized()
        guard p.enabled else { return 0 }
        let t = seconds.isFinite ? max(0, seconds) : 0
        let wave = (sin(t * 2 * .pi / p.cycleSeconds) + 1) / 2
        let pulse = p.dimFloor + (1 - p.dimFloor) * wave
        let result: Double
        switch p.mode {
        case .steady: result = p.brightness
        case .breathing: result = p.brightness * pulse
        case .battery:
            result = charging && pluggedIn && battery < 0.995 ? pulse : (pluggedIn ? 1 : LogoPreferences.clamp(battery))
        case .music:
            let amplitude = LogoPreferences.clamp(music * p.musicGain)
            result = p.brightness * (p.darkBetweenBeats ? (amplitude > 0.45 ? 1 : 0) : amplitude)
        case .agents:
            switch agent {
            case .idle: result = p.brightness * 0.12
            case .working: result = p.brightness * (0.15 + 0.85 * wave)
            case .attention: result = p.brightness * (t.truncatingRemainder(dividingBy: 1.4) < 0.2 ? 1 : 0.08)
            }
        case .trackpad: result = contacts > 0 && !(p.clickFlash && clicked) ? p.brightness : 0
        case .typing: result = recentlyTyped ? p.brightness : 0
        case .morse: result = 0 // The native Morse animator owns timing and output.
        }
        return LogoPreferences.clamp(result)
    }
}

enum LogoMorse {
    static func transmittedText(_ text: String) -> String {
        (text.applyingTransform(.toLatin, reverse: false) ?? text)
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .uppercased()
    }
    static func notation(_ text: String) -> String { MorseCode.notation(transmittedText(text)) }
    static func unsupported(_ text: String) -> String {
        String(Set(transmittedText(text).filter { !$0.isWhitespace && MorseCode.table[$0] == nil }).sorted())
    }
}

enum LogoPauseReason: Hashable { case systemSleep, sessionInactive, screenSleep, locked }

enum LogoLifecycle {
    static func pausesOutput(reasons: Set<LogoPauseReason>, closedSessionAllowed: Bool) -> Bool {
        // Locking and switching users always stop the light, including closed-lid mode.
        !reasons.isDisjoint(with: [.systemSleep, .sessionInactive, .locked]) ||
            (reasons.contains(.screenSleep) && !closedSessionAllowed)
    }
}

struct LogoTouchLedger {
    var paths: [UInt: Set<Int>] = [:]
    var count: Int { paths.values.reduce(0) { $0 + $1.count } }
    mutating func accept(device: UInt, path: Int, state: Int) {
        if state == 3 || state == 4 { paths[device, default: []].insert(path) }
        else { paths[device]?.remove(path) }
    }
}
