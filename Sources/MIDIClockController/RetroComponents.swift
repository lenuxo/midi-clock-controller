import AppLocalization
import SwiftUI

/// The display and native editor use the same bundled seven-segment font.
struct SegmentDigits: View {
    let text: String
    let color: Color
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .trailing) {
            Text(String(text.map { $0.isNumber ? "8" : $0 }))
                .foregroundStyle(color.opacity(0.055))
            Text(text).foregroundStyle(color)
        }
        .font(SegmentFont.font(size: size))
        .fixedSize()
        .accessibilityHidden(true)
    }
}

struct TempoControl: View {
    @Binding var text: String
    let label: String
    let palette: ClockPalette
    var small = false
    var expanded = false
    let commit: () -> Bool
    let step: (Double) -> Void
    @FocusState private var focused: Bool
    @State private var editing = false
    @State private var originalText = ""
    var body: some View {
        HStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 10) {
            ZStack {
                if editing {
                    TextField(label, text: $text)
                        .textFieldStyle(.plain)
                        .font(SegmentFont.font(size: small ? 38 : 56))
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(palette.digits)
                        .background(TempoSelectionAppearance(background: palette.displaySelection, foreground: palette.digits, focused: focused))
                        .focused($focused)
                        .onAppear { DispatchQueue.main.async { focused = true } }
                        .onSubmit { if commit() { focused = false; editing = false } }
                        .accessibilityLabel(label)
                } else {
                    Button { originalText = text; editing = true } label: {
                        SegmentDigits(text: text, color: palette.digits, size: small ? 38 : 56)
                            .frame(width: small ? 130 : 188, height: small ? 38 : 56)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel(L("编辑") + label)
                        .accessibilityValue(text + " BPM")
                }
            }.frame(width: small ? 130 : 188, height: small ? 38 : 56)
                .background(OutsideClickObserver(active: editing, onOutsideClick: finishEditing,
                                                  handlesKeys: focused, onCancel: cancelEditing, onStep: stepDraft))
            Text("BPM").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(palette.digits).padding(.bottom, 2)
        }
            .frame(maxWidth: expanded ? .infinity : nil)
            .padding(12)
            .help(L("回车或点击外部确认 · Esc 取消 · ↑↓ 微调 0.1 · 20–300 BPM"))
            Rectangle().fill(palette.displayDivider).frame(width: 1)
            VStack(spacing: 0) {
                TempoHoldButton(symbol: "+", label: L("%1$@ 增加 BPM", String(label)), palette: palette, direction: 1, step: adjust)
                    .frame(maxHeight: .infinity)
                Rectangle().fill(palette.displayDivider).frame(height: 1)
                TempoHoldButton(symbol: "−", label: L("%1$@ 减少 BPM", String(label)), palette: palette, direction: -1, step: adjust)
                    .frame(maxHeight: .infinity)
            }.frame(width: 38)
        }
        .frame(height: small ? 64 : 80)
        .fixedSize(horizontal: !expanded, vertical: false)
        .background(palette.display)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(focused ? palette.digits.opacity(0.75) : palette.displayDivider, lineWidth: 1))
        .onChange(of: focused) { if !$0 { finishEditing() } }
    }
    private func cancelEditing() {
        // Arrow-key adjustments are drafts too: Escape never sends a tempo change.
        editing = false
        focused = false
        text = originalText
    }
    private func stepDraft(_ delta: Double) {
        guard let value = DeviceControl.parseBPM(text) else { return }
        text = String(format: "%.1f", min(300, max(20, value + delta)))
    }
    private func finishEditing() {
        guard editing else { return }
        // Invalid input must never become a misleading seven-segment readout.
        if !commit() { text = originalText }
        editing = false
        focused = false
    }
    private func adjust(_ delta: Double) {
        if editing && !commit() { return }
        focused = false
        editing = false
        step(delta)
    }

}

