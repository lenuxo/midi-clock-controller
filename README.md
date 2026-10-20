# MIDI Clock Controller

macOS 原生 USB MIDI 主时钟。SwiftUI + CoreMIDI，无第三方依赖，支持 macOS 13+。

开发协作请阅读 [贡献流程](CONTRIBUTING.md) 和 [仓库开发规则](AGENTS.md)。

## 下载安装

在 [v0.1.1 Release](https://github.com/lenuxo/midi-clock-controller/releases/tag/v0.1.1) 下载 `MIDI-Clock-v0.1.1-macOS-arm64.dmg`，双击打开后将 `MIDI Clock.app` 拖到旁边的 `Applications` 文件夹，拷贝完成后推出磁盘映像，再从「应用程序」启动。预编译应用需要 **Apple Silicon（M 系列芯片）和 macOS 13 或更高版本**，不包含 Intel 版本，也不需要安装 Xcode。

当前应用使用 ad-hoc 签名，未使用 Developer ID 签名、未经过 Apple 公证。首次打开可能被 macOS 拦截：确认下载来源可信后，先尝试打开应用，再到「系统设置 → 隐私与安全性」找到对应提示，选择「仍要打开」，按系统提示确认。参见 [Apple 官方说明](https://support.apple.com/102445)。

Release 同时提供 `MIDI-Clock-v0.1.1-macOS-arm64.dmg.sha256`。将它与 DMG 放在同一目录，在该目录运行 `shasum -a 256 -c MIDI-Clock-v0.1.1-macOS-arm64.dmg.sha256` 可检查下载是否完整。完整安装与使用说明见 [v0.1.1 发布说明](docs/releases/v0.1.1.md)。

## 使用：主控优先，按需独立

1. 连接 MIDI 设备，把设备时钟源设为 USB MIDI / External，并开启接收 Start/Continue/Stop。
2. 设备默认「跟随主控」。输入顶部 BPM 后回车或离开输入框，点击「开始播放」同时启动跟随设备。
3. 顶部的改速、从头开始、继续播放、停止只影响跟随设备。主控区始终显示操作范围和独立设备数量。
4. 需要特殊设置时，在设备行切换为「独立控制」。当前播放不中断，展开该设备自己的 BPM、从头开始、继续播放、停止。
5. 切回「跟随主控」会采用主控的速度和播放状态。已播放设备不强制重置音序位置，因此中途加入不保证小节位置一致；需要从头对齐时，停止主控后统一「从头开始」。
6. 右上角「全部停止」停止所有设备，包括独立设备。

快捷键：⌘Return 开始或继续主控，⇧⌘Return 停止后全部从头开始（仅跟随设备），⌘. 停止主控，⇧⌘. 全部停止，⌘R 刷新设备。

主按钮随状态显示「开始播放 → 停止 → 继续播放」，只有可继续时显示次要的「从头开始」（主控为「全部从头开始」，仅作用于跟随设备）。部分设备可继续时显示对应数量。

「开始播放」和「从头开始」发送 Start（FA），「继续播放」发送 Continue（FB），「停止」发送 Stop（FC）。播放中需先停止再选择从头或继续；主控运行时的「加入同步」只从头启动等待中的设备，不打断其他设备。继续播放仅对本次连接中成功播放并停止的设备启用，故障或断线后需从头开始；主控继续只恢复符合条件的跟随设备。Continue 保留各设备自己的停止位置，不保证乐曲位置一致。停止期间不发送 Clock，继续时使用当前 BPM，不补发停止期间的脉冲。

每台设备有独立状态和错误提示。断线或发送失败只停止该设备；重连后保持停止，主控运行时显示「等待开始」，点击「加入同步」即可加入，其他播放中的设备不重启。

每次启动应用，在线设备默认跟随主控，但不自动播放。保存主控速度；独立速度按设备 ID 保存。切换模式时使用当前速度，便于无中断接管。默认展示所有系统 MIDI 输出（含 USB、接口、虚拟端口）；连接重复路由时，应确保外部设备不会同时收到两路时钟。暂不支持 Tap Tempo、每设备延迟补偿和速度比例。

## 外观与窗口

右上角半明半暗图标可选择「跟随系统 / 浅色 / 深色」，选择会自动保存。深色为石墨灰，浅色为灰白，两种主题都使用琥珀色数码屏。窗口宽度固定为 380 pt，高度可调（最低 360 pt，默认 560 pt）；内容可滚动，顶部「全部停止」始终可见。标题栏与主体使用统一背景，不再用横线分隔。

无设备时显示简短的 USB / External 连接指引；底部只在需要时显示操作反馈，不常驻使用说明。

主控区采用整宽布局：顶部显示标题、状态和控制范围，速度屏与播放按钮共用左右边界，次要操作位于主按钮下方。

BPM 显示与加减键为一体化模块。点击数字进入编辑：↑ / ↓ 每次微调草稿 0.1 BPM，Enter 或点击外部确认，Esc 取消并恢复编辑前数值。允许范围为 20–300 BPM。

加减按钮短按调整 0.1 BPM，长按约 0.4 秒后开始连续调整，持续越久越快，松开或移出按钮即停止。没有输入框处于编辑状态时，↑ / ↓ 直接调整主控 BPM，支持相同长按加速，不改变独立设备。切换应用、窗口或打开菜单会中止长按；下一次按下重新从精细步长开始。

菜单栏「播放」提供主控操作和设备刷新；「显示 → 外观」与工具栏同步。简短操作说明可随时从「帮助 → MIDI Clock 使用指南」打开，Esc 关闭。查看指南时播放不中断，可在指南底部点击「全部停止」。

## 构建

需要 Xcode 或包含 macOS SDK 的 Swift 5.9+ 工具链：

```sh
zsh scripts/build-app.sh
open "dist/MIDI Clock.app"
```

构建 DMG（先运行上面的应用构建）：

```sh
zsh scripts/build-dmg.sh
```

输出安装包和 SHA-256 校验文件至 `dist/release/`；版本号从应用包读取，磁盘映像包含 Applications 拖拽入口。

可用 Xcode 打开 `Package.swift`。app 使用本地 ad-hoc 签名，尚未签名公证用于公开分发。

## 时钟与同步

- 每设备使用独立 CoreMIDI 引擎，状态和故障隔离。系统管理设备、USB 传输、协议转换和未来时间戳发送。
- 时钟使用 host time、专用串行队列和绝对时间轴，24 PPQN；每 2 ms 补充未来 8 ms 的消息。Start / Continue / Clock / Stop 为 MIDI 1.0 UMP System 消息，不要求硬件支持 MIDI 2.0。
- 主控先准备所有引擎，再提交共同的未来启动时间（约 50 ms）；Start 或 Continue 后 1 ms 发首个 Clock。主控停止也提交共同时间，独立停止通常约 9 ms。系统调度压力可能增加延迟。
- 主控改速约 50 ms 后，在各引擎的下一时钟点切换间隔；共同起点、同速且未受调度延误影响的引擎保持一致的时间戳。独立改速保留下一个待发拍点，再采用新间隔。
- 轻微迟到会整体后移后续脉冲以避免压缩间隔；超过一个间隔或 50 ms（取较小值）则停止该设备并报错。恢复不会补发一串旧脉冲。
- 不清空整个 destination 的输出队列，以免影响其他软件。停止、重启和退出会排空本引擎已经安排的 Stop，避免旧消息干扰新运行。
- 软件输出状态不代表硬件确认同步。不同 USB 路径、外设处理、单个引擎的迟到恢复仍可能产生相位偏差；这不是硬实时保证。

## 验证

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" swift test --disable-sandbox
```

测试覆盖绝对时间轴、百万脉冲误差、连续改速、快速启停与继续、停止后改速恢复、部分发送失败、共同启停时间、独立引擎速度、断线恢复、模式切换和主控/独立隔离。集成测试使用私有虚拟端口，不向物理设备发送消息。CoreMIDI 不可用时会跳过；设置 `REQUIRE_MIDI_TESTS=1` 可要求集成测试必须运行。

`PreviewSupport.swift` 仅在 Debug 中编译，专用 bundle ID `local.midi-clock-controller.preview` 启动模拟界面，不创建任何 MIDI 连接。正常发布版不包含预览设备。

## 项目结构

- `Sources/ClockCore/`：时钟时间轴和 MIDI 调度。
- `Sources/MIDIClockController/AppModel.swift`：主控与每设备状态、模式切换、断线恢复。
- `Sources/MIDIClockController/MIDIClockApp.swift`：主控优先的原生界面。
- `Sources/MIDIClockController/RetroComponents.swift`、`ClockTheme.swift`：复古 UI 组件与亮暗主题。
- `Sources/MIDIClockController/OutsideClickObserver.swift`：输入框外点击和编辑快捷键。
- `Tests/ClockCoreTests/`、`Tests/ControllerTests/`：时序与交互状态测试。
- `Resources/AppIcon.png`：应用图标原稿；构建时生成多尺寸 ICNS。
- `scripts/build-app.sh`：构建、生成图标资源和本地签名。
- `dist/MIDI Clock.app`：生成的正式应用，不作为源码管理。
- `design/retro-precision/`：历史视觉提案和组件稿；当前设计以 `DESIGN.md` 为准。
- `.build/`：可随时删除的 Swift 构建缓存，下次构建自动生成。

官方参考：[CoreMIDI](https://developer.apple.com/documentation/coremidi)、[SwiftUI](https://developer.apple.com/documentation/swiftui)、[MIDI 消息说明](https://midi.org/about-midi-part-3midi-messages)。接口已通过 Context7 官方文档及本机 SDK 核对。
