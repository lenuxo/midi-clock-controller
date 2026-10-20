# MIDI时钟控制器

[English](README.md) · 简体中文

一款 macOS 原生 MIDI 主时钟，用于让鼓机、合成器和其他 MIDI 设备保持节奏同步。基于 SwiftUI 与 CoreMIDI 构建，以硬件乐器为灵感，提供简洁紧凑的控制界面。

## 主要功能

- **统一主控，按需独立**：同时控制多台设备的速度与播放，也可将任意设备切换为独立控制。
- **开始、继续与停止**：从头播放，或从设备停止的位置继续；「全部停止」覆盖所有连接设备。
- **精细调速**：支持 20–300 BPM、0.1 BPM 微调与长按加速，输出标准 24 PPQN MIDI 时钟。
- **专注的操作界面**：数码速度显示、浅色与深色主题，以及键盘快捷键。
- **设备故障隔离**：单台设备断线或失败不影响其他设备，重连后不会自动播放。断开设备整卡置灰，30 秒内未重连则自动移出列表。

## 下载与使用

从 [GitHub Releases](https://github.com/lenuxo/midi-clock-controller/releases/latest) 下载 DMG，打开后将应用拖入 **Applications（应用程序）**。预编译版本需要 **Apple Silicon 芯片和 macOS 13 或更高版本**。

连接 MIDI 设备，将硬件时钟源设为 **USB MIDI / External**，并开启接收 Start / Continue / Stop。在应用中设置 BPM，开始播放即可。设备默认跟随主控，需要单独调速或启停时可切换为独立控制。

应用目前采用 ad-hoc 签名，尚未经过 Apple 公证。如被 macOS 拦截，请按发布说明中的首次打开步骤操作。「继续播放」保留各设备自己的停止位置，不会对齐不同设备的乐曲位置。

## 从源码构建

需要 Swift 5.9+ 和 macOS SDK（Xcode 或兼容工具链）。

```sh
zsh scripts/build-app.sh
open "dist/MIDI Clock Controller.app"
```

运行 `zsh scripts/build-dmg.sh` 可将构建好的应用打包为 DMG，输出位于 `dist/release/`。

测试与开发流程见[贡献指南](CONTRIBUTING.md)，界面细节见[设计文档](DESIGN.md)。

## 致谢

由 **Duan** 开发。内置数码字体 DSEG7 Classic 由 keshikan 制作，采用 [SIL Open Font License 1.1](Sources/MIDIClockController/Resources/Fonts/DSEG-LICENSE.txt) 授权。
