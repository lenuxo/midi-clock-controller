import AppLocalization
import SwiftUI

struct LinkControls: View {
    @ObservedObject var model: AppModel
    let palette: ClockPalette

    private var ratioText: String {
        model.linkTempoScale < 1 ? "÷" + String(format: "%g", 1 / model.linkTempoScale)
            : "×" + String(format: "%g", model.linkTempoScale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button { model.setLinkEnabled(!model.linkEnabled) } label: {
                    Label("Link", systemImage: "link")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .foregroundStyle(model.linkEnabled ? palette.accent : palette.secondary)
                        .background(model.linkEnabled ? palette.accent.opacity(0.12) : palette.background,
                                    in: RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(model.linkEnabled ? palette.accent.opacity(0.45) : palette.border, lineWidth: 1))
                }.buttonStyle(.plain)
                    .disabled(model.playbackAction == .stop)
                    .accessibilityLabel(model.linkEnabled ? L("关闭 Ableton Link") : L("启用 Ableton Link"))
                    .accessibilityValue(model.linkEnabled ? L("已开启") : L("已关闭"))
                    .help(model.playbackAction == .stop ? L("请先停止主控，再切换 Link。") : L("共享速度与拍点；修改主控速度会影响 Link 会话。"))
                Text(model.linkEnabled ? (model.linkPeers == 0 ? L("暂无其他参与者") : L("%1$@ 个其他参与者", String(model.linkPeers))) : L("本地时钟"))
                    .font(.system(size: 11)).foregroundStyle(palette.secondary)
                    .help(model.linkEnabled ? L("数量表示其他 Link 应用或设备，不包含本机 MIDI 输出。暂无参与者时，请检查双方 Link 开关、网络和本地网络权限。") : L("启用 Ableton Link"))
                Spacer(minLength: 0)
                if model.linkEnabled {
                    Menu {
                        Toggle(L("同步开始与停止"), isOn: Binding(get: { model.linkStartStopSync }, set: model.setLinkStartStopSync))
                            .help(L("双方开启后交换新的启停命令；加入会话或开启此选项不会自动播放。"))
                        Divider()
                        Picker(L("开始对齐"), selection: Binding(get: { model.linkQuantum }, set: model.setLinkQuantum)) {
                            Text(L("下一拍")).tag(1)
                            Text(L("每 4 拍")).tag(4)
                        }.disabled(model.playbackAction == .stop)
                            .help(L("开始、继续和从头开始对齐此边界；停止不等待拍点。更改前请先停止主控。"))
                    } label: { Image(systemName: "slider.horizontal.3") }
                    .menuIndicator(.hidden)
                    .frame(width: 24, height: 24)
                    .accessibilityLabel(L("Link 设置"))
                    .help(L("设置 Link 启停联动和开始对齐方式"))
                }
            }
            if model.linkEnabled {
                Text(model.linkStartStopSync ? L("共享速度与启停 · 独立设备除外") : L("共享速度 · 启停由本机控制"))
                    .font(.system(size: 10)).foregroundStyle(palette.secondary)
                if model.linkTempoScale != 1 {
                    Text(L("Link %1$@ BPM · MIDI %2$@", String(format: "%.1f", model.linkSessionBPM), ratioText))
                        .font(.system(size: 10)).foregroundStyle(palette.accent)
                        .help(L("Link 会话速度超出 20–300 BPM，MIDI 按所示比例输出；数位屏显示折算后的 MIDI 速度。"))
                }
            }
        }
    }
}
