import SwiftUI

enum SpotterV2Typography {
    static func display(size: CGFloat = 56) -> Font {
        .system(size: size, weight: .black, design: .rounded)
    }

    static func heading(size: CGFloat, weight: Font.Weight = .black) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func body(size: CGFloat = 16, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func mono(size: CGFloat, weight: Font.Weight = .black) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func caption(weight: Font.Weight = .black) -> Font {
        .system(size: 10, weight: weight, design: .rounded)
    }
}
