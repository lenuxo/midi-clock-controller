import AppKit
import SwiftUI

/// Match the native titlebar to the canvas without replacing traffic lights or toolbar controls.
struct WindowAppearance: NSViewRepresentable {
    let background: Color
    let preference: String

    func makeNSView(context: Context) -> AppearanceView { AppearanceView() }

    func updateNSView(_ view: AppearanceView, context: Context) {
        view.canvasColor = NSColor(background)
        view.preference = preference
        // Appearance changes feed back into SwiftUI’s colorScheme environment.
        // Apply after this update to avoid re-entering the current view transaction.
        DispatchQueue.main.async { [weak view] in view?.apply() }
    }
    static func dismantleNSView(_ view: AppearanceView, coordinator: ()) { view.cleanup() }

    final class AppearanceView: NSView {
        var canvasColor: NSColor = .windowBackgroundColor
        var preference = "system"
        private var resizeObserver: NSObjectProtocol?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            cleanup()
            if let window {
                resizeObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didResizeNotification, object: window, queue: .main
                ) { [weak self] _ in
                    DispatchQueue.main.async { [weak self] in self?.keepOnScreen() }
                }
            }
            apply()
        }

        func apply() {
            guard let window else { return }
            // Clear the native override for System. Do not use preferredColorScheme:
            // its presentation preference can retain the previous explicit appearance.
            let name: NSAppearance.Name? = preference == "dark" ? .darkAqua : preference == "light" ? .aqua : nil
            if window.appearance?.name != name {
                window.appearance = name.flatMap { NSAppearance(named: $0) }
            }
            // Keep the scrolling content below the native toolbar, including rubber-band scrolling.
            window.styleMask.remove(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.backgroundColor = canvasColor
            DispatchQueue.main.async { [weak self] in self?.keepOnScreen() }
        }

        private func keepOnScreen() {
            guard let window, let visible = window.screen?.visibleFrame else { return }
            let frame = window.frame
            let origin = NSPoint(
                x: min(max(frame.minX, visible.minX), max(visible.minX, visible.maxX - frame.width)),
                y: min(max(frame.minY, visible.minY), max(visible.minY, visible.maxY - frame.height))
            )
            if origin != frame.origin { window.setFrameOrigin(origin) }
        }

        func cleanup() {
            if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
            resizeObserver = nil
        }
        deinit {
            if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        }
    }
}
