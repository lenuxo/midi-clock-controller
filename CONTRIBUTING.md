# 参与开发

开始前请阅读 [README.md](README.md)、[开发规则](AGENTS.md) 和 [界面规范](DESIGN.md)。需要 macOS 13+、包含 macOS SDK 的 Swift 5.9+ 工具链及 C++17 支持；官方 Link SDK 的验证环境为 Xcode 16.2 或更新版本。

## 提交流程

1. 从最新 `main` 创建分支，如 `fix/clock-restart` 或 `feat/device-status`。
2. 保持改动聚焦；行为变化同步更新文档，调度和状态逻辑变化补充回归测试。
3. 运行相关检查，确认差异不包含构建产物、凭据或本机配置。
4. 提交信息说明变更目的，可使用 `fix:`、`feat:`、`docs:` 或 `chore:` 前缀。
5. Pull Request 说明解决的问题、变更后行为、验证结果和已知限制。界面变化附浅色及深色截图，时序变化说明测试覆盖范围。

## 常用检查

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" swift test --disable-sandbox
zsh scripts/build-app.sh
git diff --check
```

调度回归覆盖跟随设备延迟唤醒后逐步回到共同拍点，以及全部停止时先向所有设备排程、再等待消息送达。控制器测试还覆盖 MIDI 初始化失败后刷新重试、快速 Link 启停和编辑 BPM 期间的远端改速。

CoreMIDI 测试可能在服务不可用时跳过。需要完整 MIDI 验证时，在测试命令前设置 `REQUIRE_MIDI_TESTS=1`。测试只连接私有虚拟端口；涉及真实硬件的验证须明确设备和操作范围。

Link 真实网络测试默认跳过。设置 `REQUIRE_LINK_NETWORK_TESTS=1` 可强制运行官方 SDK 的双参与者发现、改速、拍点与启停验证；只在隔离测试网络运行，避免影响演出会话。Debug 预览使用模拟 Link 和 MIDI，不联网、不连接硬件。完整流程见 [Link 验证说明](docs/ableton-link.md#验证)。

第三方源码版本及必要性记录在 `Sources/CLink/vendor/README.md`；维护时保留上游授权；项目采用 GPL-2.0-or-later，发布时同时提供完整对应源码包及构建脚本。

`dist/` 中的应用仅作本地验证，使用 ad-hoc 签名。上传源码不代表应用已经完成公开分发签名或公证。
