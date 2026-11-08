# Third-party code in MyStatus

MyStatus incorporates parts of open-source projects.
Their licence texts are in `LICENSES/`.

## Fanny macOS Fan Control

- Source: <https://github.com/ShahzaibAli02/Fanny-MacOs-FanControl>, `Core/SMC.swift`
- Copyright © 2026 Shahzaib Ali
- Licence: MIT (`LICENSES/Fanny-MIT.txt`)
- The bundled helper uses the SMC backend with bounded retries and returns its diagnostic mode to normal when no manual fan targets remain.

## MonitorControl

- Source: <https://github.com/MonitorControl/MonitorControl>, commit `7cfe64500d19cbbcbf82121a91c826f658a403bd`
- Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others
- Licence: MIT (`LICENSES/MonitorControl-MIT.txt`)

| In this repository | Origin | Changes |
| --- | --- | --- |
| `Sources/StatusDeckCore/Vendor/MonitorControl/Arm64DDC.swift` | `MonitorControl/Support/Arm64DDC.swift` | Adds `import CPrivateAPI` in place of the bridging header |
| `Sources/StatusDeckCore/Vendor/MonitorControl/Command.swift` | `MonitorControl/Enums/Command.swift` | None |
| `Sources/CPrivateAPI/include/CPrivateAPI.h` | `MonitorControl/Support/Bridging-Header.h` | Only the DDC declarations |

Also adapted from MonitorControl, rewritten for this app: the coalesced DDC writes, matching display speakers
to an audio device by name, and the black overlay window used to dim displays without DDC.

## Status Trio

- Source: <https://github.com/lingyired/status-trio>, commit `212a64fcd155131582aa3e3265d6bf17ea5132a9`
- Copyright 2026 lingyired
- Licence: Apache License 2.0 (`LICENSES/StatusTrio-Apache-2.0.txt`, `LICENSES/StatusTrio-NOTICE.txt`)

| In `Sources/StatusDeckCore/Vendor/StatusTrio/` | Origin in `Sources/StatusTrioCore/` | Changes |
| --- | --- | --- |
| `CoreAudioOutputController.swift` | `Audio/` | `isMuted`, `volume` and `defaultOutputDeviceID` made non-private and non-isolated; origin header added |
| `AudioOutputDevice.swift`, `AudioOutputControlling.swift`, `CoreAudioOutputChannelElements.swift` | `Audio/` | Origin header added |
| `IOBluetoothRadioPowerBackend.swift` | `Monitoring/` | Origin header added |
| `WiFiNameAuthorizer.swift` | `Monitoring/` | Origin header added |
| `BluetoothAccessoryBatteryReader.swift` | `Monitoring/` | Keeps the parser, drops the worker class |
| `InputSourceReading.swift`, `InputSourceSwitching.swift` | `InputSource/` | Origin header added |
| `SharedTypes.swift` | `Audio/AudioOutputDeviceIcon.swift`, `Models/StatusSnapshot.swift`, `Monitoring/BluetoothRadioPowerController.swift` | Only the types the files above depend on |

Also adapted from Status Trio, rewritten for this app: the SMC key-data ABI and power-sensor keys
(`SMCClient` in `Services/Monitor/SensorReaders.swift`), the paired-device reading through `system_profiler`
(`Services/Control/ConnectivityControllers.swift`), the confirmation before disconnecting input devices, and the idea of
a single menu bar icon carrying battery, connection and volume (`TrioIconRenderer` in `Plugins/MenuBarPlugins.swift`,
an independent drawing).

## References that contributed no code

- **Tutti** (<https://github.com/BarryBarrywu/tutti>) is proprietary and publishes no source code. Its public
  screenshots informed the visual style. Nothing in StatusDeck is derived from its code or assets.
- **SoundBridge** (<https://github.com/chenjy16/SoundBridge>) informed the idea of software gain for outputs macOS
  cannot adjust. Its repository has no licence file, so none of its code is used, and StatusDeck uses a Core Audio
  tap rather than its virtual driver.
- **Lucent** informed the feature set of the clipboard plugin, by way of a report on what the app does. The
  implementation is independent, and StatusDeck uses none of its code, keys, endpoints or data.

## Bundled plugin adapters

- **Hanging clipboard** includes an adapted copy of [Tendedero](https://github.com/alejandrobujan/tendedero), by Alejandro Buján (MIT code license; original name/icon excluded). Source remains in `Extensions/HangingClipboardPlugin`. Changes replace the standalone application lifecycle with `DeckPlugin`, namespace preferences, filter Carbon hotkeys, and stop watchers when disabled. The original app icon is not distributed.
- **Mos** includes `Interpolator.swift` from [Caldis/Mos](https://github.com/Caldis/Mos), commit `8a2fd112e2af444c37ca5f65f42e9bd19c08a5c2`, under [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/). `Extensions/MosPlugin/LICENSE` retains the notice. The new adapter supplies mouse-wheel interception, per-axis reversal, speed/duration controls, and app exclusions. Mos's Logitech remapping and action library are not included. This distribution is for personal, noncommercial use.
- **CodeIsland** includes the desktop panel, session discovery, local hook server, and `CodeIslandCore` from [wxtsky/CodeIsland](https://github.com/wxtsky/CodeIsland), commit `03c77e9457f0adc56fa036caf4925e4a576b453b` (MIT). `Extensions/CodeIslandPlugin/adapt.py` adapts the panel lifecycle, settings routing, resource lookup, and socket teardown to MyStatus. Yams 5.4.0 and its libyaml dependency are included under `Extensions/CodeIslandPlugin/Vendor/Yams` with their license. The hosted build includes upstream interface resources and does not start the standalone launcher, automatically install hooks, or start companion services.
- **Tutti** is a visual reference only. No Tutti source, binaries, or assets are included.

Each adapter has an `upstream.json` describing the exact repository and integrated source scope. In-app updates fetch that source scope at an immutable Git commit and compile it using the shipped adapter. Incompatible upstream changes fail without replacing the installed plugin.
