import SwiftUI

enum SpotterV2 {
    enum Tokens {
        static let background = Color(hex: 0x0D0D0D)
        static let foreground = Color(hex: 0xF2F0EB)
        static let secondary = Color(hex: 0x262626)
        static let muted = Color(hex: 0x262626)
        static let mutedForeground = Color(hex: 0xA3A3A3)
        static let destructive = Color(hex: 0xFF5C3A)
        static let card = Color(hex: 0x0D0D0D)
        static let border = Color(hex: 0xF2F0EB)
        static let chart1 = Color(hex: 0x00D1FF)
        static let chart3 = Color(hex: 0xFF5C3A)
        static let chart4 = Color(hex: 0x525252)
        static let chart5 = Color(hex: 0x262626)

        static func primary(_ theme: SpotterThemeOption) -> Color {
            theme.accentColor
        }

        static func chart2(_ theme: SpotterThemeOption) -> Color {
            theme.accentColor
        }

        static func ring(_ theme: SpotterThemeOption) -> Color {
            theme.accentColor
        }
    }

    enum Spacing {
        static let xxxs: CGFloat = 2
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    enum Radius {
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let pill: CGFloat = 999
    }

    enum BorderWidth {
        static let standard: CGFloat = 2
        static let bold: CGFloat = 4
    }

    enum Motion {
        static let snappy: Animation = .snappy(duration: 0.22)
        static let press: Animation = .easeInOut(duration: 0.12)
        static let pulse: Animation = .easeInOut(duration: 1.2).repeatForever()
    }
}

extension Color {
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
