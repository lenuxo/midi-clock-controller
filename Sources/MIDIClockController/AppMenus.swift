import AppLocalization
import AppKit
import SwiftUI

enum AppAbout {
    @MainActor static func show() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let credits = NSMutableAttributedString(
            string: L("作者 Duan\n\n"),
            attributes: [.font: NSFont.systemFont(ofSize: 12), .paragraphStyle: paragraph]
        )
        credits.append(NSAttributedString(
            string: "GitHub · lenuxo/midi-clock-controller",
            attributes: [
                .link: URL(string: "https://github.com/lenuxo/midi-clock-controller")!,
                .font: NSFont.systemFont(ofSize: 11),
                .paragraphStyle: paragraph
            ]
        ))
        credits.append(NSAttributedString(string: "\n\nAbleton Link 4.1.1 · Asio · DSEG7 Classic · Sparkle\n",
                                         attributes: [.font: NSFont.systemFont(ofSize: 10), .paragraphStyle: paragraph]))
        let bundledLicenses = Bundle.main.resourceURL?.appendingPathComponent("ThirdPartyLicenses", isDirectory: true)
        let licenseURL = bundledLicenses.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            ?? URL(string: "https://github.com/Ableton/link/blob/Link-4.1.1/LICENSE.md")!
        credits.append(NSAttributedString(string: L("查看第三方授权"), attributes: [
            .link: licenseURL, .font: NSFont.systemFont(ofSize: 10), .paragraphStyle: paragraph
        ]))
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: L("app.name"), .credits: credits])
    }
}

struct AppMenus: Commands {
    @ObservedObject var model: AppModel
    @Binding var showingHelp: Bool
    @ObservedObject var updateChecker: UpdateChecker
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("appLanguage") private var language = AppLanguage.current
    @AppStorage("interfaceZoom") private var zoomPercent = 100

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(L("关于 MIDI Clock"), action: AppAbout.show)
        }
        CommandGroup(after: .appInfo) {
            Button(L(updateChecker.isChecking ? "正在检查更新…" : "检查更新…"), action: updateChecker.check)
                .disabled(updateChecker.isChecking || updateChecker.isPresenting || showingHelp)
            Divider()
            Picker("语言 / Language", selection: Binding(
                get: { language },
                set: { selected in
                    guard selected != language else { return }
                    language = selected
                    UserDefaults.standard.set([selected], forKey: "AppleLanguages")
                    let alert = NSAlert()
                    alert.messageText = L("语言将在下次启动时生效")
                    alert.informativeText = L("退出并重新打开 MIDI Clock 后，全部界面和菜单将使用所选语言。当前 MIDI 播放不会中断。")
                    alert.addButton(withTitle: L("好"))
                    alert.runModal()
                }
            )) {
                Text("简体中文").tag("zh-Hans")
                Text("English").tag("en")
            }
        }
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .sidebar) {
            Picker(L("外观"), selection: $appearance) {
                Text(L("跟随系统")).tag("system")
                Text(L("浅色")).tag("light")
                Text(L("深色")).tag("dark")
            }
            Divider()
            Button(L("放大界面")) { zoomPercent = InterfaceZoom.adjusted(zoomPercent, by: 10) }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(zoomPercent >= InterfaceZoom.maximum)
            Button(L("缩小界面")) { zoomPercent = InterfaceZoom.adjusted(zoomPercent, by: -10) }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(zoomPercent <= InterfaceZoom.minimum)
            Button(L("实际大小（100%）")) { zoomPercent = 100 }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(zoomPercent == 100)
        }
        CommandMenu(L("播放")) {
            Button(model.playbackAction == .resume ? L("继续主控播放") : L("开始主控播放")) {
                model.performPlaybackAction()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(showingHelp || !model.canStartMaster || model.playbackAction == .stop)
            Button(L("停止主控"), action: model.stopMaster)
                .keyboardShortcut(".", modifiers: .command)
                .disabled(model.playbackAction != .stop)
            Button(L("跟随设备全部从头开始"), action: model.startMaster)
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(showingHelp || model.playbackAction != .resume)
            Divider()
            Button(L("全部停止"), action: model.stopAll)
                .keyboardShortcut(".", modifiers: [.command, .shift])
                .disabled(model.playingCount == 0 && !model.masterRunning)
            Divider()
            Button(L("加入等待中的跟随设备"), action: model.startMaster)
                .disabled(showingHelp || model.playbackAction != .stop || model.pendingFollowers.isEmpty)
            Button(L("刷新 MIDI 设备"), action: model.refreshOutputs)
                .keyboardShortcut("r", modifiers: .command)
                .disabled(showingHelp)
        }
        CommandGroup(replacing: .help) {
            Button(L("MIDI Clock 使用指南…")) { showingHelp = true }
                .disabled(showingHelp || updateChecker.isChecking || updateChecker.isPresenting)
        }
    }
}

