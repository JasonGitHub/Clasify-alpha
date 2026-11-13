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

/// Card BL's values, BL v2 (Designer 1, 22:48 JST 11-13, the current candidate), from
/// `design-review/round17/bl/k7.json`. All BL numbers live in this file. From v1
/// (`k7-spike1.json`), only the Silver tone's last stops and the Silver wheel ring changed. The
/// labels and the drop shadow are the same as BH. The bezel is #2a2c2e for both colors: BH's
/// Silver bezel, but not BH's near black Black bezel.
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
        stops([(0x575757, 0), (0x555555, 0.06), (0x535353, 0.16), (0x4f4f4f, 0.33), (0x4c4c4c, 0.49), (0x484848, 0.65),
               (0x454545, 0.82), (0x424242, 0.91), (0x414141, 0.95), (0x3d3d3d, 0.975), (0x3a3a3a, 0.984), (0x363636, 0.99),
               (0x2c2c2c, 0.997), (0x222222, 1)])
    }

    /// `wheel`: Silver is CSS `linear-gradient(160deg, #fff 12%, #f5f8f9 50%, #eceeef)` on the
    /// 225 point square. A 160° line on a square runs from (0.281, -0.102) to (0.719, 1.102).
    /// Black is flat #1e1e1e.
    static func wheel(black: Bool) -> AnyShapeStyle {
        if black { return AnyShapeStyle(Color(hex: 0x1e1e1e)) }
        return AnyShapeStyle(LinearGradient(
            stops: stops([(0xffffff, 0.12), (0xf5f8f9, 0.5), (0xeceeef, 1)]),
            startPoint: UnitPoint(x: 0.2808, y: -0.1024), endPoint: UnitPoint(x: 0.7192, y: 1.1024)))
    }

    /// `wsh`: Silver has a 1 point ring inside the edge, black 10%, and a 0.5 point ring outside
    /// it, black 15%. Black has none.
    static func wheelInnerRing(black: Bool) -> Double { black ? 0 : 0.1 }
    static func wheelRing(black: Bool) -> Double { black ? 0 : 0.15 }

    /// `bezel`: the screen's bezel, both colors.
    static let bezel: UInt32 = 0x2a2c2e

    /// `ctr`: Silver #c9c9ca, #cdcdce at 50%, #d0d0d1. Black flat #454545. BL gives no pressed
    /// value, so a press darkens the button by 6%, about as much as BH's `ctrDown`.
    static func center(black: Bool, down: Bool) -> [Gradient.Stop] {
        let list: [(UInt32, Double)] = black ? [(0x454545, 0), (0x454545, 1)] : [(0xc9c9ca, 0), (0xcdcdce, 0.5), (0xd0d0d1, 1)]
        return list.map { entry in
            let (hex, at) = entry
            let r = Double(hex >> 16 & 0xff) / 255, g = Double(hex >> 8 & 0xff) / 255, b = Double(hex & 0xff) / 255
            let k = down ? 0.94 : 1
            return .init(color: Color(.sRGB, red: r * k, green: g * k, blue: b * k), location: at)
        }
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
