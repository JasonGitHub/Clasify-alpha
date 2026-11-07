import SwiftUI

/// The title bar battery (round 7, card Y), traced from the iPod classic manual. It is drawn in
/// the SVG's 111 x 53 view box and scaled to 11 points tall, 23.04 wide. Back to front: the
/// shadow, the tip, the frame, the empty inside, the fill, and the bolt or plug.
struct BatteryView: View {
    let battery: Labels.BatteryText

    static let viewBox = CGSize(width: 111, height: 53)
    static let height: CGFloat = 11
    static var width: CGFloat { (height * viewBox.width / viewBox.height * 100).rounded() / 100 }

    var body: some View {
        let scale = Self.height / Self.viewBox.height
        ZStack(alignment: .topLeading) {
            // The shadow under the frame: #6e6e6f fading out downward, the same all along its width.
            rect(0, 49, 101, 4).fill(LinearGradient(
                colors: [Color(hex: 0x6e6e6f), Color(hex: 0x6e6e6f, opacity: 0)],
                startPoint: UnitPoint(x: 0, y: 49 / Self.viewBox.height), endPoint: UnitPoint(x: 0, y: 1)))
            tip
            Path(roundedRect: CGRect(x: 0, y: 0, width: 101, height: 49), cornerRadius: 1).fill(Color(hex: 0x8a9886))
            rect(2, 2, 97, 46).fill(Self.gradient(Self.emptyColors))
            if battery.level > 0 {
                rect(2, 2, 97 * battery.level, 46).fill(Self.gradient(battery.red ? Self.redColors : Self.fillColors))
            }
            switch battery.mark {
            case .bolt:
                ZStack {  // soft corners: a stroke 1.6 wide with round joins
                    Self.bolt.fill(Color(hex: 0x4a5640))
                    Self.bolt.stroke(Color(hex: 0x4a5640), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                }
            case .plug: plug
            case nil: EmptyView()
            }
        }
        .frame(width: Self.viewBox.width, height: Self.viewBox.height, alignment: .topLeading)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: Self.width, height: Self.height, alignment: .topLeading)
        .accessibilityElement()
        .accessibilityLabel(battery.label)
    }

