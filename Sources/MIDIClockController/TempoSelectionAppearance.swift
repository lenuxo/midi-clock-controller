import AppKit
import SwiftUI

/// Style only the field editor belonging to this BPM field; restore the shared editor afterward.
struct TempoSelectionAppearance: NSViewRepresentable {
    let background: Color
    let foreground: Color
    let focused: Bool

    func makeNSView(context: Context) -> SelectionView { SelectionView() }
    func updateNSView(_ view: SelectionView, context: Context) {
        view.selectionBackground = NSColor(background)
        view.selectionForeground = NSColor(foreground)
        if focused { DispatchQueue.main.async { [weak view] in view?.apply() } }
    }
    static func dismantleNSView(_ view: SelectionView, coordinator: ()) { view.cleanup() }

    final class SelectionView: NSView {
        var selectionBackground = NSColor.systemYellow
        var selectionForeground = NSColor.black
        private weak var editor: NSTextView?
        private var savedAttributes: [NSAttributedString.Key: Any]?
        private var savedCaret: NSColor?
        private var observers: [NSObjectProtocol] = []

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            cleanup()
            guard window != nil else { return }
            observers.append(NotificationCenter.default.addObserver(
                forName: NSControl.textDidBeginEditingNotification, object: nil, queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.async { [weak self] in self?.apply() }
            })
            observers.append(NotificationCenter.default.addObserver(
                forName: NSControl.textDidEndEditingNotification, object: nil, queue: .main
            ) { [weak self] notification in
                guard let self, let field = notification.object as? NSTextField,
                      field.window === self.window,
                      self.convert(field.bounds, from: field).intersects(self.bounds) else { return }
                self.restore()
            })
        }

        func apply() {
            guard let candidate = window?.firstResponder as? NSTextView,
                  candidate.window === window,
                  convert(candidate.bounds, from: candidate).intersects(bounds) else { return }
            if editor !== candidate {
                restore()
                editor = candidate
                savedAttributes = candidate.selectedTextAttributes
                savedCaret = candidate.insertionPointColor
            }
            candidate.selectedTextAttributes = [
                .backgroundColor: selectionBackground,
                .foregroundColor: selectionForeground
            ]
            candidate.insertionPointColor = selectionForeground
            candidate.needsDisplay = true
        }

        private func restore() {
            if let savedAttributes { editor?.selectedTextAttributes = savedAttributes }
            if let savedCaret { editor?.insertionPointColor = savedCaret }
            editor = nil
            savedAttributes = nil
            savedCaret = nil
        }
        func cleanup() {
            restore()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
        }
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}
