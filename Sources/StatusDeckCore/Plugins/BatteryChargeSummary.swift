import StatusDeckKit
import SwiftUI

struct BatteryTimeEstimate: Equatable {
    let minutes: Int
    let charging: Bool
    init?(_ battery: BatteryStats) {
        guard battery.isPresent, !battery.isFullyCharged,
              let minutes = battery.minutesRemaining, minutes > 0,
              !battery.isExternalPowerConnected || battery.isCharging,
              !(battery.isCharging && battery.percent >= 100) else { return nil }
        self.minutes = minutes
        charging = battery.isCharging
    }
}

struct BatteryChargeSummary: View {
    let battery: BatteryStats
    @Environment(\.deckTheme) private var theme

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                let charge = Double(battery.percent) / 100
                DeckRing(value: charge, color: battery.isLowPowerMode ? theme.warning : (battery.percent <= 20 && !battery.isExternalPowerConnected ? theme.negative : theme.accent)) {
                    DeckRingPercent(charge, caption: DeckL("电量"))
                }.frame(width: 98, height: 98).frame(maxWidth: .infinity)
                DeckRing(value: battery.health ?? 0, color: theme.magenta) {
                    if let health = battery.health { DeckRingPercent(health, caption: DeckL("电池健康")) }
                    else { Text("—").foregroundStyle(theme.secondary) }
                }.frame(width: 98, height: 98).frame(maxWidth: .infinity)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(battery.statusText).font(.system(size: 12)).foregroundStyle(theme.secondary)
                Spacer(minLength: 4)
                if let estimate = BatteryTimeEstimate(battery) {
                    Text(estimate.charging ? DeckL("充满还需", "Until full") : DeckL("剩余", "Remaining"))
                        .font(.system(size: 11)).foregroundStyle(theme.secondary)
                    Text(Format.duration(TimeInterval(estimate.minutes) * 60))
                        .font(.system(size: 15, weight: .semibold)).monospacedDigit().foregroundStyle(theme.primary)
                        .accessibilityIdentifier(estimate.charging ? "battery.time-to-full" : "battery.time-remaining")
                }
            }.padding(.top, 2)
        }
    }
}
