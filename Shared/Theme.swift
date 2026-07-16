import SwiftUI

// MARK: - Design tokens from the mockup (light theme)

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

enum Theme {
    static let bg = Color(hex: 0xF2F2F7)
    static let card = Color(hex: 0xFFFFFF)
    static let inset = Color(hex: 0xEFEFF3)      // --card2
    static let inset2 = Color(hex: 0xE3E3E9)     // --card3
    static let separator = Color(hex: 0xE4E4EA)

    static let label = Color(hex: 0x111114)
    static let secondary = Color(hex: 0x6E6E76)
    static let tertiary = Color(hex: 0xA6A6AE)

    static let green = Color(hex: 0x34C759)
    static let amber = Color(hex: 0xFF9500)
    static let red = Color(hex: 0xFF3B30)
    static let blue = Color(hex: 0x007AFF)

    static let greenD = Color(hex: 0x1F8A3B)
    static let amberD = Color(hex: 0xC25E00)
    static let redD = Color(hex: 0xD70015)

    // Tinted button backgrounds: 15% accent (mockup --greenT/--amberT, red 12%)
    static let greenT = green.opacity(0.15)
    static let amberT = amber.opacity(0.15)
    static let redT = red.opacity(0.12)

    static let cardRadius: CGFloat = 20
    static let ringTrack = Color(hex: 0xE3E3E8)
}
