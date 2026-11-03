# MIDI Clock Controller

English · [简体中文](README.zh-CN.md)

A native macOS MIDI master clock for keeping drum machines, synthesizers, and other MIDI gear in time. Built with SwiftUI and CoreMIDI, with a compact interface inspired by hardware instruments.

## Features

- **Ableton Link + MIDI** — share tempo, beat alignment, and optional Start/Stop sync with Link peers while driving USB MIDI hardware. Independent devices keep their own controls.
- **One master, multiple devices** — control tempo and playback together, or switch any device to independent control.
- **Start, Continue, and Stop** — play from the beginning or resume from a device’s stopped position. Stop All covers all local MIDI devices.
- **Precise tempo control** — 20–300 BPM, 0.1 BPM adjustments, and press-and-hold acceleration, with standard 24 PPQN MIDI clock output.
- **A focused interface** — a digital tempo display, light and dark themes, and keyboard shortcuts.
- **Device isolation** — a disconnected or failed device does not interrupt the others; reconnecting never starts playback automatically. Disconnected devices are dimmed and removed after 30 seconds unless they reconnect.

## Download & use

This page describes the current source. Check each release's notes for the features included in its download.

Download the DMG from [GitHub Releases](https://github.com/lenuxo/midi-clock-controller/releases/latest), open it, and drag the app into **Applications**. Prebuilt releases require **Apple Silicon and macOS 13 or later**.

Connect your MIDI gear, set its clock source to **USB MIDI / External**, and enable Start / Continue / Stop reception. Choose a BPM in the app and start playback. Devices follow the master by default; use independent control when a device needs its own tempo or transport. Each card labels **MIDI Clock** as its output protocol and identifies its beat source: Link, local master, or independent. A Link beat source means the app bridges Link to MIDI; it does not mean the hardware has a native Link connection.

The **Link Session** group shows other participants, shared tempo and beat timing, and local Start/Stop sync status. Link does not expose participant names or individual sync status. **MIDI Devices** continues to list each local MIDI output separately.

Stop the master and click **Join** in the Ableton Link card. **Transport → Local / Linked** controls optional Start/Stop sync (Local by default). **MIDI launch → Next beat / Every 4 beats** separately controls the MIDI start boundary; Stop is immediate. Joining never starts MIDI playback automatically. **Stop All** stops local MIDI and disables transport sync. Link is off at each app launch. See the [Link guide](docs/ableton-link.en.md) for behavior and testing.

The app is currently ad-hoc signed and not notarized. If macOS blocks it, follow the first-launch instructions in the release notes. Continue preserves each device’s own position; it does not align song positions across devices.

## Build from source

Requires Swift 5.9+ with the macOS SDK and C++17 support. The bundled Link SDK is officially verified with Xcode 16.2 or later.

```sh
zsh scripts/build-app.sh
open "dist/MIDI Clock Controller.app"
```

To package the built app as a DMG, run `zsh scripts/build-dmg.sh`. Output is saved in `dist/release/`.

See [Contributing](CONTRIBUTING.md) for tests and development workflow, and [Design](DESIGN.md) for interface details. These developer documents are currently in Chinese.

## Credits

Created by **Duan**. The bundled DSEG7 Classic font is by keshikan, licensed under the [SIL Open Font License 1.1](Sources/MIDIClockController/Resources/Fonts/DSEG-LICENSE.txt).

Link uses the official Ableton Link 4.1.1 SDK (GPLv2+ / proprietary dual licensing) and its Asio dependency (Boost Software License). Notices are in [the vendored SDK](Sources/CLink/vendor/README.md) and packaged with the app; About provides a third-party licenses link. This project is distributed under **GPL-2.0-or-later**; see [LICENSE](LICENSE) and [licensing and corresponding source](COPYING.md).
