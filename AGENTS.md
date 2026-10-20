# 仓库开发规则

## 项目约定

- 本项目是 macOS 13+ 原生 MIDI 主时钟，使用 Swift 5.9+、SwiftUI 和 CoreMIDI，无第三方依赖。新增依赖必须说明必要性。
- 开始修改前阅读 `README.md`、`DESIGN.md` 和相关源文件；当前界面规范以 `DESIGN.md` 为准，`design/retro-precision/` 为历史参考。
- 保持现有 Swift 风格：四空格缩进、类型名 UpperCamelCase、成员名 lowerCamelCase。避免无关重构和全文件格式化。
- `README.md` 默认使用英文，`README.zh-CN.md` 提供对应的简体中文版本；保持内容简洁且两版同步。其他协作说明使用中文，代码标识符保持英文。行为、构建命令或界面约定改变时同步更新文档。

## 模块边界与行为约束

- `ClockCore` 负责绝对时间轴和 MIDI 调度，不依赖 SwiftUI；`AppModel` 负责主控与设备状态；视图与主题留在应用模块。
- 保持 24 PPQN、20–300 BPM、基于 host time 的绝对时间轴；不要用 UI 定时器驱动 MIDI 时钟。
- 主控操作仅影响跟随设备；全部停止影响所有设备；设备故障隔离，重连不自动播放。
- 改动启停、改速、队列清理或退出流程时，验证已排程消息不会污染下一次运行，避免压缩间隔或补发过期脉冲。
- 不清空整个 destination 的输出队列，不干扰其他软件。软件发送成功不等于硬件已同步。
- Debug 预览保持无 MIDI 连接，模拟设备不得进入发布版。

## 文档查询（Context7）

- 涉及库、框架、SDK、API、CLI 或云服务的用法、配置、迁移及特定行为时，先用 Context7 查询当前文档，不凭记忆决定接口。
- 纯重构、自写脚本、业务逻辑调试、代码审查和一般编程概念不必查询。
- 先运行 `npx ctx7@latest library <name> "<具体问题>"`，根据名称、相关性、来源可信度和质量选择结果，再运行 `npx ctx7@latest docs <libraryId> "<具体问题>"`。用户直接提供有效 ID 时可省略解析。
- 每个查询围绕一个概念，保留问题的具体背景；每个问题最多三条命令。版本特定问题使用查询结果提供的版本 ID。查询不得包含凭据。
- Context7 CLI 请求在 Codex 默认沙箱外执行；遇到 DNS 或网络错误时，不在沙箱内反复重试。
- 配额耗尽时告知用户，建议运行 `npx ctx7@latest login` 或配置 `CONTEXT7_API_KEY`，不得静默退回记忆中的接口。文档未覆盖 Apple 接口时，明确限制并核对 Apple 官方文档及本机 SDK。

## 验证

- 测试：`CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" swift test --disable-sandbox`。
- 发布构建：`zsh scripts/build-app.sh`，输出为 `dist/MIDI Clock Controller.app`，使用本地 ad-hoc 签名。
- 调度和状态逻辑修改应补充有意义的回归测试；纯文档修改检查内容及差异即可。
- 集成测试仅使用私有虚拟端口，不向物理设备发送消息。需要强制验证 CoreMIDI 时设置 `REQUIRE_MIDI_TESTS=1`；报告跳过测试及原因，不把跳过当作验证成功。
- UI 修改验证浅色、深色、380 pt 宽度、滚动、键盘操作及错误状态；优先使用无 MIDI 连接的 Debug 预览。
- 最终说明实际执行的检查和结果，不复用历史通过记录。

## Git 与发布

- 默认分支为 `main`，后续功能或修复使用简短描述性分支。提交只包含本次相关改动，提交信息说明目的。
- 提交前查看 `git status` 和暂存差异；不覆盖他人改动，不擅自强制推送或重写已发布历史。
- 不提交 `.build/`、`.swiftpm/`、`dist/`、本机 Xcode 状态、密钥、令牌或签名证书。保留源码、测试和设计参考。
- 不擅自添加许可证、创建版本标签或 GitHub Release。源码推送与公开分发应用是不同操作，当前应用尚未完成 Developer ID 签名及公证。
