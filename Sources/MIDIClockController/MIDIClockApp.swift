import AppKit
import SwiftUI
import ClockCore

@main
struct MIDIClockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = MIDIClockApp.makeAppModel()
    @State private var showingHelp = false
    @MainActor private static func makeAppModel() -> AppModel {
        #if DEBUG
        if Bundle.main.bundleIdentifier == "local.midi-clock-controller.preview" { return previewModel() }
        #endif
        return AppModel()
    }
    var body: some Scene {
        Window("MIDI Clock", id: "main") {
            ContentView(model: model).onAppear { delegate.model = model }
                .sheet(isPresented: $showingHelp) { QuickHelpView(model: model, close: { showingHelp = false }) }
        }
        .defaultSize(width: 380, height: 560)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .windowResizability(.contentSize)
        .commands { AppMenus(model: model, showingHelp: $showingHelp) }
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
                            if !model.devices.isEmpty {
                                Text("\(model.onlineDevices.count) 在线 · \(model.playingCount) 播放中")
                                    .font(.caption).foregroundStyle(palette.secondary)
                            }
                            Spacer()
                            Button(action: model.refreshOutputs) { Image(systemName: "arrow.clockwise") }
                                .accessibilityLabel("刷新设备").help("刷新 MIDI 输出")
                        }.padding(.horizontal, 16).padding(.vertical, 12)
                        if model.devices.isEmpty {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "cable.connector")
                                    .font(.system(size: 18)).foregroundStyle(palette.secondary)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("连接 MIDI 设备").font(.system(size: 12, weight: .medium))
                                    Text("通过 USB 连接，并将设备时钟设为 External。")
                                        .font(.caption).foregroundStyle(palette.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }.padding(.horizontal, 20).padding(.vertical, 14)
                        } else {
                            LazyVStack(spacing: 6) {
                                ForEach(Array(model.devices.enumerated()), id: \.element.id) { index, device in
                                    DeviceRow(device: device, number: index + 1, masterRunning: model.masterRunning, palette: palette,
                                              setFollowing: { model.setFollowing(device, $0) })
                                }
                            }.padding(.horizontal, 12)
                        }
                        if let notice = model.notice {
                            Text(notice).font(.caption).foregroundStyle(palette.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16).padding(.top, 12)
                        }
                        #if DEBUG
                        if Bundle.main.bundleIdentifier == "local.midi-clock-controller.preview" {
                            Text("交互预览 · 不发送 MIDI 消息")
                                .font(.caption).foregroundStyle(palette.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16).padding(.top, 12)
                        }
                        #endif
                    }.padding(.bottom, 16)
                }
            }.background(palette.background).foregroundStyle(palette.text)
        .frame(minWidth: 380, maxWidth: 380, minHeight: 360, maxHeight: .infinity)
        .tint(palette.accent)
        .preferredColorScheme(scheme)
        .background(WindowAppearance(background: palette.background))
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
                .menuIndicator(.hidden)
                .help("外观：跟随系统 / 浅色 / 深色").accessibilityLabel("选择亮暗主题")
                Button(action: model.stopAll) {
                    Label("全部停止", systemImage: "stop.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.text)
                        .padding(.horizontal, 7).padding(.vertical, 5)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(palette.border, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.playingCount == 0)
                .help("停止所有设备，包括独立设备 · ⇧⌘.")
            }
        }


    }

    private var masterStatusText: String {
        if model.onlineDevices.isEmpty { return "未连接设备" }
        if model.followers.isEmpty { return "无跟随设备" }
        switch model.playbackAction {
        case .start: return "就绪"
        case .resume: return "已停止"
        case .stop: return "播放中"
        }
    }

    private var masterActionTitle: String {
        switch model.playbackAction {
        case .start: return "开始播放"
        case .resume: return "继续播放"
        case .stop: return "停止"
        }
    }

    private var transport: some View {
        VStack(spacing: 6) {
            Button(action: model.performPlaybackAction) {
                Label(masterActionTitle, systemImage: model.playbackAction == .stop ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(InstrumentButtonStyle(palette: palette, emphasized: model.playbackAction != .stop))
            .help(model.playbackAction == .stop ? "停止所有跟随设备" : model.playbackAction == .resume ? "跟随设备从各自停留位置继续" : "所有跟随设备从序列开头播放")
            if model.playbackAction == .resume {
                Button("全部从头开始", action: model.startMaster)
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .help("仅跟随设备从序列开头播放，不影响独立设备")
            }
        }.disabled(model.followers.isEmpty)
    }

    private var masterPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("主控时钟").font(.headline)
                    Spacer(minLength: 8)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(model.playbackAction == .stop ? palette.playing : palette.secondary)
                            .frame(width: 5, height: 5)
                            .accessibilityHidden(true)
                        Text(masterStatusText)
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(model.playbackAction == .stop ? palette.playing : palette.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("主控状态：" + masterStatusText)
                }
                Text("控制 \(model.followers.count) 台跟随设备 · \(model.independentCount) 台独立")
                    .font(.system(size: 11)).foregroundStyle(palette.secondary)
            }
            TempoControl(text: $model.masterBPMText, label: "主控速度 BPM", palette: palette, expanded: true,
                         commit: model.commitMasterBPM, step: { model.setMasterBPM(model.masterBPM + $0) })
            transport
            if model.playbackAction == .resume && model.resumableFollowers.count < model.followers.count {
                Text("可继续 \(model.resumableFollowers.count) 台，\(model.followers.count - model.resumableFollowers.count) 台需重新开始")
                    .font(.caption).foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.playbackAction == .stop && !model.pendingFollowers.isEmpty {
                Button("加入同步 · 等待中的设备从头开始", action: model.startMaster)
                    .font(.caption)
                    .help("只启动等待中的设备，不重启正在播放的设备；不保证小节位置一致")
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(palette.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
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
                VStack(spacing: 10) {
                    TempoControl(text: $device.bpmText, label: "\(device.output.name)独立 BPM", palette: palette, small: true, commit: device.commitBPM,
                                 step: { device.setBPM(device.bpm + $0) })
                    PlaybackControls(action: device.playbackAction, palette: palette,
                                     status: device.online ? nil : "已断开",
                                     perform: device.performPlaybackAction, restart: { device.start() })
                }.frame(maxWidth: .infinity).disabled(!device.online)
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
