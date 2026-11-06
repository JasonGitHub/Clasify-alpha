import SwiftUI

/// The Now Playing shuffle and repeat icons (round 7, card U change 53). Each is 16 by 14 points,
/// the same as its SVG view box, so the paths need no scaling. They draw in the foreground style.
/// All three share one frame and top edge; the Repeat One badge is an offset and does not change it.
/// A "cut" is a stroke in the screen's background color under the top shape, so the shapes
/// look apart where they cross.
struct ModeIcon: View {
    enum Kind { case shuffle, repeatAll, repeatOne }
    let kind: Kind

    static let size = CGSize(width: 16, height: 14)
    /// The screen's background behind the icons.
    static let cut = Color(hex: 0xedf2f6)

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch kind {
            case .shuffle: shuffle
            case .repeatAll: loop
            case .repeatOne:
                loop
                badge
            }
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
    }

    /// "M0.9 3.7H3.2C6.6 3.7 7.6 10.3 11 10.3H12" and its mirror, "M0.9 10.3H3.2C6.6 10.3 7.6 3.7 11 3.7H12".
    static func crossing(from y0: CGFloat, to y1: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.9, y: y0))
        p.addLine(to: CGPoint(x: 3.2, y: y0))
        p.addCurve(to: CGPoint(x: 11, y: y1), control1: CGPoint(x: 6.6, y: y0), control2: CGPoint(x: 7.6, y: y1))
        p.addLine(to: CGPoint(x: 12, y: y1))
        return p
    }

    /// An arrowhead pointing right, with its tip at (15, tipY): "M11.6 (tipY-2.5)L15 tipY 11.6 (tipY+2.5)Z".
    static func head(tipY: CGFloat) -> Path {
        var p = Path()
        p.addLines([CGPoint(x: 11.6, y: tipY - 2.5), CGPoint(x: 15, y: tipY), CGPoint(x: 11.6, y: tipY + 2.5)])
        p.closeSubpath()
        return p
    }

    private func filled(_ path: Path) -> some View {
        ZStack {
            path.fill(.foreground)
            path.stroke(.foreground, style: StrokeStyle(lineWidth: 0.3, lineJoin: .round))
        }
    }

    private var shuffle: some View {
        ZStack {
            Self.crossing(from: 3.7, to: 10.3).stroke(.foreground, lineWidth: 2.4)
            filled(Self.head(tipY: 10.3))
            Self.crossing(from: 10.3, to: 3.7).stroke(Self.cut, lineWidth: 4.3)
            Self.crossing(from: 10.3, to: 3.7).stroke(.foreground, lineWidth: 2.4)
            filled(Self.head(tipY: 3.7))
        }
    }

    private var loop: some View {
        ZStack {
            Path(roundedRect: CGRect(x: 1.33, y: 3.7, width: 13.34, height: 7.8), cornerRadius: 3.9)
                .stroke(.foreground, lineWidth: 2.6)
            Self.head(tipY: 3.7).fill(Self.cut)
            Self.head(tipY: 3.7).stroke(Self.cut, style: StrokeStyle(lineWidth: 1.9, lineJoin: .round))
            Path { p in
                p.move(to: CGPoint(x: 9, y: 3.7))
                p.addLine(to: CGPoint(x: 12, y: 3.7))
            }
            .stroke(.foreground, lineWidth: 2.6)
            filled(Self.head(tipY: 3.7))
        }
    }

    /// Repeat One's badge: a circle at (3.73, 11.23), radius 3.73, with a thin ring in the
    /// background color and a white bold "1". The digit's middle sits at the circle's middle,
    /// which puts its baseline near y 13.37, as in the SVG. The badge goes about 1.4 points
    /// below the frame on purpose; nothing clips it.
    private var badge: some View {
        let r: CGFloat = 3.73
        return ZStack {
            Circle().fill(.foreground)
            Circle().stroke(Self.cut, lineWidth: 0.9)
            Text("1").font(.helvetica(6, bold: true)).foregroundStyle(.white).fixedSize()
        }
        .frame(width: 2 * r, height: 2 * r)
        .offset(x: 3.73 - r, y: 11.23 - r)
    }
}
