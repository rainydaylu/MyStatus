<p align="center">
  <img src="Support/AppIcon.png" width="112" height="112" alt="MyStatus blue glass speedometer app icon">
</p>

<h1 align="center">MyStatus</h1>

<p align="center">
  <strong>Your Mac at a glance.</strong> See system activity, adjust your screen and sound, and find what you copied, all from the menu bar.
</p>

<p align="center">
  <a href="https://github.com/rainydaylu/MyStatus/releases/latest#assets"><img src="docs/images/download-mac-en.svg" width="190" height="40" alt="Download for Mac"></a>
  &nbsp;
  <a href="https://github.com/rainydaylu/MyStatus/releases/latest"><img src="docs/images/github-release-en.svg" width="170" height="40" alt="GitHub Release"></a>
</p>

<p align="center">
  <em>v1.2.4 · Apple silicon Macs (M1 or newer) · macOS 13 or later</em>
  <br>
  <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <a href="#getting-started">Getting started</a> &nbsp;·&nbsp;
  <a href="#understand-your-macs-activity">System activity</a> &nbsp;·&nbsp;
  <a href="#adjust-display-sound-and-connections">Display and sound</a> &nbsp;·&nbsp;
  <a href="#find-something-you-copied">Clipboard</a> &nbsp;·&nbsp;
  <a href="#make-the-panel-yours">Customization</a> &nbsp;·&nbsp;
  <a href="#build-from-source">Build from source</a>
</p>

<p align="center">
  <img src="docs/images/mystatus-menu-bar.jpg" width="740" alt="MyStatus menu bar panel with display, sound, Wi-Fi, CPU, memory, disk, and network cards">
  <br>
  <em>Material preview composed from two sections of the MyStatus menu bar panel.</em>
</p>

---

## Getting started

1. **Download and unzip.** Choose the MyStatus ZIP under **Assets** on the latest release page, then double-click it in Finder.
2. **Move the app to Applications.** Drag **MyStatus.app** into the **Applications** folder and open it.
3. **Open the panel.** Click the MyStatus status icon in the menu bar at the top of your screen. Hover over or click a card to see more detail, including with direct touch input.

Start with **Memory**, **Displays**, or **Sound**. The main panel shows the readings and controls you’re likely to use most. The detail pane gives you more room for charts, device choices, and settings. Click **Edit Controls** at the bottom of the panel to change which cards are shown.

