import SwiftUI

struct ClockPalette {
    let dark: Bool
    var background: Color { Color(hex: dark ? 0x111416 : 0xEEF1EF) }
    var panel: Color { Color(hex: dark ? 0x1B2023 : 0xFFFFFF) }
    var display: Color { Color(hex: 0x090C0D) }
    var digits: Color { Color(hex: 0xFFC15A) }
    var accent: Color { dark ? digits : Color(hex: 0x8A4B00) }
    var border: Color { Color(hex: dark ? 0x394247 : 0xC9D1CC) }
    var text: Color { Color(hex: dark ? 0xEFF2ED : 0x1B2520) }
    var secondary: Color { Color(hex: dark ? 0xA8B2AC : 0x58665E) }
    var playing: Color { Color(hex: dark ? 0x82C995 : 0x2E7D3F) }
    var error: Color { Color(hex: dark ? 0xE88270 : 0xA43B2D) }
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}
