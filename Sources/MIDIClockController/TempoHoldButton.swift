import AppKit
import SwiftUI

struct TempoHoldButton: NSViewRepresentable {
    let symbol: String
    let label: String
    let palette: ClockPalette
    let direction: Double
    let step: (Double) -> Void
    @Environment(\.isEnabled) private var enabled

    func makeNSView(context: Context) -> HoldButton { HoldButton() }
    func updateNSView(_ button: HoldButton, context: Context) {
        button.title = symbol
        button.setAccessibilityLabel(label)
        button.toolTip = "短按微调 0.1 BPM；长按逐渐加速"
        button.ink = NSColor(palette.digits)
        button.direction = direction
        button.step = step
        button.isEnabled = enabled
        if !enabled { button.hold.stop() }
        button.needsDisplay = true
    }
    static func dismantleNSView(_ view: HoldButton, coordinator: ()) { view.hold.stop() }

    final class HoldButton: NSButton {
        let hold = TempoHold()
        var step: ((Double) -> Void)?
        var direction = 1.0
        var ink = NSColor.systemOrange
        private var trackingMouse = false
        private var hovering = false
        private var hoverArea: NSTrackingArea?

        init() {
            super.init(frame: .zero)
            isBordered = false
            setButtonType(.momentaryChange)
            target = self
            action = #selector(activate)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        @objc private func activate() {
            // Native accessibility/keyboard activation is a single step; mouse-down already applied it.
            if !trackingMouse && isEnabled { step?(direction * 0.1) }
        }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            guard isEnabled else { return }
            trackingMouse = true
            needsDisplay = true
            hold.start(direction: direction, allowed: { [weak self] in
                guard let self else { return false }
                return self.isEnabled && self.window != nil && self.trackingMouse
            }, action: { [weak self] in self?.step?($0) })
        }
        override func mouseDragged(with event: NSEvent) {
            if !visibleRect.contains(convert(event.locationInWindow, from: nil)) { endPress() }
        }
        override func mouseUp(with event: NSEvent) { endPress() }
        private func endPress() {
            hold.stop()
            trackingMouse = false
            needsDisplay = true
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { endPress() }
        }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let hoverArea { removeTrackingArea(hoverArea) }
            let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
            addTrackingArea(area)
            hoverArea = area
        }
        override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
        override func mouseExited(with event: NSEvent) { hovering = false; endPress() }
        override func draw(_ dirtyRect: NSRect) {
            ink.withAlphaComponent(isEnabled ? (trackingMouse ? 0.24 : hovering ? 0.13 : 0.04) : 0.02).setFill()
            NSBezierPath(rect: bounds).fill()
            let string = NSAttributedString(string: title, attributes: [
                .font: NSFont.systemFont(ofSize: 17, weight: .medium),
                .foregroundColor: ink.withAlphaComponent(isEnabled ? 1 : 0.35)
            ])
            let size = string.size()
            string.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
        }
    }
}
