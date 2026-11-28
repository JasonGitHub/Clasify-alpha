import ClasifyCore
import ClasifySkins
import SwiftUI

/// Card CX (first pass): the place of the device on the phone screen. All of the phone's
/// layout values are here, so a phone-only body later changes one file.
@MainActor enum PhoneLayout {
    /// Free space on each side of the body, in points.
    static let side: CGFloat = 16
    /// The share of the free height above the body; the rest is below it.
    static let above: CGFloat = 0.42
    /// The flat background: the body's color.
    static let silver = Color(red: 0xE3 / 255, green: 0xE5 / 255, blue: 0xE8 / 255)
    static let black = Color(red: 0x0B / 255, green: 0x0B / 255, blue: 0x0C / 255)
    /// The floor shadow: an ellipse 84 % of the body width, from 6 pt above the body's bottom
    /// to 10 pt below it, blurred 9 pt.
    static let shadowWidth: CGFloat = 0.84, shadowTop: CGFloat = 6, shadowBottom: CGFloat = 10, shadowBlur: CGFloat = 9
    static let shadowSilver = 0.24, shadowBlack = 0.43

    /// One scale for the whole body, no stretch: the safe-area width less `side` on each side.
    static func scale(width: CGFloat) -> CGFloat { (width - 2 * side) / PocketSkin.size.width }

    /// The body's top in the safe area: `above` of the free height.
    static func top(height: CGFloat, bodyHeight: CGFloat) -> CGFloat { max(0, height - bodyHeight) * above }
}

/// The Pocket skin, scaled to the phone, on a flat background with a floor shadow.
struct PhoneDevice: View {
    let store: Store
    let artwork: Artwork

    var body: some View {
        let black = store.state.shownColor == .black
        GeometryReader { geo in
            let scale = PhoneLayout.scale(width: geo.size.width)
            let size = CGSize(width: PocketSkin.size.width * scale, height: PocketSkin.size.height * scale)
            let top = PhoneLayout.top(height: geo.size.height, bodyHeight: size.height)
            ZStack(alignment: .top) {
                Ellipse()
                    .fill(Color.black.opacity(black ? PhoneLayout.shadowBlack : PhoneLayout.shadowSilver))
                    .frame(width: size.width * PhoneLayout.shadowWidth, height: PhoneLayout.shadowTop + PhoneLayout.shadowBottom)
                    .blur(radius: PhoneLayout.shadowBlur)
                    .offset(y: top + size.height - PhoneLayout.shadowTop)
                PocketSkin(state: store.state) { store.send($0) }
                    .environment(\.artwork, artwork)
                    .environment(\.pocketDropShadow, false)  // the floor shadow takes its place
                    .frame(width: PocketSkin.size.width, height: PocketSkin.size.height)
                    .scaleEffect(scale)
                    .frame(width: size.width, height: size.height)
                    .offset(y: top)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .background((black ? PhoneLayout.black : PhoneLayout.silver).ignoresSafeArea())
    }
}
