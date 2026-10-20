import SwiftUI

/// Vector display only. A native text field handles selection, caret, input and VoiceOver.
struct SegmentDigits: View {
    let text: String
    let color: Color
    var body: some View {
        Canvas { context, size in
            let glyphs = Array(text)
            let units = glyphs.reduce(0.0) { $0 + ($1 == "." ? 0.28 : 1) }
            let w = min(size.height * 0.58, size.width / max(1, units))
            let h = size.height
            let t = h * 0.075
            let masks = [0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F]
            var x = size.width - units * w
            for character in glyphs {
                if character == "." {
                    context.fill(Path(ellipseIn: CGRect(x: x + t, y: h - t * 1.4, width: t, height: t)), with: .color(color))
                    x += w * 0.28
                    continue
                }
                let mask = character.wholeNumberValue.map { masks[$0] } ?? 0
                let rects = [
                    CGRect(x: x+t, y: 0, width: w-3*t, height: t),
                    CGRect(x: x+w-2*t, y: t, width: t, height: h/2-1.5*t),
                    CGRect(x: x+w-2*t, y: h/2+t/2, width: t, height: h/2-1.5*t),
                    CGRect(x: x+t, y: h-t, width: w-3*t, height: t),
                    CGRect(x: x, y: h/2+t/2, width: t, height: h/2-1.5*t),
                    CGRect(x: x, y: t, width: t, height: h/2-1.5*t),
                    CGRect(x: x+t, y: h/2-t/2, width: w-3*t, height: t)
                ]
                for (index, rect) in rects.enumerated() {
                    context.fill(Path(roundedRect: rect, cornerRadius: t/3), with: .color(color.opacity(mask & (1 << index) != 0 ? 1 : 0.055)))
                }
                x += w
            }
        }.accessibilityHidden(true)
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
                        .font(.system(size: small ? 32 : 46, weight: .medium, design: .monospaced))
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(palette.digits)
                        .focused($focused)
                        .onAppear { DispatchQueue.main.async { focused = true } }
                        .onSubmit { if commit() { focused = false; editing = false } }
                        .accessibilityLabel(label)
                } else {
                    Button { originalText = text; editing = true } label: {
                        SegmentDigits(text: text, color: palette.digits)
                            .frame(width: small ? 118 : 154, height: small ? 38 : 56)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel("编辑" + label)
                        .accessibilityValue(text + " BPM")
                }
            }.frame(width: small ? 118 : 154, height: small ? 38 : 56)
                .background(OutsideClickObserver(active: editing, onOutsideClick: finishEditing,
                                                  handlesKeys: focused, onCancel: cancelEditing, onStep: stepDraft))
            Text("BPM").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(palette.digits).padding(.bottom, 2)
        }
            .frame(maxWidth: expanded ? .infinity : nil)
            .padding(12)
            .help("回车或点击外部确认 · Esc 取消 · ↑↓ 微调 0.1 · 20–300 BPM")
            Rectangle().fill(palette.border).frame(width: 1)
            VStack(spacing: 0) {
                TempoHoldButton(symbol: "+", label: "\(label)增加 BPM", palette: palette, direction: 1, step: adjust)
                    .frame(maxHeight: .infinity)
                Rectangle().fill(palette.border).frame(height: 1)
                TempoHoldButton(symbol: "−", label: "\(label)减少 BPM", palette: palette, direction: -1, step: adjust)
                    .frame(maxHeight: .infinity)
            }.frame(width: 38)
        }
        .frame(height: small ? 64 : 80)
        .fixedSize(horizontal: !expanded, vertical: false)
        .background(palette.display)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(focused ? palette.digits : palette.border, lineWidth: focused ? 2 : 1))
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
    var detail: String? = nil
    var status: String? = nil
    var restartTitle = "从头开始"
    let perform: () -> Void
    let restart: () -> Void

    private var title: String {
        switch action {
        case .start: return "开始播放"
        case .resume: return "继续播放"
        case .stop: return "停止"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button(action: perform) {
                    Label(title, systemImage: action == .stop ? "stop.fill" : "play.fill")
                        .frame(width: 96, height: 36)
                }
                .buttonStyle(InstrumentButtonStyle(palette: palette, emphasized: action != .stop))
                .help(action == .stop ? "停止播放，保留当前位置" : action == .resume ? "从各自停留位置继续播放" : "从序列开头播放")
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    Label(status ?? (action == .stop ? "播放中" : action == .resume ? "已停止" : "就绪"),
                          systemImage: action == .stop ? "play.fill" : "stop.fill")
                        .foregroundStyle(action == .stop ? palette.playing : palette.secondary)
                    if let detail { Text(detail).foregroundStyle(palette.secondary) }
                }.font(.system(size: 11))
            }
            if action == .resume {
                Button(restartTitle, action: restart)
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.accent)
                    .padding(.vertical, 4)
                    .help("放弃停止位置，从序列开头播放；主控只影响跟随设备")
            }
        }
    }
}
