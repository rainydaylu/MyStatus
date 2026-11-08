import Foundation

/// The system-facing controllers several built-in plugins need. Everything is
/// created on first use, so with the plugins that want it off, a controller and its
/// listeners simply never exist.
@MainActor
final class SharedServices {
    let isDryRun: Bool
    init(isDryRun: Bool = false) { self.isDryRun = isDryRun }
    let store = SystemStore()

    private(set) lazy var displays = DisplayController()
    private(set) lazy var audio = AudioController()
    private(set) lazy var softwareVolume = isDryRun ? SoftwareVolumeController(permission: { .denied }) : SoftwareVolumeController()
    private(set) lazy var sound = SoundModel(audio: audio, displays: displays, software: softwareVolume)
    private(set) lazy var wifi = WiFiController()
    private(set) lazy var bluetooth = BluetoothController()
    private(set) lazy var inputSources = InputSourceController()
    private(set) lazy var systemControls = SystemControlAuthorization(isDryRun: isDryRun)
    private(set) lazy var power = PowerController(authorization: systemControls)
    private(set) lazy var fans = FanController(authorization: systemControls)
}
