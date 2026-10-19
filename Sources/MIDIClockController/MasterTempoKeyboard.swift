import AppKit
import SwiftUI

/// Window-local shortcuts; focused text editors and menu tracking retain their own arrow handling.
struct MasterTempoKeyboard: NSViewRepresentable {
    let step: (Double) -> Void
    func makeNSView(context: Context) -> KeyboardView { KeyboardView() }
    func updateNSView(_ view: KeyboardView, context: Context) { view.step = step }
    static func dismantleNSView(_ view: KeyboardView, coordinator: ()) { view.cleanup() }

    final class KeyboardView: NSView {
        var step: ((Double) -> Void)?
        private let hold = TempoHold()
        private var key: UInt16?
        private var monitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            cleanup()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .leftMouseDown, .flagsChanged]) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }
        private var allowed: Bool {
            guard let window, NSApp.isActive, window.isKeyWindow else { return false }
            return !(window.firstResponder is NSTextView) && !(window.firstResponder is NSTextField)
        }
        private func handle(_ event: NSEvent) -> NSEvent? {
            if event.type == .leftMouseDown || event.type == .flagsChanged {
                hold.stop(); key = nil
                return event
            }
            if event.type == .keyUp, event.keyCode == key {
                hold.stop(); key = nil
                return nil
            }
            guard event.type == .keyDown, event.window === window,
                  event.keyCode == 125 || event.keyCode == 126 else { return event }
            guard allowed, event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else {
                hold.stop(); key = nil
                return event
            }
            // Own the repeat cadence. Ignore OS repeats, including those after a cancellation.
            if event.isARepeat { return nil }
            key = event.keyCode
            hold.start(direction: event.keyCode == 126 ? 1 : -1,
                       allowed: { [weak self] in self?.allowed == true },
                       action: { [weak self] in self?.step?($0) })
            return nil
        }
        func cleanup() {
            hold.stop(); key = nil
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
