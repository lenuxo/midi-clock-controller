import AppKit
import CoreText
import SwiftUI

enum SegmentFont {
    static let name = "DSEG7Classic-Regular"

    // Register for this process only; never install or change system fonts.
    static let available: Bool = {
        guard let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") else {
            return false
        }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return NSFont(name: name, size: 12) != nil
    }()

    static func font(size: CGFloat) -> Font {
        available ? .custom(name, fixedSize: size) : .system(size: size, weight: .medium, design: .monospaced)
    }
}
