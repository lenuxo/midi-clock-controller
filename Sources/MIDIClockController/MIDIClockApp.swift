import AppKit
import SwiftUI
import ClockCore

@main
struct MIDIClockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = MIDIClockApp.makeAppModel()
    @MainActor private static func makeAppModel() -> AppModel {
        #if DEBUG
        if Bundle.main.bundleIdentifier == "local.midi-clock-controller.preview" { return previewModel() }
        #endif
        return AppModel()
    }
    var body: some Scene {
        Window("MIDI Clock", id: "main") {
            ContentView(model: model).onAppear { delegate.model = model }
        }
        .defaultSize(width: 380, height: 560)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .windowResizability(.contentSize)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { model?.shutdown() }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @AppStorage("appearance") private var appearance = "system"
    @Environment(\.colorScheme) private var systemScheme
    private var scheme: ColorScheme? { appearance == "dark" ? .dark : appearance == "light" ? .light : nil }
    private var palette: ClockPalette { ClockPalette(dark: (scheme ?? systemScheme) == .dark) }

    var body: some View {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        masterPanel
                        HStack {
                            Text("设备").font(.headline)
                            Text("\(model.onlineDevices.count) 在线 · \(model.playingCount) 播放中")
                                .font(.caption).foregroundStyle(palette.secondary)
                            Spacer()
                            Button(action: model.refreshOutputs) { Image(systemName: "arrow.clockwise") }
                                .accessibilityLabel("刷新设备").help("刷新 MIDI 输出")
                        }.padding(.horizontal, 16).padding(.vertical, 12)
                        if model.devices.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "cable.connector").font(.title)
                                Text("连接你的第一台设备").font(.headline)
                                Text("连接 USB MIDI，并将设备设为外部时钟。识别后默认跟随主控，点击开始即可同步。")
                                    .foregroundStyle(palette.secondary).multilineTextAlignment(.center)
                            }.frame(maxWidth: .infinity).padding(24)
                        } else {
                            LazyVStack(spacing: 6) {
                                ForEach(Array(model.devices.enumerated()), id: \.element.id) { index, device in
                                    DeviceRow(device: device, number: index + 1, masterRunning: model.masterRunning, palette: palette,
                                              setFollowing: { model.setFollowing(device, $0) })
                                }
                            }.padding(.horizontal, 12)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            #if DEBUG
                            if Bundle.main.bundleIdentifier == "local.midi-clock-controller.preview" {
                                Text("交互预览 · 不发送 MIDI 消息")
                            }
                            #endif
                            if let notice = model.notice { Text(notice) }
                            Text("默认跟随主控。切换为独立后，可单独设置速度和启停；重连后需手动开始。")
                                .foregroundStyle(palette.secondary)
                        }.font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(18)
                    }
                }
            }.background(palette.background).foregroundStyle(palette.text)
        .frame(minWidth: 380, maxWidth: 380, minHeight: 360, maxHeight: .infinity)
        .tint(palette.accent)
        .preferredColorScheme(scheme)
        .background(MasterTempoKeyboard { delta in
            model.setMasterBPM(model.masterBPM + delta)
        })
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Text("MIDI CLOCK").font(.system(size: 13, weight: .bold, design: .monospaced)).tracking(1)
            }
            ToolbarItem(placement: .principal) { Spacer().frame(minWidth: 0, maxWidth: .infinity) }
            ToolbarItemGroup(placement: .confirmationAction) {
                Menu {
                    Picker("外观", selection: $appearance) {
                        Text("跟随系统").tag("system")
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                    }.pickerStyle(.inline)
                } label: { Image(systemName: "circle.lefthalf.filled") }
                .help("外观：跟随系统 / 浅色 / 深色").accessibilityLabel("选择亮暗主题")
                Button(action: model.stopAll) { Text("全部停止").foregroundStyle(palette.accent) }
                    .disabled(model.playingCount == 0)
                    .keyboardShortcut(".", modifiers: [.command, .shift])
            }
        }


    }

    private var masterStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(model.masterRunning ? (model.followers.contains(where: \.running) ? "播放中" : "等待设备") : "已停止",
                  systemImage: model.masterRunning ? "play.fill" : "stop.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(model.masterRunning ? palette.playing : palette.secondary)
            Text("\(model.followers.count) 台跟随 · \(model.independentCount) 台独立")
                .font(.system(size: 10)).foregroundStyle(palette.secondary)
        }
    }

    private var transport: some View {
        HStack(spacing: 10) {
            TransportKey(title: model.masterRunning && !model.pendingFollowers.isEmpty ? "加入同步" : "开始", symbol: "play.fill", palette: palette, primary: true, shortcut: KeyboardShortcut(.return, modifiers: .command), action: model.startMaster)
                .disabled(model.followers.isEmpty || (model.masterRunning && model.pendingFollowers.isEmpty))
            TransportKey(title: "停止", symbol: "stop.fill", palette: palette, shortcut: KeyboardShortcut(".", modifiers: .command), action: model.stopMaster)
                .disabled(!model.masterRunning && !model.followers.contains(where: \.running))
        }
    }

    private var masterPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("主控时钟").font(.headline)
            HStack {
                Spacer(minLength: 0)
                TempoControl(text: $model.masterBPMText, label: "主控速度 BPM", palette: palette, commit: model.commitMasterBPM,
                             step: { model.setMasterBPM(model.masterBPM + $0) })
                Spacer(minLength: 0)
            }
            HStack {
                transport
                Spacer(minLength: 8)
                masterStatus
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(palette.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.panel, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(palette.border, lineWidth: 1))
        .padding(.horizontal, 12).padding(.top, 12)
    }

}

struct DeviceRow: View {
    @ObservedObject var device: DeviceControl
    let number: Int
    let masterRunning: Bool
    let palette: ClockPalette
    let setFollowing: (Bool) -> Void

    var stateLabel: String {
        if !device.online { return "已断开" }
        if device.running { return "播放中" }
        if device.followsMaster && masterRunning { return "等待开始" }
        return "已停止"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(format: "%02d", number))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.secondary)
                Text(device.output.name).font(.system(size: 13, weight: .semibold))
                    .lineLimit(2).help(device.output.name)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                Label(stateLabel, systemImage: device.running ? "play.fill" : "stop.fill")
                    .font(.system(size: 11)).foregroundStyle(device.running ? palette.playing : palette.secondary)
                if device.followsMaster {
                    Text(String(format: "%.1f BPM", device.bpm))
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.secondary)
                }
                Spacer(minLength: 0)
                Picker("控制方式", selection: Binding(get: { device.followsMaster }, set: setFollowing)) {
                    Text("跟随主控").tag(true)
                    Text("独立控制").tag(false)
                }.labelsHidden().frame(width: 110).disabled(!device.online)
                    .accessibilityLabel("\(device.output.name)控制方式")
            }
            if !device.followsMaster {
                HStack(spacing: 10) {
                    TempoControl(text: $device.bpmText, label: "\(device.output.name)独立 BPM", palette: palette, small: true, commit: device.commitBPM,
                                 step: { device.setBPM(device.bpm + $0) })
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        TransportKey(title: "开始", symbol: "play.fill", palette: palette, primary: true, small: true, action: { device.start() })
                            .disabled(device.running)
                        TransportKey(title: "停止", symbol: "stop.fill", palette: palette, small: true, action: { device.stop() })
                            .disabled(!device.running)
                    }
                }.disabled(!device.online)
            }
            if let error = device.error {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(palette.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(palette.panel, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(device.followsMaster ? palette.border : palette.accent.opacity(0.7), lineWidth: 1))
    }
}
