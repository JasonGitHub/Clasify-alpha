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
            Path(roundedRect: CGRect(x: 0, y: 0, width: 101, height: 49), cornerRadius: 1).fill(Color(hex: 0x636364))
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
        0x666866, 0x788170, 0x899a7b, 0x9ab485, 0xaccd90, 0xb8d89e, 0xc5e1ab, 0xd1eab9, 0xddf4c6, 0xdef5c8, 0xdaf3c3,
        0xd6f0be, 0xd2edb9, 0xcdebb2, 0xc6e7a7, 0xbee49d, 0xb7e193, 0xb1de8a, 0xb0dd89, 0xb0dd89, 0xafdd88, 0xaedc88,
        0xa3d17d, 0x97c571, 0x8bb965, 0x7fad59, 0x76a550, 0x70a04b, 0x699b45, 0x639540, 0x60923d, 0x61933e, 0x62943f,
        0x639540, 0x649641, 0x679944, 0x6a9d46, 0x6c9f49, 0x6fa34c, 0x6da04a, 0x6a9d47, 0x689a45, 0x659742, 0x648e46,
        0x63824e, 0x627555, 0x61695d,
    ]
    static let emptyAll: [UInt32] = [
        0x626263, 0x5f6061, 0x5b5d5f, 0x585a5d, 0x55585b, 0x56585c, 0x56595d, 0x57595d, 0x58595e, 0x5a5b60, 0x5c5d62,
        0x5d5f65, 0x5f6167, 0x616369, 0x626469, 0x63656a, 0x64666b, 0x66686d, 0x696b70, 0x6c6e73, 0x6e7175, 0x717478,
        0x76797d, 0x7b7d82, 0x7f8286, 0x84868b, 0x86888d, 0x87898f, 0x888a90, 0x8a8b91, 0x8b8d93, 0x8c8e94, 0x8d8f95,
        0x8e9096, 0x909298, 0x94969b, 0x97999e, 0x9b9da1, 0x9ea0a4, 0x9fa1a4, 0x9fa2a5, 0xa0a3a5, 0xa1a4a6, 0x959799,
        0x868889, 0x777879, 0x686869,
    ]
    static let redAll: [UInt32] = [
        0x706866, 0x866f68, 0x9c766b, 0xb27d6d, 0xc48572, 0xcc9180, 0xd39d8e, 0xdba89c, 0xe2b4a9, 0xe0afa3, 0xdeaa9e,
        0xdda598, 0xdba093, 0xd99888, 0xd88e7d, 0xd78571, 0xd57c66, 0xd47760, 0xd47860, 0xd3785f, 0xd3785f, 0xd0765c,
        0xc66b51, 0xbb6046, 0xb1563c, 0xa64b31, 0xa2472d, 0x9e4228, 0x993e24, 0x94391f, 0x95391f, 0x963c21, 0x983e22,
        0x9a4024, 0x9c4226, 0x9e4427, 0xa04729, 0xa2492a, 0xa34b2b, 0xa04829, 0x9e4527, 0x9b4224, 0x983f22, 0x8c4731,
        0x7f4f40, 0x72574f, 0x66605f,
    ]
}
