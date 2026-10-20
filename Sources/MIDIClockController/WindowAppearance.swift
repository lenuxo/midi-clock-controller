import AppKit
import SwiftUI

/// Match the native titlebar to the canvas without replacing traffic lights or toolbar controls.
struct WindowAppearance: NSViewRepresentable {
    let background: Color

    func makeNSView(context: Context) -> AppearanceView { AppearanceView() }

    func updateNSView(_ view: AppearanceView, context: Context) {
        view.canvasColor = NSColor(background)
        view.apply()
    }

    final class AppearanceView: NSView {
        var canvasColor: NSColor = .windowBackgroundColor

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        func apply() {
            guard let window else { return }
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.backgroundColor = canvasColor
        }
    }
}
