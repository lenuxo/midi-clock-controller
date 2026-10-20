import AppKit
import XCTest
@testable import MIDIClockController

final class WindowAppearanceTests: XCTestCase {
    @MainActor func testSystemClearsBothManualOverridesOnTheSameWindow() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 560),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = WindowAppearance.AppearanceView()
        window.contentView = view
        defer { view.cleanup(); window.close() }

        for preference in ["dark", "light", "dark", "light"] {
            view.preference = preference
            view.apply()
            XCTAssertEqual(window.appearance?.name, preference == "dark" ? .darkAqua : .aqua)
            view.preference = "system"
            view.apply()
            XCTAssertNil(window.appearance)
            XCTAssertEqual(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]),
                           NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]))
        }
    }
}
