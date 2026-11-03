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
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Ableton Link").font(.headline)
                Text(model.linkEnabled
                     ? (model.linkPeers == 0 ? L("暂无其他参与者") : L("%1$@ 个其他参与者", String(model.linkPeers))) : L("未加入"))
                    .font(.caption).foregroundStyle(palette.secondary)
                    .help(L("数量表示其他 Link 应用或设备，不包含本机 MIDI 输出。暂无参与者时，请检查双方 Link 开关、网络和本地网络权限。"))
                Spacer(minLength: 0)
                Button {
                    model.setLinkEnabled(!model.linkEnabled)
                } label: {
                    Text(model.linkEnabled ? L("退出") : L("加入"))
                        .frame(minHeight: 28)
                }
                .buttonStyle(RestartButtonStyle(palette: palette))
                .disabled(model.playbackAction == .stop)
                .accessibilityLabel(model.linkEnabled ? L("退出 Link 会话") : L("加入 Link 会话"))
                .help(model.playbackAction == .stop ? L("请先停止主控，再切换 Link。") : model.linkEnabled ? L("退出后使用本地时钟，保留当前速度。") : L("加入后共享速度和拍点，不会自动开始播放。"))
            }.padding(.horizontal, 16).padding(.vertical, 12)
            sessionCard.padding(.horizontal, 12)
            if model.linkEnabled {
                Text(L("Link 不提供参与者名称及逐台同步状态。"))
                    .font(.system(size: 10)).foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.top, 8)
            }
        }
        .foregroundStyle(palette.text)
    }

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.linkEnabled {
                if model.linkTempoScale != 1 {
                    Text(L("Link %1$@ BPM · MIDI %2$@", String(format: "%.1f", model.linkSessionBPM), ratioText))
                        .font(.system(size: 10)).foregroundStyle(palette.accent)
                        .help(L("Link 会话速度超出 20–300 BPM，MIDI 按所示比例输出；数位屏显示折算后的 MIDI 速度。"))
                }
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("启停控制")).font(.system(size: 11)).foregroundStyle(palette.secondary)
                        ClockChoiceControl(value: !model.linkStartStopSync, first: L("本机"), second: L("联动"),
                                           label: L("启停控制"), palette: palette, width: nil,
                                           select: { model.setLinkStartStopSync(!$0) })
                            .help(L("双方开启后交换新的启停命令；加入会话或开启此选项不会自动播放。"))
                    }.frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("MIDI 开始对齐")).font(.system(size: 11)).foregroundStyle(palette.secondary)
                        ClockChoiceControl(value: model.linkQuantum == 1, first: L("下一拍"), second: L("每 4 拍"),
                                           label: L("MIDI 开始对齐"), palette: palette, width: nil,
                                           select: { model.setLinkQuantum($0 ? 1 : 4) })
                            .disabled(model.playbackAction == .stop)
                    }.frame(maxWidth: .infinity)
                        .help(L("开始、继续和从头开始对齐此边界；停止不等待拍点。更改前请先停止主控。"))
                }
                Text(model.linkStartStopSync ? L("与同样开启联动的参与者互相启停；独立设备除外。")
                     : L("仅由本机控制 MIDI 启停，不跟随远端播放操作。"))
                    .font(.system(size: 10)).foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(L("加入后共享速度与拍点，启停默认由本机控制。"))
                    .font(.system(size: 11)).foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.panel, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(palette.border, lineWidth: 1))
    }
}
