import SwiftUI

/// The mockup's SVG icons as shapes. Each path uses the SVG's own view box and scales to its frame.
enum Icon: Sendable {
    case chevron, prev, next, playPause, speaker, speakerLoud
    /// The joined notes on a track that has no cover.
    case notes
    /// The title bar's play and pause marks.
    case play, pause
    /// The Now Playing status icons.
    case shuffle, repeatMode

    var viewBox: CGSize {
        switch self {
        case .chevron: CGSize(width: 8, height: 12)
        case .prev, .next: CGSize(width: 18, height: 12)
        case .playPause: CGSize(width: 20, height: 12)
        case .speaker: CGSize(width: 14, height: 14)
        case .speakerLoud: CGSize(width: 16, height: 14)
        case .notes: CGSize(width: 24, height: 24)
        case .play, .pause: CGSize(width: 9, height: 10)
        case .shuffle, .repeatMode: CGSize(width: 16, height: 14)
        }
    }

    /// The filled part of the icon.
    var fill: Path {
        var p = Path()
        switch self {
        case .chevron, .shuffle, .repeatMode:
            break
        case .notes:
            p.addEllipse(in: CGRect(x: 3.2, y: 15.2, width: 6, height: 6))
            p.addEllipse(in: CGRect(x: 14.2, y: 13.2, width: 6, height: 6))
            p.addRect(CGRect(x: 7.6, y: 4.8, width: 1.8, height: 13.4))
            p.addRect(CGRect(x: 18.6, y: 2.4, width: 1.8, height: 13.8))
            p.addLines([CGPoint(x: 7.6, y: 4.8), CGPoint(x: 20.4, y: 1.9), CGPoint(x: 20.4, y: 5.3), CGPoint(x: 7.6, y: 8.2)])
            p.closeSubpath()
        case .play:
            p.addLines([CGPoint(x: 1, y: 0.5), CGPoint(x: 8.5, y: 5), CGPoint(x: 1, y: 9.5)])
            p.closeSubpath()
        case .pause:
            p.addRect(CGRect(x: 1, y: 0.5, width: 2.6, height: 9))
            p.addRect(CGRect(x: 5.4, y: 0.5, width: 2.6, height: 9))
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
            p.addLines([CGPoint(x: 2, y: 1.5), CGPoint(x: 6.5, y: 6), CGPoint(x: 2, y: 10.5)])
            return (p, 2)
        case .speakerLoud:
            // The SVG arcs "M10.5 4.5a3.5 3.5 0 010 5" and "M12.5 2.5a6.3 6.3 0 010 9".
            p.move(to: CGPoint(x: 10.5, y: 4.5))
            p.addArc(center: CGPoint(x: 8.05, y: 7), radius: 3.5, startAngle: .degrees(-45.6), endAngle: .degrees(45.6), clockwise: false)
            p.move(to: CGPoint(x: 12.5, y: 2.5))
            p.addArc(center: CGPoint(x: 8.09, y: 7), radius: 6.3, startAngle: .degrees(-45.6), endAngle: .degrees(45.6), clockwise: false)
            return (p, 1.3)
        case .shuffle:  // "M1 3h3l7 8h3 M1 11h3l2-2.3 M9 5.3L11 3h3 M12 1l2 2-2 2 M12 9l2 2-2 2"
            p.addLines([CGPoint(x: 1, y: 3), CGPoint(x: 4, y: 3), CGPoint(x: 11, y: 11), CGPoint(x: 14, y: 11)])
            p.addLines([CGPoint(x: 1, y: 11), CGPoint(x: 4, y: 11), CGPoint(x: 6, y: 8.7)])
            p.addLines([CGPoint(x: 9, y: 5.3), CGPoint(x: 11, y: 3), CGPoint(x: 14, y: 3)])
            p.addLines([CGPoint(x: 12, y: 1), CGPoint(x: 14, y: 3), CGPoint(x: 12, y: 5)])
            p.addLines([CGPoint(x: 12, y: 9), CGPoint(x: 14, y: 11), CGPoint(x: 12, y: 13)])
            return (p, 1.5)
        case .repeatMode:  // two arrows with rounded corners, from the SVG
            p.move(to: CGPoint(x: 3, y: 6))
            p.addArc(tangent1End: CGPoint(x: 3, y: 3), tangent2End: CGPoint(x: 4.5, y: 3), radius: 1.5)
            p.addLine(to: CGPoint(x: 13, y: 3))
            p.addLines([CGPoint(x: 11, y: 1), CGPoint(x: 13, y: 3), CGPoint(x: 11, y: 5)])
            p.move(to: CGPoint(x: 13, y: 8))
            p.addArc(tangent1End: CGPoint(x: 13, y: 11), tangent2End: CGPoint(x: 11.5, y: 11), radius: 1.5)
            p.addLine(to: CGPoint(x: 3, y: 11))
            p.addLines([CGPoint(x: 5, y: 13), CGPoint(x: 3, y: 11), CGPoint(x: 5, y: 9)])
            return (p, 1.5)
        case .prev, .next, .playPause, .speaker, .notes, .play, .pause:
            return nil
        }
    }

    /// The SVG gives these strokes round ends.
    var roundCaps: Bool {
        switch self {
        case .chevron, .shuffle, .repeatMode: true
        default: false
        }
    }
}

/// Draws an icon in the current foreground style.
struct IconView: View {
    let icon: Icon
    let width: CGFloat
    let height: CGFloat
    /// The VoiceOver label of an icon that shows a state. Without one, VoiceOver skips the icon.
    let label: String?

    init(_ icon: Icon, width: CGFloat, height: CGFloat, label: String? = nil) {
        self.icon = icon; self.width = width; self.height = height; self.label = label
    }

    var body: some View {
        let scale = CGAffineTransform(scaleX: width / icon.viewBox.width, y: height / icon.viewBox.height)
        ZStack {
            icon.fill.applying(scale).fill(.foreground)
            if let stroke = icon.stroke {
                stroke.path.applying(scale)
                    .stroke(.foreground, style: StrokeStyle(
                        lineWidth: stroke.width * scale.a, lineCap: icon.roundCaps ? .round : .butt, lineJoin: .round))
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .accessibilityElement()
        .accessibilityLabel(label ?? "")
        .accessibilityHidden(label == nil)
    }
}