struct InstrumentButtonStyle: ButtonStyle {
    let palette: ClockPalette
    var emphasized = false
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12).frame(minHeight: 32)
            .foregroundStyle(emphasized && enabled ? palette.display : palette.text)
            .background(emphasized && enabled ? palette.digits.opacity(configuration.isPressed ? 0.7 : 1) : (hovered || configuration.isPressed ? palette.border : palette.panel), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(emphasized && enabled ? palette.digits : palette.secondary.opacity(0.65), lineWidth: 1))
            .opacity(enabled ? 1 : 0.35)
            .onHover { hovered = $0 }
    }
}

/// One primary action in a stable position; restart is only offered after stopping.
struct PlaybackControls: View {
    let action: PlaybackAction
    let palette: ClockPalette
    var restartTitle = L("从头开始")
    let perform: () -> Void
    let restart: () -> Void

    private var title: String {
        switch action {
        case .start: return L("开始播放")
        case .resume: return L("继续播放")
        case .stop: return L("停止")
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: perform) {
                Label(title, systemImage: action == .stop ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(InstrumentButtonStyle(palette: palette, emphasized: action != .stop))
            .help(action == .stop ? L("停止这台设备，保留当前位置") : action == .resume ? L("这台设备从停止位置继续播放") : L("这台设备从序列开头播放"))
            if action == .resume {
                Button(action: restart) {
                    Label(restartTitle, systemImage: "backward.end.fill")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                    .buttonStyle(RestartButtonStyle(palette: palette))
                    .help(L("仅这台设备从序列开头播放"))
            }
        }
    }
}

/// A quiet, tactile companion to the amber Continue button.
struct RestartButtonStyle: ButtonStyle {
    let palette: ClockPalette
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .foregroundStyle(palette.accent)
            .background(palette.accent.opacity(configuration.isPressed ? 0.18 : hovered ? 0.12 : 0.06),
                        in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4)
                .stroke(palette.accent.opacity(hovered ? 0.55 : 0.3), lineWidth: 1))
            .opacity(enabled ? 1 : 0.35)
            .onHover { hovered = $0 }
    }
}

/// Both routing modes stay visible; selecting the current mode is a no-op.
struct DeviceModeControl: View {
    let followsMaster: Bool
    let palette: ClockPalette
    let deviceName: String
    let select: (Bool) -> Void

    var body: some View {
        HStack(spacing: 2) {
            option(true, title: L("跟随"), description: L("跟随主控"))
            option(false, title: L("独立"), description: L("独立控制"))
        }
        .padding(3)
        .frame(width: AppLanguage.current == "en" ? 144 : 110)
        .background(palette.background, in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(palette.border, lineWidth: 1))
    }

    private func option(_ following: Bool, title: String, description: String) -> some View {
        Button {
            if followsMaster != following { select(following) }
        } label: {
            Text(title)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 24)
        }
        .buttonStyle(DeviceModeButtonStyle(palette: palette, selected: followsMaster == following))
        .accessibilityLabel(deviceName + " · " + description)
        .accessibilityAddTraits(followsMaster == following ? .isSelected : [])
        .help(description)
    }
}

private struct DeviceModeButtonStyle: ButtonStyle {
    let palette: ClockPalette
    let selected: Bool
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: selected ? .semibold : .medium))
            .foregroundStyle(selected ? palette.accent : palette.secondary)
            .background(selected ? palette.accent.opacity(configuration.isPressed ? 0.22 : 0.12)
                        : palette.secondary.opacity(hovered || configuration.isPressed ? 0.1 : 0),
                        in: RoundedRectangle(cornerRadius: 3))
            .overlay(alignment: .bottom) {
                if selected {
                    Capsule().fill(palette.accent).frame(width: 14, height: 2).padding(.bottom, 2)
                }
            }
            .opacity(enabled ? 1 : 0.4)
            .onHover { hovered = $0 }
    }
}
