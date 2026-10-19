import AppKit
import SwiftUI

/// Observe clicks without consuming them; handle editing keys only while this editor is focused.
struct OutsideClickObserver: NSViewRepresentable {
    var active: Bool
    var onOutsideClick: () -> Void
    var handlesKeys = false
    var onCancel: () -> Void = {}
    var onStep: (Double) -> Void = { _ in }

    func makeNSView(context: Context) -> ObserverView { ObserverView() }
    func updateNSView(_ view: ObserverView, context: Context) {
        view.onOutsideClick = onOutsideClick
        view.handlesKeys = handlesKeys
        view.onCancel = onCancel
        view.onStep = onStep
        view.setActive(active)
    }
    static func dismantleNSView(_ view: ObserverView, coordinator: ()) { view.setActive(false) }

    final class ObserverView: NSView {
        var onOutsideClick: (() -> Void)?
        var handlesKeys = false
        var onCancel: (() -> Void)?
        var onStep: ((Double) -> Void)?
        private var monitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func setActive(_ active: Bool) {
            if !active {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            } else if monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak self] event in
                    guard let self, let window = self.window, event.window === window else { return event }
                    if event.type == .keyDown {
                        guard self.handlesKeys,
                              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return event }
                        switch event.keyCode {
                        case 53: self.onCancel?(); return nil // Escape
                        case 126: self.onStep?(0.1); return nil // Up
                        case 125: self.onStep?(-0.1); return nil // Down
                        default: return event
                        }
                    }
                    let point = self.convert(event.locationInWindow, from: nil)
                    if !self.visibleRect.contains(point) {
                        self.onOutsideClick?()
                    }
                    return event
                }
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
