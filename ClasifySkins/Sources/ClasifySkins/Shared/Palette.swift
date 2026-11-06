import SwiftUI

extension Color {
    /// A color from a CSS hex value, such as `0x1b1f24`.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB, red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255,
            blue: Double(hex & 0xff) / 255, opacity: opacity)
    }
}

extension Font {
    /// The mockup's font, Helvetica Neue.
    static func helvetica(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom("Helvetica Neue", size: size).weight(bold ? .bold : .regular)
    }

    static func helvetica(_ size: CGFloat, weight: Font.Weight) -> Font {
        .custom("Helvetica Neue", size: size).weight(weight)
    }
}

extension LinearGradient {
    /// A top-to-bottom gradient.
    static func vertical(_ colors: Color...) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
}
