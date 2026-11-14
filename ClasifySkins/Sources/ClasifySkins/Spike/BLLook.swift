import SwiftUI

/// SPIKE (CLA-101, K.3D spike 2): which Classic look the 2D device draws. BH is the look of
/// 1.0. BL (card BL, Round 17, changes 250-255) shows only with the hidden switch `spike.k3d`.
public enum PocketLook: Sendable {
    case bh, bl
}

private struct PocketLookKey: EnvironmentKey {
    static let defaultValue = PocketLook.bh
}

extension EnvironmentValues {
    /// The Classic look. The app sets `.bl` only when the switch `spike.k3d` is on.
    public var pocketLook: PocketLook {
        get { self[PocketLookKey.self] }
        set { self[PocketLookKey.self] = newValue }
    }
}

private struct PocketDropShadowKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// The device draws its drop shadow. SPIKE (CLA-101): off only while the 3D flip draws the
    /// same shadow from the 3D body (`K3DShadow`).
    public var pocketDropShadow: Bool {
        get { self[PocketDropShadowKey.self] }
        set { self[PocketDropShadowKey.self] = newValue }
    }
}

/// Card BL's values, BL v3 (Designer 1, Jason OK 17:32 JST 11-14; changes 250-255 and 268-272),
/// from `design-review/round17/bl/v3/k8.json`. All BL numbers live in this file. v3 matches the
/// K.3D.8 body: from v2, the Black tone, wheel, center button and labels changed, and both
/// wheels got a soft shade at the hole and the rim. The drop shadow is the same as BH. The
/// bezel is #2a2c2e for both colors: BH's Silver bezel, but not BH's near black Black bezel.
enum BL {
    /// The body: three layers, from the bottom. The main top-to-bottom tone, a left-to-right
    /// shade, and a thin dark line at the top.
    static func body(black: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 34)
        return shape
            .fill(LinearGradient(stops: black ? blackTone : silverTone, startPoint: .top, endPoint: .bottom))
            .overlay { shape.fill(LinearGradient(stops: sideShade, startPoint: .leading, endPoint: .trailing)) }
            .overlay { shape.fill(LinearGradient(stops: topLine, startPoint: .top, endPoint: .bottom)) }
    }

    /// `edge`: the 1 point line around the body.
    static func edge(black: Bool) -> Double { black ? 0.2 : 0.12 }
    /// `grain`: the overlay grain's opacity.
    static func grain(black: Bool) -> Double { black ? 0.12 : 0.35 }

    static var topLine: [Gradient.Stop] { [
        .init(color: .black.opacity(0.05), location: 0), .init(color: .black.opacity(0), location: 0.003),
    ] }
    static var sideShade: [Gradient.Stop] { [
        .init(color: .black.opacity(0.11), location: 0), .init(color: .black.opacity(0), location: 0.006),
        .init(color: .black.opacity(0), location: 0.05), .init(color: .black.opacity(0.025), location: 0.5),
        .init(color: .black.opacity(0.045), location: 0.82), .init(color: .black.opacity(0.07), location: 0.93),
        .init(color: .black.opacity(0.1), location: 0.97), .init(color: .black.opacity(0.12), location: 0.986),
        .init(color: .black.opacity(0.22), location: 0.995), .init(color: .black.opacity(0.32), location: 1),
    ] }
    static var silverTone: [Gradient.Stop] {
        stops([(0xffffff, 0), (0xfdfdfd, 0.04), (0xf9f9f9, 0.10), (0xf4f4f4, 0.16), (0xe8e8e8, 0.33), (0xe0e0e0, 0.49),
               (0xd8d8d8, 0.60), (0xd4d4d4, 0.65), (0xcccccc, 0.82), (0xc4c4c4, 0.91), (0xc2c2c2, 0.95), (0xbbbbbb, 0.97),
               (0xb2b2b2, 0.983), (0xa3a3a3, 0.992), (0x888888, 0.997), (0x6a6a6a, 1)])
    }
    static var blackTone: [Gradient.Stop] {
        stops([(0x828389, 0), (0x7a7c82, 0.04), (0x787a80, 0.06), (0x75787d, 0.10), (0x707277, 0.16), (0x65676b, 0.25),
               (0x5f6165, 0.33), (0x5c5d61, 0.40), (0x55565a, 0.49), (0x505155, 0.55), (0x4b4d50, 0.60), (0x494a4d, 0.65),
               (0x47484b, 0.70), (0x424346, 0.75), (0x3f4143, 0.82), (0x3d3e40, 0.88), (0x3b3c3f, 0.91), (0x37383b, 0.95),
               (0x2b2c2e, 0.975), (0x29292b, 0.984), (0x262628, 0.99), (0x1f1f21, 0.997), (0x18181a, 1)])
    }

    /// `wheel`: Silver is CSS `linear-gradient(160deg, #fff 12%, #f5f8f9 50%, #eceeef)` on the
    /// 225 point square. A 160° line on a square runs from (0.281, -0.102) to (0.719, 1.102).
    /// Black is flat #202123.
    static func wheel(black: Bool) -> AnyShapeStyle {
        if black { return AnyShapeStyle(Color(hex: 0x202123)) }
        return AnyShapeStyle(LinearGradient(
            stops: stops([(0xffffff, 0.12), (0xf5f8f9, 0.5), (0xeceeef, 1)]),
            startPoint: UnitPoint(x: 0.2808, y: -0.1024), endPoint: UnitPoint(x: 0.7192, y: 1.1024)))
    }

    /// `wheel`'s top layer, CSS `radial-gradient(circle closest-side, c 37.8%, clear 40.9%,
    /// clear 96%, c2 100%)`: a soft shade at the hole and at the rim. Silver is black 4.5% and
    /// 5.5%; Black is white 5% at both. `radius` is the wheel's.
    static func wheelShade(black: Bool, radius: CGFloat) -> RadialGradient {
        let tint: Color = black ? .white : .black
        let hole = black ? 0.05 : 0.045, rim = black ? 0.05 : 0.055
        return RadialGradient(stops: [
            .init(color: tint.opacity(hole), location: 0.378), .init(color: tint.opacity(0), location: 0.409),
            .init(color: tint.opacity(0), location: 0.96), .init(color: tint.opacity(rim), location: 1),
        ], center: .center, startRadius: 0, endRadius: radius)
    }

    /// `lab`: the wheel's labels at rest. Silver #8c939b (as BH), Black #ededee.
    static func label(black: Bool) -> UInt32 { black ? 0xededee : 0x8c939b }

    /// `wsh`: Silver has a 1 point ring inside the edge, black 10%, and a 0.5 point ring outside
    /// it, black 15%. Black has none.
    static func wheelInnerRing(black: Bool) -> Double { black ? 0 : 0.1 }
    static func wheelRing(black: Bool) -> Double { black ? 0 : 0.15 }

    /// `bezel`: the screen's bezel, both colors.
    static let bezel: UInt32 = 0x2a2c2e

    /// `ctr`: Silver #c9c9ca, #cdcdce at 50%, #d0d0d1. Black #2e2e30, #353638 at 30%, #393a3c at
    /// 50%, #3c3d40. BL gives no pressed value, so a press darkens the button by 6%, about as
    /// much as BH's `ctrDown`.
    static func center(black: Bool, down: Bool) -> [Gradient.Stop] {
        let list: [(UInt32, Double)] = black
            ? [(0x2e2e30, 0), (0x353638, 0.3), (0x393a3c, 0.5), (0x3c3d40, 1)]
            : [(0xc9c9ca, 0), (0xcdcdce, 0.5), (0xd0d0d1, 1)]
        return list.map { entry in
            let (hex, at) = entry
            let r = Double(hex >> 16 & 0xff) / 255, g = Double(hex >> 8 & 0xff) / 255, b = Double(hex & 0xff) / 255
            let k = down ? 0.94 : 1
            return .init(color: Color(.sRGB, red: r * k, green: g * k, blue: b * k), location: at)
        }
    }

    /// `ctr`'s top layer on Black, CSS `radial-gradient(circle closest-side, clear 70%, black 5%)`:
    /// a soft shade at the button's edge. Silver has none. `radius` is the button's.
    static func centerShade(black: Bool, radius: CGFloat) -> RadialGradient {
        RadialGradient(stops: [
            .init(color: .black.opacity(0), location: 0.7), .init(color: .black.opacity(black ? 0.05 : 0), location: 1),
        ], center: .center, startRadius: 0, endRadius: radius)
    }

    /// `csh`: Silver has a 0.5 point ring at 10% outside the button, and a 0.5 point inner line at
    /// 5% along its top. Black has none.
    static func centerRing(black: Bool) -> Double { black ? 0 : 0.1 }
    static func centerTopLine(black: Bool) -> Double { black ? 0 : 0.05 }

    private static func stops(_ list: [(UInt32, Double)]) -> [Gradient.Stop] {
        list.map { .init(color: Color(hex: $0.0), location: $0.1) }
    }
}

/// CSS `inset 0 0.5px 0`: the part of a circle that the same circle 0.5 point lower does not
/// cover, a thin crescent along the top. Fill it with the even-odd rule and clip it to the circle.
struct TopCrescent: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(ellipseIn: rect)
        path.addEllipse(in: rect.offsetBy(dx: 0, dy: 0.5))
        return path
    }
}
