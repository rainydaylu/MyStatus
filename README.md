# MyStatus

MyStatus puts your Mac’s system activity, display controls, and clipboard history in the menu bar. Open one panel to see what’s using memory, change your screen brightness or volume, or find something you copied earlier.

**[Download MyStatus for Mac](https://github.com/rainydaylu/MyStatus/releases/download/v1.0.0/MyStatus-1.0.0.zip)** · [Release notes](https://github.com/rainydaylu/MyStatus/releases/tag/v1.0.0) · [简体中文](README.zh-CN.md)

The download is for **Apple silicon Macs (M1 or newer)** running **macOS 13 or later**.

![MyStatus menu bar panel with display, sound, Wi-Fi, CPU, memory, disk, and network cards](docs/images/mystatus-menu-bar.jpg)

*Two sections of the MyStatus menu bar panel, exported from the app. The order and number of cards can vary with your setup.*

[Getting started](#getting-started) · [System activity](#understand-your-macs-activity) · [Display and sound](#adjust-display-sound-and-connections) · [Clipboard](#find-something-you-copied) · [Customization](#make-the-panel-yours) · [Build from source](#build-from-source)

## Getting started

1. **Download and unzip.** Use the download link above, then double-click the ZIP file in Finder.
2. **Move the app to Applications.** Drag **MyStatus.app** into the **Applications** folder and open it.
3. **Open the panel.** Click the MyStatus status icon in the menu bar at the top of your screen. Move your pointer over a card to see more detail.

Start with **Memory**, **Displays**, or **Sound**. The main panel shows the readings and controls you’re likely to use most. The detail pane gives you more room for charts, device choices, and settings. Click **Edit Controls** at the bottom of the panel to change which cards are shown.

If macOS shows a developer verification message, see [Apple’s guide to opening apps safely](https://support.apple.com/en-us/102445). This release has not been notarized by Apple.

## Understand your Mac’s activity

![CPU and GPU charts and the memory pressure and usage rings in the app’s detail views](docs/images/mystatus-system-details.jpg)

| Card | What to look at |
| --- | --- |
| **CPU** | The bars show recent activity. Blue is work done by your apps and pink is work done by the system. The small rings show individual cores. Hover over the card for CPU and GPU details. |
| **Memory** | The two rings show memory pressure and memory use. If your Mac feels slow, start with pressure. It shows how hard macOS is working to make room for your apps. The detail view breaks down app, wired, and compressed memory and shows swap use. |
| **Disk** | See how much space is available and how quickly the disk is reading or writing. Hover over the card to check individual volumes. |
| **Network** | See your current upload and download rates and their recent history. The detail pane shows traffic totals since launch and the active interfaces. |
| **Sensors and battery** | Check temperatures, fan speeds, charge, and battery health when your Mac reports them. The battery detail also shows cycle count and power flow where available. |

If a **Processes** list stays on **Loading** or **Sampling** in v1.0.0, you can check per-app activity in macOS **Activity Monitor**. The cards still show overall system readings.

## Adjust display, sound, and connections

The **Displays** and **Sound** sliders are available directly in the panel. Use the details to see which display or sound device you’re adjusting.

![The actual MyStatus display detail and Wi-Fi detail, including brightness, resolution, signal, and channel](docs/images/mystatus-display-and-wifi.jpg)

- **Displays.** Adjust the built-in screen or a compatible external monitor. Supported external displays can also expose a contrast slider. Available controls depend on your monitor and how it’s connected.
- **Sound.** Switch output and input devices. MyStatus can also adjust the volume of compatible HDMI or DisplayPort audio outputs. If your monitor can’t accept volume commands, **Software Volume** is available for supported outputs on macOS 14.2 or later.
- **Wi-Fi and Bluetooth.** Check connection status, Wi-Fi signal and channel, or battery levels for supported Bluetooth devices. To join a different Wi-Fi network, open **System Settings**.
- **Keyboard controls.** The **Media keys** option lets you use the brightness keys for a supported external display and the volume keys for a supported output. macOS asks for Accessibility access when you enable keyboard control.

## Find something you copied

Press **Control–Option–V** to open clipboard history. Search for text you copied, filter by type or source app, or pin something you use often. Select an item and press **Return** to reuse it. If MyStatus copies the item to the clipboard, press **Command–V** where you want it to go.

<p align="center">
  <img src="docs/images/mystatus-clipboard-history.jpg" width="440" alt="MyStatus clipboard preview with sample file, note, link, color, and code entries">
</p>

*The app’s clipboard preview with built-in sample entries.*

Clipboard history is stored locally in a user-only folder without encryption. You can pause recording, clear history, or exclude specific apps. Items marked as confidential or temporary by their source app are skipped.

## Make the panel yours

Use **Edit Controls** to turn cards on or off and drag them into the order you want. You can keep the combined battery, Wi-Fi, and volume icon in the menu bar or enable live readouts for CPU, memory, and network speed.

In **Preferences**, choose a light or dark appearance or follow the system setting. Adjust how translucent the cards are, how strongly the background is tinted, and how much the desktop behind the panel is blurred. MyStatus uses Liquid Glass on macOS 26 and a frosted appearance on earlier versions.

![The same native MyStatus CPU and memory cards in light and dark appearance](docs/images/mystatus-light-and-dark.jpg)

*These exported views show the two color schemes. The live glass effect also depends on what’s behind the panel.*

### Optional extensions

| Extension | What it adds |
| --- | --- |
| **Hanging Clipboard** | Keep copied images and screenshots at the top of the screen so you can preview, drag, or annotate them. |
| **Mos** | Smooth out mouse-wheel scrolling, reverse its direction separately from the trackpad, and set app-specific exceptions. |
| **CodeIsland** | See supported local AI coding sessions in a notch-style panel at the top of the display. |

Enable the extensions you want in **Edit Controls**. **Plugin updates** can check for new upstream versions. Hanging Clipboard and CodeIsland require macOS 14 or later.

## Permissions and troubleshooting

| If you want to… | What to check |
| --- | --- |
| Adjust an external display from the keyboard or use Mos | Allow MyStatus in **System Settings → Privacy & Security → Accessibility**. |
| Adjust monitor audio with Software Volume | Check system audio permission when macOS prompts you. The app uses the audio stream to adjust playback and does not save a recording. |
| See the name of your Wi-Fi network | Allow location access when prompted. The panel can show connection status without the network name. |
| Change fan speed or Low Power Mode | Some hardware supports these controls and macOS can require administrator authorization. |
| Report a problem | Include your macOS version, Mac model, and the feature you were using. [Open an issue on GitHub](https://github.com/rainydaylu/MyStatus/issues). |

## Build from source

<details>
<summary>Build the app, run tests, and develop plugins</summary>

Install the Xcode Command Line Tools with Swift 6 or later. Use the macOS 26 SDK when building with Liquid Glass support.

```bash
git clone https://github.com/rainydaylu/MyStatus.git
cd MyStatus
./scripts/build-app.sh --no-launch
open build/MyStatus.app
```

Run tests with `./scripts/test.sh`. Start plugin development with [StatusDeckKit](Packages/StatusDeckKit) and the [Keep Awake example](Examples/KeepAwakePlugin). Third-party plugins run inside MyStatus with its permissions.

</details>

MyStatus is made by [rainydaylu](https://github.com/rainydaylu). See the [third-party notices](THIRD_PARTY_NOTICES.md) for credits and licenses, including the noncommercial license for the bundled Mos code.
