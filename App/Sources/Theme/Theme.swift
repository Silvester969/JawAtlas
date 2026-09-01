import SwiftUI

extension Color {
    static func dsToken(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    static let dsBrandPrimary = dsToken(light: 0x0B5FA5, dark: 0x4DA3FF)
    static let dsBrandPressed = dsToken(light: 0x084A82, dark: 0x2E86E0)

    static let dsSafetyGreen = dsToken(light: 0x1E8E3E, dark: 0x34C759)
    static let dsSafetyGreenContainer = dsToken(light: 0xE6F4EA, dark: 0x0C3A1D)
    static let dsSafetyOrange = dsToken(light: 0xB06000, dark: 0xFF9F0A)
    static let dsSafetyOrangeContainer = dsToken(light: 0xFFF3E0, dark: 0x3D2A05)
    static let dsSafetyRed = dsToken(light: 0xC22B2B, dark: 0xFF453A)
    static let dsSafetyRedContainer = dsToken(light: 0xFDE7E7, dark: 0x3D0C0C)
    static let dsSafetyNeutral = dsToken(light: 0x5F6368, dark: 0x9AA0A6)
    static let dsSafetyNeutralContainer = dsToken(light: 0xEEEEEE, dark: 0x26292D)

    static let dsBackground = dsToken(light: 0xF6F7F8, dark: 0x000000)
    static let dsCard = dsToken(light: 0xFFFFFF, dark: 0x1C1E21)
    static let dsCardPressed = dsToken(light: 0xF0F1F3, dark: 0x26292D)
    static let dsSeparator = dsToken(light: 0xE3E5E8, dark: 0x33373B)
    static let dsTextPrimary = dsToken(light: 0x1B1D1F, dark: 0xF2F3F4)
    static let dsTextSecondary = dsToken(light: 0x5F6368, dark: 0xAEB2B6)

    static let dsCanalOverlay = dsToken(light: 0x8E44AD, dark: 0xB788DC)
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
