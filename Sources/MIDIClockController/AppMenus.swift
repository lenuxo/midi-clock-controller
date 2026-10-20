import SwiftUI

struct AppMenus: Commands {
    @ObservedObject var model: AppModel
    @Binding var showingHelp: Bool
    @AppStorage("appearance") private var appearance = "system"

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .sidebar) {
            Picker("外观", selection: $appearance) {
                Text("跟随系统").tag("system")
                Text("浅色").tag("light")
                Text("深色").tag("dark")
            }
        }
        CommandMenu("播放") {
            Button(model.playbackAction == .resume ? "继续主控播放" : "开始主控播放") {
                model.performPlaybackAction()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(showingHelp || model.followers.isEmpty || model.playbackAction == .stop)
            Button("停止主控", action: model.stopMaster)
                .keyboardShortcut(".", modifiers: .command)
                .disabled(model.playbackAction != .stop)
            Button("跟随设备全部从头开始", action: model.startMaster)
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(showingHelp || model.playbackAction != .resume)
            Divider()
            Button("全部停止", action: model.stopAll)
                .keyboardShortcut(".", modifiers: [.command, .shift])
                .disabled(model.playingCount == 0)
            Divider()
            Button("加入等待中的跟随设备", action: model.startMaster)
                .disabled(showingHelp || model.playbackAction != .stop || model.pendingFollowers.isEmpty)
            Button("刷新 MIDI 设备", action: model.refreshOutputs)
                .keyboardShortcut("r", modifiers: .command)
                .disabled(showingHelp)
        }
        CommandGroup(replacing: .help) {
            Button("MIDI Clock 使用指南…") { showingHelp = true }
                .disabled(showingHelp)
        }
    }
}

struct QuickHelpView: View {
    @ObservedObject var model: AppModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("MIDI Clock 使用指南").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    tip("连接设备", "通过 USB 连接，将设备时钟设为 External，并开启接收 Start / Continue / Stop。")
                    tip("播放与同步", "主控只影响跟随设备。停止后可继续播放，或选择全部从头开始。继续保留各设备自己的位置，不保证乐曲位置一致。")
                    tip("独立控制", "在设备行切换为独立，单独调整速度和播放。顶部「全部停止」会停止所有设备。断线重连后需手动开始。")
                    tip("调整 BPM", "点击数字编辑，Enter 确认、Esc 取消；↑↓ 微调。非编辑时 ↑↓ 调整主控速度，长按方向键或加减键会逐渐加速。")
                    VStack(alignment: .leading, spacing: 6) {
                        Text("快捷键").fontWeight(.semibold)
                        shortcut("开始 / 继续主控", "⌘Return")
                        shortcut("跟随设备从头开始", "⇧⌘Return")
                        shortcut("停止主控", "⌘.")
                        shortcut("全部停止", "⇧⌘.")
                        shortcut("刷新设备", "⌘R")
                    }
                }.font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("全部停止", action: model.stopAll)
                    .keyboardShortcut(".", modifiers: [.command, .shift])
                    .disabled(model.playingCount == 0)
                Spacer()
                Button("完成", action: close).keyboardShortcut(.cancelAction)
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
