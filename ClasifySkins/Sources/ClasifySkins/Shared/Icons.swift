import SwiftUI

/// The mockup's SVG icons as shapes. Each path uses the SVG's own view box and scales to its frame.
enum Icon: Sendable {
    case chevron, prev, next, playPause, speaker, speakerLoud
    /// The joined notes on the cover placeholder.
    case notes
    /// The song list bar's note (Round 7 card W, change 55): the mockup's path, with bigger heads.
    case barNote
    /// The title bar's play and pause marks.
    case play, pause

    var viewBox: CGSize {
        switch self {
        case .chevron: CGSize(width: 8, height: 12)
        case .prev, .next: CGSize(width: 16, height: 8.4)
        case .playPause: CGSize(width: 20, height: 8)
        case .speaker: CGSize(width: 14, height: 14)
        case .speakerLoud: CGSize(width: 16, height: 14)
        case .notes: CGSize(width: 24, height: 24)
        case .barNote: CGSize(width: 16, height: 16)
        case .play, .pause: CGSize(width: 8, height: 9)
        }
    }

    /// The filled part of the icon.
    var fill: Path {
        var p = Path()
        switch self {
        case .chevron:
            break
        case .notes:
            p.addEllipse(in: CGRect(x: 3.2, y: 15.2, width: 6, height: 6))
            p.addEllipse(in: CGRect(x: 14.2, y: 13.2, width: 6, height: 6))
            p.addRect(CGRect(x: 7.6, y: 4.8, width: 1.8, height: 13.4))
            p.addRect(CGRect(x: 18.6, y: 2.4, width: 1.8, height: 13.8))
            p.addLines([CGPoint(x: 7.6, y: 4.8), CGPoint(x: 20.4, y: 1.9), CGPoint(x: 20.4, y: 5.3), CGPoint(x: 7.6, y: 8.2)])
            p.closeSubpath()
        case .barNote:
            // The SVG "M5 3l9-2v10.5a2.3 2.3 0 11-1.6-2.2V4.6L6.6 5.8v7.7a2.3 2.3 0 11-1.6-2.2z". Each
            // arc is a head: radius 2.3, from the stem's right edge the long way round to its left.
            p.move(to: CGPoint(x: 5, y: 3))
            p.addLine(to: CGPoint(x: 14, y: 1))
            p.addLine(to: CGPoint(x: 14, y: 11.5))
            p.addArc(center: CGPoint(x: 11.7, y: 11.491), radius: 2.3, startAngle: .degrees(0.23), endAngle: .degrees(-72.28), clockwise: false)
            p.addLine(to: CGPoint(x: 12.4, y: 4.6))
            p.addLine(to: CGPoint(x: 6.6, y: 5.8))
            p.addLine(to: CGPoint(x: 6.6, y: 13.5))
            p.addArc(center: CGPoint(x: 4.3, y: 13.491), radius: 2.3, startAngle: .degrees(0.23), endAngle: .degrees(-72.28), clockwise: false)
            p.closeSubpath()
        case .play:
            p.addLines([CGPoint(x: 0.5, y: 0.5), CGPoint(x: 7.5, y: 4.5), CGPoint(x: 0.5, y: 8.5)])
            p.closeSubpath()
        case .pause:
            p.addRect(CGRect(x: 0.75, y: 0.5, width: 2.5, height: 8))
            p.addRect(CGRect(x: 4.75, y: 0.5, width: 2.5, height: 8))
        case .prev:  // the bar on the outside, as in the photo
            p.addRect(CGRect(x: 0, y: 0, width: 1.8, height: 8.4))
            p.addLines([CGPoint(x: 8.8, y: 0), CGPoint(x: 1.8, y: 4.2), CGPoint(x: 8.8, y: 8.4)])
            p.closeSubpath()
            p.addLines([CGPoint(x: 16, y: 0), CGPoint(x: 9, y: 4.2), CGPoint(x: 16, y: 8.4)])
            p.closeSubpath()
        case .next:
            p.addLines([CGPoint(x: 0, y: 0), CGPoint(x: 7, y: 4.2), CGPoint(x: 0, y: 8.4)])
            p.closeSubpath()
            p.addLines([CGPoint(x: 7.2, y: 0), CGPoint(x: 14.2, y: 4.2), CGPoint(x: 7.2, y: 8.4)])
            p.closeSubpath()
            p.addRect(CGRect(x: 14.2, y: 0, width: 1.8, height: 8.4))
        case .playPause:
            p.addLines([CGPoint(x: 0, y: 0), CGPoint(x: 7.5, y: 4), CGPoint(x: 0, y: 8)])
            p.closeSubpath()
            p.addRect(CGRect(x: 11, y: 0, width: 3, height: 8))
            p.addRect(CGRect(x: 16.5, y: 0, width: 3, height: 8))
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
        case .prev, .next, .playPause, .speaker, .notes, .barNote, .play, .pause:
            return nil
        }
    }

    /// The SVG gives these strokes round ends.
    var roundCaps: Bool {
        switch self {
        case .chevron: true
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
