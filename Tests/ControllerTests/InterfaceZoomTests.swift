import XCTest
@testable import MIDIClockController

final class InterfaceZoomTests: XCTestCase {
    func testRepeatedStepsStopAtSupportedLimits() {
        var value = 100
        for _ in 0..<20 { value = InterfaceZoom.adjusted(value, by: 10) }
        XCTAssertEqual(value, 150)
        for _ in 0..<20 { value = InterfaceZoom.adjusted(value, by: -10) }
        XCTAssertEqual(value, 80)
    }

    func testInvalidStoredPreferenceRecoversWithinRange() {
        XCTAssertEqual(InterfaceZoom.clamped(-100), 80)
        XCTAssertEqual(InterfaceZoom.clamped(900), 150)
        XCTAssertEqual(InterfaceZoom.adjusted(900, by: -10), 140)
        XCTAssertEqual(InterfaceZoom.adjusted(-100, by: 10), 90)
    }
}
