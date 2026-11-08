// From Status Trio (https://github.com/lingyired/status-trio), Copyright 2026 lingyired.
// Licensed under the Apache License 2.0; see LICENSES/StatusTrio-Apache-2.0.txt.
// Modified for StatusDeck where noted in THIRD_PARTY_NOTICES.md.

import CoreAudio

@MainActor
protocol AudioOutputControlling: AnyObject {
    @discardableResult func setVolume(_ scalar: Double) -> Bool
    @discardableResult func toggleMute() -> Bool
    @discardableResult func selectOutputDevice(_ deviceID: AudioDeviceID) -> Bool
}
