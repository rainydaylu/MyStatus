import Foundation
import LogoLightCore

/// Explicit development check: bounded brightness changes, then verified native handback.
@MainActor enum LogoNativeCheck {
    static func run() async -> Int32 {
        let hardware = LogoHardware()
        guard hardware.supported, !hardware.hasRecovery, let service = CoreBrightnessService() else { return 2 }
        let original = service.value(forKey: "LEBacklightMode") as? NSNumber
        var samples: [Double] = []
        var failure: String?
        do {
            try await hardware.begin()
            for brightness in [0.25, 0.75] {
                hardware.output(brightness, response: 0.12)
                try await Task.sleep(nanoseconds: 850_000_000)
                let state = service.value(forKey: "LEPWMState") as? [String: Any]
                samples.append((state?["Factor"] as? NSNumber)?.doubleValue ?? -1)
            }
        } catch { failure = error.localizedDescription }
        hardware.end()
        for _ in 0..<250 where hardware.hasRecovery { try? await Task.sleep(nanoseconds: 20_000_000) }
        let restored = service.value(forKey: "LEBacklightMode") as? NSNumber
        let passed = failure == nil && samples.count == 2 && samples[0] >= 0 && samples[1] > samples[0] + 0.1 &&
            original == restored && !hardware.hasRecovery
        let result: [String: Any] = ["passed": passed, "brightness_factor_samples": samples,
            "original_switch_restored": original == restored, "recovery_record_cleared": !hardware.hasRecovery,
            "failure": failure ?? "", "optical_measurement": false]
        if let bytes = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            FileHandle.standardOutput.write(bytes + Data([10]))
        }
        return passed ? 0 : 1
    }
}
