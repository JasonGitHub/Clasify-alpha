import SwiftUI

/// The mockup's SVG icons as shapes. Each path uses the SVG's own view box and scales to its frame.
enum Icon: Sendable {
    case chevron, prev, next, playPause, speaker, speakerLoud, note

    var viewBox: CGSize {
        switch self {
        case .chevron: CGSize(width: 7, height: 10)
        case .prev, .next: CGSize(width: 18, height: 12)
        case .playPause: CGSize(width: 20, height: 12)
        case .speaker: CGSize(width: 14, height: 14)
        case .speakerLoud: CGSize(width: 16, height: 14)
        case .note: CGSize(width: 24, height: 24)
        }
    }

    /// The filled part of the icon.
    var fill: Path {
        var p = Path()
        switch self {
        case .chevron, .note:
            break
        case .prev:  // the SVG's vertical line has no stroke, so only the two triangles show
            p.addLines([CGPoint(x: 10, y: 1), CGPoint(x: 3, y: 6), CGPoint(x: 10, y: 11)])
            p.closeSubpath()
            p.addLines([CGPoint(x: 17, y: 1), CGPoint(x: 10, y: 6), CGPoint(x: 17, y: 11)])
            p.closeSubpath()
        case .next:
            p.addLines([CGPoint(x: 8, y: 1), CGPoint(x: 15, y: 6), CGPoint(x: 8, y: 11)])
            p.closeSubpath()
            p.addLines([CGPoint(x: 1, y: 1), CGPoint(x: 8, y: 6), CGPoint(x: 1, y: 11)])
            p.closeSubpath()
        case .playPause:
            p.addLines([CGPoint(x: 1, y: 1), CGPoint(x: 8, y: 6), CGPoint(x: 1, y: 11)])
            p.closeSubpath()
            p.addRect(CGRect(x: 11, y: 1, width: 3, height: 10))
            p.addRect(CGRect(x: 16, y: 1, width: 3, height: 10))
        case .speaker, .speakerLoud:
            p.addLines([
                CGPoint(x: 2, y: 5), CGPoint(x: 5, y: 5), CGPoint(x: 8, y: 2), CGPoint(x: 8, y: 12),
                CGPoint(x: 5, y: 9), CGPoint(x: 2, y: 9),
            ])
            p.closeSubpath()
        }
        return p
    }

    /// The stroked part of the icon, and its line width in view box units.
    var stroke: (path: Path, width: CGFloat)? {
        var p = Path()
        switch self {
        case .chevron:
            p.addLines([CGPoint(x: 1.5, y: 1), CGPoint(x: 5.5, y: 5), CGPoint(x: 1.5, y: 9)])
            return (p, 1.6)
        case .speakerLoud:
            // The SVG arcs "M10.5 4.5a3.5 3.5 0 010 5" and "M12.5 2.5a6.3 6.3 0 010 9".
            p.move(to: CGPoint(x: 10.5, y: 4.5))
            p.addArc(center: CGPoint(x: 8.05, y: 7), radius: 3.5, startAngle: .degrees(-45.6), endAngle: .degrees(45.6), clockwise: false)
            p.move(to: CGPoint(x: 12.5, y: 2.5))
            p.addArc(center: CGPoint(x: 8.09, y: 7), radius: 6.3, startAngle: .degrees(-45.6), endAngle: .degrees(45.6), clockwise: false)
            return (p, 1.3)
        case .note:
            p.addLines([CGPoint(x: 9, y: 18), CGPoint(x: 9, y: 5), CGPoint(x: 20, y: 3), CGPoint(x: 20, y: 16)])
            p.addEllipse(in: CGRect(x: 4, y: 15.5, width: 5, height: 5))
            p.addEllipse(in: CGRect(x: 15, y: 13.5, width: 5, height: 5))
            return (p, 1.6)
        case .prev, .next, .playPause, .speaker:
            return nil
        }
    }
}

/// Draws an icon in the current foreground style.
struct IconView: View {
    let icon: Icon
    let width: CGFloat
    let height: CGFloat

    init(_ icon: Icon, width: CGFloat, height: CGFloat) {
        self.icon = icon; self.width = width; self.height = height
    }

    var body: some View {
        let scale = CGAffineTransform(scaleX: width / icon.viewBox.width, y: height / icon.viewBox.height)
        ZStack {
            icon.fill.applying(scale).fill(.foreground)
            if let stroke = icon.stroke {
                stroke.path.applying(scale)
                    .stroke(.foreground, style: StrokeStyle(lineWidth: stroke.width * scale.a, lineJoin: .round))
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}
