import ApplicationServices
import Combine
import Foundation
import StatusDeckKit

// Read modifier flags from the wheel event itself. No global keyboard tap is needed.
enum MosModifier: String, CaseIterable, Codable, Identifiable {
    case none, shift, control, option, command

    var id: Self { self }

    var title: String {
        switch self {
        case .none: DeckL("不使用", "None")
        case .shift: "⇧ Shift"
        case .control: "⌃ Control"
        case .option: "⌥ Option"
        case .command: "⌘ Command"
        }
    }

    func isHeld(in flags: CGEventFlags) -> Bool {
        switch self {
        case .none: false
        case .shift: flags.contains(.maskShift)
        case .control: flags.contains(.maskControl)
        case .option: flags.contains(.maskAlternate)
        case .command: flags.contains(.maskCommand)
        }
    }
}

struct MosScrollOptions: Codable, Equatable {
    var smooth = false
    var reverse = true
    var reverseVertical = true
    var reverseHorizontal = false
    var boostKey: MosModifier = .none
    var horizontalKey: MosModifier = .none
    var bypassKey: MosModifier = .command
    var minimumStep = 23.0
    var speed = 1.45
    var duration = 0.50

    static let stepRange = 1.0...120.0
    static let speedRange = 0.25...4.0
    static let durationRange = 0.0...5.0

    // Match the duration slider in Mos 3.5, which is a curve parameter.
    var frameTransition: Double {
        let value = min(Self.durationRange.upperBound, max(Self.durationRange.lowerBound, duration))
        return ((1 - sqrt(value / 5.2)) * 1000).rounded() / 1000
    }

    var reverseX: Bool { reverse && reverseHorizontal }
    var reverseY: Bool { reverse && reverseVertical }

    mutating func resetAdvanced() {
        let presets = MosScrollOptions()
        boostKey = presets.boostKey
        horizontalKey = presets.horizontalKey
        bypassKey = presets.bypassKey
        minimumStep = presets.minimumStep
        speed = presets.speed
        duration = presets.duration
    }
}

struct MosAppRule: Codable, Identifiable {
    let id: String
    let name: String
    let path: String?
    var options: MosScrollOptions
}

@MainActor
final class MosPreferences: ObservableObject {
    private let defaults: PluginDefaults
    @Published var options: MosScrollOptions {
        didSet { defaults.set(try? JSONEncoder().encode(options), forKey: "scrollOptions") }
    }
    @Published var rules: [MosAppRule] {
        didSet { defaults.set(try? JSONEncoder().encode(rules), forKey: "appRules") }
    }
    @Published var allowlist: Bool {
        didSet { defaults.set(allowlist, forKey: "allowlist") }
    }
    @Published var hidesIcon: Bool {
        didSet { defaults.set(hidesIcon, forKey: "hidesIcon") }
    }

    init(store: UserDefaults = .standard) {
        defaults = PluginDefaults(pluginID: "com.statusdeck.mos", store: store)
        let decoder = JSONDecoder()
        let presets = MosScrollOptions()
        if let data = defaults.data("scrollOptions"), var saved = try? decoder.decode(MosScrollOptions.self, from: data) {
            // Earlier builds saved the entire profile even when only a switch changed.
            let originalPreset = saved.minimumStep == 12 && saved.speed == 1 && saved.duration == 0.32
            let priorPreset = saved.minimumStep == 2 && saved.speed == 0.25 && saved.duration == 0.1
            if originalPreset || priorPreset {
                saved.minimumStep = presets.minimumStep
                saved.speed = presets.speed
                saved.duration = presets.duration
                defaults.set(try? JSONEncoder().encode(saved), forKey: "scrollOptions")
            }
            options = saved
        } else {
            let horizontal = defaults.bool("reverseHorizontal", default: false)
            let vertical = defaults.bool("reverseVertical", default: horizontal ? false : presets.reverseVertical)
            options = MosScrollOptions(
                smooth: defaults.bool("smooth", default: presets.smooth), reverse: vertical || horizontal,
                reverseVertical: vertical || !horizontal, reverseHorizontal: horizontal,
                speed: defaults.double("speed", default: presets.speed), duration: defaults.double("duration", default: presets.duration)
            )
        }
        if let data = defaults.data("appRules"), let saved = try? decoder.decode([MosAppRule].self, from: data) {
            rules = saved
        } else {
            let excluded = (defaults.string("excludedApps") ?? "").split(separator: "\n")
            let ids = Set(excluded.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter { !$0.isEmpty }
            rules = ids.sorted().map { id in
                MosAppRule(id: id, name: id, path: nil, options: MosScrollOptions(smooth: false))
            }
        }
        allowlist = defaults.bool("allowlist", default: false)
        hidesIcon = defaults.bool("hidesIcon", default: true)
    }

    func settings(for bundleID: String?) -> MosScrollOptions? {
        if let bundleID, let rule = rules.first(where: { $0.id == bundleID }) { return rule.options }
        return allowlist ? nil : options
    }

    func addApp(id: String, name: String, url: URL) {
        guard !rules.contains(where: { $0.id == id }) else { return }
        rules.append(MosAppRule(id: id, name: name, path: url.path, options: options))
    }
}