> **First launch.** If macOS shows a developer verification message, see [Apple’s guide to opening apps safely](https://support.apple.com/en-us/102445). This release has not been notarized by Apple.

## Understand your Mac’s activity

<p align="center">
  <img src="docs/images/mystatus-system-details.jpg" width="740" alt="CPU and GPU charts and the memory pressure and usage rings in the app’s detail views">
  <br>
  <em>CPU and GPU details on the left, memory pressure and usage on the right.</em>
</p>

| Card | What to look at |
| --- | --- |
| **CPU** | The bars show recent activity. Blue is work done by your apps and pink is work done by the system. The small rings show individual cores. Hover over the card for CPU and GPU details. |
| **Memory** | The two rings show memory pressure and memory use. If your Mac feels slow, start with pressure. It shows how hard macOS is working to make room for your apps. The detail view breaks down app, wired, and compressed memory and shows swap use. |
| **Disk** | See how much space is available and how quickly the disk is reading or writing. Hover over the card to check individual volumes, per-process disk activity where available, and read/write history. |
| **Network** | See your current upload and download rates and their recent history. The detail pane shows traffic totals since launch, the active interfaces, and network activity by process where available. |
| **Sensors and battery** | Check temperatures, fan speeds, charge, and battery health when your Mac reports them. Hover over a fan or sensor reading for its history. The battery detail also shows cycle count and power flow where available. |

In a detail pane, hover over a supported chart or reading to open a larger history view. Choose a time range from 1 minute to 5 hours where available, then move the pointer over the chart to inspect a sample.

## Adjust display, sound, and connections

The **Displays** and **Sound** sliders are available directly in the panel. Use the details to see which display or sound device you’re adjusting.

<p align="center">
  <img src="docs/images/mystatus-display-and-wifi.jpg" width="740" alt="MyStatus display detail and Wi-Fi detail, including brightness, resolution, signal, and channel">
  <br>
  <em>Hover over Displays or Wi-Fi to open its detail pane.</em>
</p>

- **Displays.** Adjust the built-in screen or a compatible external monitor. Supported external displays can also expose a contrast slider. Available controls depend on your monitor and how it’s connected.
- **Sound.** Switch output and input devices. MyStatus can also adjust the volume of compatible HDMI or DisplayPort audio outputs. If your monitor can’t accept volume commands, **Software Volume** is available for supported outputs on macOS 14.2 or later.
- **Wi-Fi and Bluetooth.** Check connection status, Wi-Fi signal and channel, or battery levels for supported Bluetooth devices. To join a different Wi-Fi network, open **System Settings**.
- **Keyboard controls.** The **Media keys** option lets you use the brightness keys for a supported external display and the volume keys for a supported output. macOS asks for Accessibility access when you enable keyboard control.

## Find something you copied

Press <kbd>Shift</kbd> + <kbd>Command</kbd> + <kbd>V</kbd> to open clipboard history. Search, filter by type or source app, pin entries, or organize them with colored tags. Hover over or click an entry to open its preview. Double-click to copy the original content once and close the clipboard; press <kbd>Esc</kbd> to close both panes. Use **Copy plain text** in the context menu to remove formatting. Select an entry and press <kbd>Return</kbd> to reuse it; if it is copied rather than pasted, press <kbd>Command</kbd> + <kbd>V</kbd> in the target app.

<p align="center">
  <img src="docs/images/mystatus-clipboard-history.jpg" width="428" alt="MyStatus clipboard preview with sample file, note, link, color, and code entries">
  <br>
  <em>The clipboard preview with built-in sample entries.</em>
</p>

Clipboard history is stored locally in a user-only folder without encryption. You can pause recording, clear history, or exclude specific apps. Items marked as confidential or temporary by their source app are skipped.

## Make the panel yours

Use **Edit Controls** to turn cards on or off and drag them into the order you want. The combined battery, Wi-Fi, and volume icon and live network speeds are on by default. CPU and memory readouts are off by default and can be enabled separately in the menu bar readout settings.

In **Preferences**, choose a light or dark appearance or follow the system setting. Adjust how translucent the cards are, how strongly the background is tinted, and how much the desktop behind the panel is blurred. MyStatus uses Liquid Glass on macOS 26 and a frosted appearance on earlier versions.

<p align="center">
  <img src="docs/images/mystatus-light-and-dark.jpg" width="740" alt="MyStatus CPU and memory cards in light and dark appearance">
  <br>
  <em>Light and dark material preview. In the app, the glass samples what’s behind the panel.</em>
</p>

### Optional extensions

| Extension | What it adds |
| --- | --- |
| **Hanging Clipboard** | Keep copied images and screenshots at the top of the screen so you can preview, drag, or annotate them. |
| **Mos** | Smooth out mouse-wheel scrolling, reverse its direction separately from the trackpad, and set app-specific exceptions. |
| **CodeIsland** | See supported local AI coding sessions in a notch-style panel at the top of the display. |

Enable the extensions you want in **Edit Controls**. **Plugin updates** can check for new upstream versions. Hanging Clipboard and CodeIsland require macOS 14 or later.

---

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

---

<p align="center">
  Made by <a href="https://github.com/rainydaylu">rainydaylu</a> &nbsp;·&nbsp;
  <a href="THIRD_PARTY_NOTICES.md">Third-party credits and licenses</a>
  <br>
  <em>The bundled Mos code is licensed for noncommercial use.</em>
</p>
