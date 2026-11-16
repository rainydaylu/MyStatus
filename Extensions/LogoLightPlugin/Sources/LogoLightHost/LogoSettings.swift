import Foundation
import StatusDeckKit

enum LogoMode: String, Codable, CaseIterable, Identifiable {
    case steady, breathing, battery, music, agents, trackpad, typing
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

    func normalized() -> Self {
        var value = self
        value.brightness = Self.clamp(brightness)
        value.cycleSeconds = Self.bound(cycleSeconds, 3...10, 6)
        value.dimFloor = Self.clamp(dimFloor)
        value.musicGain = Self.bound(musicGain, 0.25...3, 1)
        value.musicResponse = Self.bound(musicResponse, 0.05...0.5, 0.12)
        value.closedMinutes = min(30, max(1, closedMinutes))
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
        }
        return LogoPreferences.clamp(result)
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
