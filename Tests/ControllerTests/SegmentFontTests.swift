import AppKit
import XCTest
@testable import MIDIClockController

final class SegmentFontTests: XCTestCase {
    func testBundledFontRegistersAndCoversBPMCharacters() throws {
        XCTAssertTrue(SegmentFont.available)
        let font = try XCTUnwrap(NSFont(name: SegmentFont.name, size: 56))
        XCTAssertEqual(font.fontName, "DSEG7Classic-Regular")
        XCTAssertTrue(CharacterSet(charactersIn: "0123456789.-").isSubset(of: font.coveredCharacterSet))
    }

    func testValidBPMReadoutsFitBothEditors() throws {
        XCTAssertTrue(SegmentFont.available)
        for (size, width): (CGFloat, CGFloat) in [(56, 188), (38, 130)] {
            let font = try XCTUnwrap(NSFont(name: SegmentFont.name, size: size))
            for bpm in ["20.0", "90.0", "120.0", "299.9", "300.0"] {
                XCTAssertLessThanOrEqual((bpm as NSString).size(withAttributes: [.font: font]).width, width - 4)
            }
        }
    }
}