    private func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
        Path(CGRect(x: x, y: y, width: w, height: h))
    }

    /// A vertical gradient over the inside, y 2 to 48 of the view box.
    private static func gradient(_ hex: [UInt32]) -> LinearGradient {
        let n = Double(hex.count - 1)
        return LinearGradient(
            stops: hex.enumerated().map { .init(color: Color(hex: $0.element), location: Double($0.offset) / n) },
            startPoint: UnitPoint(x: 0, y: 2 / viewBox.height), endPoint: UnitPoint(x: 0, y: 48 / viewBox.height))
    }

    /// The small tip on the right: an outlined, nearly square cap.
    private var tip: some View {
        ZStack(alignment: .topLeading) {
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 1.5, topTrailingRadius: 1.5)
                .fill(LinearGradient.vertical(Color(hex: 0x666667), Color(hex: 0x8c8c8d)))
                .frame(width: 10.5, height: 14)
                .offset(x: 99, y: 18)
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 0.5, topTrailingRadius: 0.5)
                .fill(LinearGradient(
                    stops: [
                        .init(color: Color(hex: 0xbdbdbd), location: 0), .init(color: Color(hex: 0xd8d8d8), location: 0.4),
                        .init(color: Color(hex: 0xb4b4b5), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom))
                .frame(width: 8.5, height: 10)
                .offset(x: 99, y: 20)
        }
    }

    /// "M49.59 9.00L50.93 9.00L49.62 20.65L59.33 20.65L48.64 39.80L47.35 39.80L48.52 28.26L38.67 28.26Z"
    static var bolt: Path {
        var p = Path()
        p.addLines([
            CGPoint(x: 49.59, y: 9), CGPoint(x: 50.93, y: 9), CGPoint(x: 49.62, y: 20.65), CGPoint(x: 59.33, y: 20.65),
            CGPoint(x: 48.64, y: 39.8), CGPoint(x: 47.35, y: 39.8), CGPoint(x: 48.52, y: 28.26), CGPoint(x: 38.67, y: 28.26),
        ])
        p.closeSubpath()
        return p
    }

    /// The plug: a cord, a body with rounded corners, and two prongs.
    private var plug: some View {
        ZStack(alignment: .topLeading) {
            Path(roundedRect: CGRect(x: 25, y: 20.5, width: 15, height: 8.5), cornerRadius: 3).fill(Color(hex: 0x435731))
            UnevenRoundedRectangle(topLeadingRadius: 4.5, bottomLeadingRadius: 7, bottomTrailingRadius: 7, topTrailingRadius: 4.5)
                .fill(Color(hex: 0x3d4f2d))
                .frame(width: 22, height: 25.5)
                .offset(x: 38, y: 12)
            Path(roundedRect: CGRect(x: 58, y: 16.5, width: 10.5, height: 4), cornerRadius: 1).fill(Color(hex: 0x3d4f2d))
            Path(roundedRect: CGRect(x: 58, y: 28.3, width: 10.5, height: 3.8), cornerRadius: 1).fill(Color(hex: 0x3d4f2d))
        }
    }

    // The gradients from battery-icon-gen.py, every second stop and the last, top to bottom.
    static let fillColors = everySecond(fillAll)
    static let redColors = everySecond(redAll)
    static let emptyColors = everySecond(emptyAll)

    /// Every second color and the last one, as the generator's `stops()` picks them.
    static func everySecond(_ all: [UInt32]) -> [UInt32] {
        stride(from: 0, to: all.count, by: 2).map { all[$0] } + (all.count % 2 == 0 ? [all[all.count - 1]] : [])
    }

    static let fillAll: [UInt32] = [
        0xb1e392, 0xb2e592, 0xb3e692, 0xb4e992, 0xb3e991, 0xb2ea91, 0xb2ea90, 0xb0ea8f, 0xaee98c, 0xace88a, 0xaae788,
        0xa7e585, 0xa3e381, 0xa0e17d, 0x9ddf7a, 0x9add77, 0x96db74, 0x93d971, 0x91d76e, 0x8ed56b, 0x8cd369, 0x8ad267,
        0x89d166, 0x88d064, 0x85ce62, 0x83cb60, 0x81c95e, 0x7fc75d, 0x7dc45c, 0x7cc25a, 0x7ac059, 0x79be58, 0x77bc57,
        0x76bb56, 0x76ba56, 0x76b857, 0x75b757, 0x79ba5b, 0x7ebd60, 0x83c066, 0x85c168, 0x85c068, 0x85bf69, 0x84bd69,
        0x81b966, 0x7eb664, 0x7bb362,
    ]
    static let emptyAll: [UInt32] = [
        0x76777a, 0x747679, 0x727578, 0x717377, 0x6f7276, 0x707276, 0x707377, 0x707377, 0x717377, 0x727478, 0x737579,
        0x73767b, 0x74777c, 0x75787d, 0x76787d, 0x76797d, 0x77797e, 0x787a7f, 0x797c80, 0x7b7d82, 0x7c7f83, 0x7d8084,
        0x808387, 0x828589, 0x84878b, 0x87898e, 0x888a8f, 0x888b90, 0x898b90, 0x8a8c91, 0x8a8d92, 0x8b8d92, 0x8b8e93,
        0x8c8e93, 0x8d8f94, 0x8f9196, 0x909397, 0x929599, 0x94969a, 0x94979a, 0x94979b, 0x95989b, 0x95989b, 0x8f9295,
        0x888a8d, 0x808285, 0x797a7d,
    ]
    static let redAll: [UInt32] = [
        0xa37264, 0xaf7564, 0xbb7864, 0xc77b64, 0xd17e66, 0xd4846e, 0xd78b75, 0xdb907c, 0xde9683, 0xde9480, 0xdd917d,
        0xdc8e7a, 0xdc8c77, 0xdb8871, 0xdb826b, 0xdb7e65, 0xda795f, 0xda765c, 0xda775c, 0xda775b, 0xda775b, 0xd8765a,
        0xd37054, 0xce6b4f, 0xc9664a, 0xc36044, 0xc15e42, 0xbf5c40, 0xbd5a3e, 0xba573b, 0xbb573b, 0xbb593c, 0xbc5a3d,
        0xbd5b3e, 0xbe5c3f, 0xbf5d3f, 0xc05f40, 0xc16041, 0xc26141, 0xc05f40, 0xbf5e3f, 0xbe5c3e, 0xbc5b3d, 0xb55f45,
        0xad644e, 0xa56857, 0x9e6e60,
    ]
}
