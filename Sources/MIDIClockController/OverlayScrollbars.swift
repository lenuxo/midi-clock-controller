import AppKit
import SwiftUI

/// Place inside ScrollView content to keep native scrollbars from reserving width.
struct OverlayScrollbars: NSViewRepresentable {
    func makeNSView(context: Context) -> ScrollerView { ScrollerView() }
    func updateNSView(_ view: ScrollerView, context: Context) { view.scheduleApply() }
    static func dismantleNSView(_ view: ScrollerView, coordinator: ()) { view.cleanup() }

    final class ScrollerView: NSView {
        private var styleObserver: NSObjectProtocol?
        private var applyScheduled = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            scheduleApply()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            cleanup()
            if window != nil {
                // AppKit reapplies the system preference when the input device
                // or scrollbar preference changes. Keep this scroll view overlay.
                styleObserver = NotificationCenter.default.addObserver(
                    forName: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil, queue: .main
                ) { [weak self] _ in self?.scheduleApply() }
                scheduleApply()
            }
        }

        func scheduleApply() {
            guard !applyScheduled else { return }
            applyScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.applyScheduled = false
                guard self.window != nil, let scrollView = self.enclosingScrollView else { return }
                if scrollView.scrollerStyle != .overlay { scrollView.scrollerStyle = .overlay }
                // Overlay scrollers manage their own fade; autohidesScrollers
                // only controls legacy scrollers and is intentionally left alone.
            }
        }

        func cleanup() {
            if let styleObserver { NotificationCenter.default.removeObserver(styleObserver) }
            styleObserver = nil
        }

        deinit {
            if let styleObserver { NotificationCenter.default.removeObserver(styleObserver) }
        }
    }
}
