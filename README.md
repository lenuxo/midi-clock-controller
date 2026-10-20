# MIDI Clock Controller

English · [简体中文](README.zh-CN.md)

A native macOS MIDI master clock for keeping drum machines, synthesizers, and other MIDI gear in time. Built with SwiftUI and CoreMIDI, with a compact interface inspired by hardware instruments.

## Features

- **One master, multiple devices** — control tempo and playback together, or switch any device to independent control.
- **Start, Continue, and Stop** — play from the beginning or resume from a device’s stopped position. Stop All covers every connected device.
- **Precise tempo control** — 20–300 BPM, 0.1 BPM adjustments, and press-and-hold acceleration, with standard 24 PPQN MIDI clock output.
- **A focused interface** — a digital tempo display, light and dark themes, and keyboard shortcuts.
- **Device isolation** — a disconnected or failed device does not interrupt the others; reconnecting never starts playback automatically.

## Download & use

Download the DMG from [GitHub Releases](https://github.com/lenuxo/midi-clock-controller/releases/latest), open it, and drag the app into **Applications**. Prebuilt releases require **Apple Silicon and macOS 13 or later**.

Connect your MIDI gear, set its clock source to **USB MIDI / External**, and enable Start / Continue / Stop reception. Choose a BPM in the app and start playback. Devices follow the master by default; use independent control when a device needs its own tempo or transport.

The app is currently ad-hoc signed and not notarized. If macOS blocks it, follow the first-launch instructions in the release notes. Continue preserves each device’s own position; it does not align song positions across devices.

## Build from source

Requires Swift 5.9+ with the macOS SDK (Xcode or a compatible toolchain).

```sh
zsh scripts/build-app.sh
open "dist/MIDI Clock Controller.app"
```

To package the built app as a DMG, run `zsh scripts/build-dmg.sh`. Output is saved in `dist/release/`.

See [Contributing](CONTRIBUTING.md) for tests and development workflow, and [Design](DESIGN.md) for interface details. These developer documents are currently in Chinese.

## Credits

Created by **Duan**. The bundled DSEG7 Classic font is by keshikan, licensed under the [SIL Open Font License 1.1](Sources/MIDIClockController/Resources/Fonts/DSEG-LICENSE.txt).