struct QuickHelpView: View {
    @ObservedObject var model: AppModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("MIDI Clock 使用指南")).font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    tip(L("连接设备"), L("通过 USB 连接，将设备时钟设为 External，并开启接收 Start / Continue / Stop。"))
                    tip(L("播放与同步"), L("主控控制跟随 MIDI 设备；独立设备自行启停。停止后可继续或从头开始。继续保留设备自己的位置，不保证乐曲位置一致。"))
                    tip("Ableton Link", L("停止主控后，在 Link 会话卡片点击「加入」，共享速度和拍点。主控改速会影响会话。参与者数量不包含本机 MIDI 输出；没有其他参与者时仍可运行。"))
                    tip(L("Link 启停联动"), L("加入会话后，在「启停控制」中选择「本机」或「联动」。联动需双方开启，切换不会自动播放。下方「MIDI 开始对齐」单独控制下一拍或每 4 拍启动；停止立即执行。"))
                    tip(L("全部停止"), L("停止本机所有 MIDI 设备、取消待开始任务并关闭 Link 启停联动；其他 Link 参与者继续运行。"))
                    tip(L("独立控制"), L("独立设备可单独调速和启停；开启「随主控启动」后，可在自己的 BPM 下一起开始。主控停止仍保持独立播放，全部停止可停止所有设备。断线重连不自动播放。"))
                    tip(L("调整 BPM"), L("点击数字编辑，Enter 确认、Esc 取消；↑↓ 微调。非编辑时 ↑↓ 调整主控速度，长按方向键或加减键会逐渐加速。"))
                    tip(L("速度折算"), L("Link 速度超出 20–300 BPM 时，MIDI 按显示的倍速或半速比例输出，数位屏显示 MIDI 速度。"))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("快捷键")).fontWeight(.semibold)
                        shortcut(L("开始 / 继续主控"), "⌘Return")
                        shortcut(L("跟随设备从头开始"), "⇧⌘Return")
                        shortcut(L("停止主控"), "⌘.")
                        shortcut(L("全部停止"), "⇧⌘.")
                        shortcut(L("刷新设备"), "⌘R")
                        shortcut(L("放大界面"), "⌘+")
                        shortcut(L("缩小界面"), "⌘−")
                        shortcut(L("实际大小（100%）"), "⌘0")
                    }
                }.font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                    .background(OverlayScrollbars())
            }
            HStack {
                Button(L("全部停止"), action: model.stopAll)
                    .keyboardShortcut(".", modifiers: [.command, .shift])
                    .disabled(model.playingCount == 0 && !model.masterRunning)
                Spacer()
                Button(L("完成"), action: close).keyboardShortcut(.cancelAction)
            }
        }.padding(20).frame(width: 340, height: 340)
    }

    private func tip(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).fontWeight(.semibold)
            Text(body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func shortcut(_ title: String, _ keys: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(keys).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
        }
    }
}
