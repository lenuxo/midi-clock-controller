# 应用内更新与发布

应用采用固定版本的官方 Sparkle 2.10.1，负责下载、EdDSA 验签、安装和重启。此依赖用于复用成熟的 macOS 更新流程，SwiftPM 按 Package.resolved 和官方二进制校验和下载。MIT 授权及附带声明随 App 的 ThirdPartyLicenses 分发。

## 用户操作

应用菜单「检查更新…」先读取 GitHub 最新正式 Release。

- Release 附带 appcast.xml 时，Sparkle 展示更新说明，并提供下载和安装。用户确认「安装并重新启动」后，应用停止全部本机 MIDI、完成队列收尾并退出。Link 启停联动同时关闭，远端参与者继续运行。
- 旧 Release 缺少清单时，提供对应 GitHub Release 页面的手动下载入口。
- 自动检查、后台自动安装和系统信息上传均关闭。公开仓库查询不使用 GitHub Token。

首次包含 Sparkle 的版本需要手动安装一次，随后才能使用应用内升级。应用内升级不改变 ad-hoc 签名和未公证这一发布状态，Developer ID 与公证仍是后续发布工作。

## 更新信任与密钥

应用内置公钥位于 Resources/UpdatePublicKey.txt，构建时写入 SUPublicEDKey。正式私钥保存在发布者的 macOS 登录钥匙串中，账户名为 local.midi-clock-controller，由 Sparkle 的 generate_keys 创建。源码、应用、更新清单均不包含私钥。

使用同一私钥签署每次发布的更新包和清单。发布时需在已唤醒、解锁的 Mac 上允许官方工具访问钥匙串。私钥需由发布者安全备份。更换密钥需按 Sparkle 官方密钥轮换文档操作。

## 构建发布附件

1. 在 scripts/build-app.sh 中更新 CFBundleShortVersionString 和递增的 CFBundleVersion，并准备对应的 docs/releases/v版本.md。GitHub 标签使用相同版本，例如 v0.1.9。
2. 运行以下命令。

```sh
zsh scripts/build-app.sh
zsh scripts/build-dmg.sh
zsh scripts/build-update.sh
```

build-update.sh 会检查钥匙串公钥与 App 内公钥一致，创建保留框架符号链接的 ZIP，使用官方 generate_appcast 签署 ZIP、嵌入版本说明、写入架构与最低系统要求，并为清单签名。输出位于 dist/release/。可给脚本传入自定义说明文件路径。

```sh
zsh scripts/build-update.sh /absolute/path/release-notes.md
```

将该次版本的 DMG、完整对应源码、签名更新 ZIP、校验文件和 appcast.xml 上传到同一个 GitHub Release 草稿，确认齐全后再发布。脚本只生成本地文件，不上传或发布。ZIP 下载地址固定指向对应版本标签。修改更新包或清单后需重新签名。正式包版本与既有 Release 相同时，先递增版本再发布，避免覆盖历史附件。

运行时优先使用该 Release 的 appcast.xml 附件 URL。Info.plist 的默认地址为：

```
https://github.com/lenuxo/midi-clock-controller/releases/latest/download/appcast.xml
```

每个新 Release 都要附带新生成的清单。自动升级失败时，可通过 Release 页面下载 DMG 进行手动安装。

## 验证

- 运行完整 Swift 测试，版本检查使用模拟响应，CoreMIDI 测试仅使用私有虚拟端口。
- 发布 App 应通过 codesign --verify --deep --strict，包含 Sparkle.framework 的完整嵌套组件和授权。
- 隔离端到端测试使用 local.midi-clock-controller.preview Debug App、一次性测试密钥、本机 HTTP 清单及模拟 MIDI。发布版不支持本地清单环境变量。
- 验证旧版预览能下载、验签、替换并重启为新版，且篡改包被拒绝。测试 App 使用独立 Bundle ID，与正式 App 和正式更新密钥隔离。
- 本机锁屏或 Dark Wake 阻止钥匙串授权和界面操作时，需先解锁再完成实际安装验收。

官方文档见 [Sparkle 集成说明](https://sparkle-project.org/documentation/) 和[发布说明](https://sparkle-project.org/documentation/publishing/)。
