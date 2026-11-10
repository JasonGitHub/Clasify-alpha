import ClasifyCore
import SwiftUI

/// The color pick's times (Round 13, card AW, changes 149, 150, 179 and 200 to 203).
enum ColorPick {
    /// Change 200: until the first turn, the comet goes 180° clockwise from 9 o'clock over the
    /// top to 3 o'clock in 2.9 s, then rests 1 s.
    static let sweep = 2.9, loop = 3.9
    /// Change 202: the light under the thumb fades in in 0.3 s and glides 0.16 s to each new
    /// angle. 0.6 s after the last move it fades out in 0.6 s. Its long tail fades in in 0.35 s.
    /// The waiting light fades out in 0.4 s at the first touch.
    static let fadeIn = 0.3, glide = 0.16, hold = 0.6, fadeOut = 0.6, tailIn = 0.35, waitingOut = 0.4
    /// Change 203: the device color crossfades in 0.45 s, on the device and the small preview.
    static let colorFade = 0.45
    /// "Turn the wheel to try one" fades in 2 s after the pick opens (changes 149 and 179).
    static let turnHintAfter = 2.0
    /// "Then press center button" fades in after 3 pulses of the center glow (change 150).
    static let pressHintAfter = 7.2

    /// The waiting comet `t` seconds after the pick opened: its angle in degrees, clockwise from
    /// 3 o'clock; its opacity, which fades in and out at the ends; and its long tail, which
    /// follows the speed of the sine ease (full at 12 o'clock). Nil while it rests.
    static func waiting(at t: Double) -> (angle: Double, opacity: Double, longTail: Double)? {
        guard t >= 0 else { return nil }
        let x = t.truncatingRemainder(dividingBy: loop) / sweep
        guard x <= 1 else { return nil }
        let eased = (1 - cos(.pi * x)) / 2
        return (180 + 180 * eased, min(1, x / 0.1, (1 - x) / 0.1), sin(.pi * x))
    }

    /// The light under the thumb: its opacity and its long tail, `since` seconds after it came
    /// and `idle` seconds after the last move.
    static func following(since: Double, idle: Double) -> (opacity: Double, longTail: Double) {
        let fade = min(max(since / fadeIn, 0), 1) * min(max(1 - (idle - hold) / fadeOut, 0), 1)
        return (fade, min(max(since / tailIn, 0), 1))
    }

    /// The hint under the rows and its opacity at time `now`: before the first turn, the turn
    /// hint after 2 s; after it, the press hint 7.2 s after the turn. Each fades in 0.4 s.
    static func hint(openedAt: Double, turnedAt: Double, now: Double) -> (text: String, opacity: Double) {
        if turnedAt > 0 {
            return ("Then press center button", min(max((now - turnedAt - pressHintAfter) / 0.4, 0), 1))
        }
        return ("Turn the wheel to try one", min(max((now - openedAt - turnHintAfter) / 0.4, 0), 1))
    }
}

/// The color pick's words under the rows: the hint (card AW, changes 149 and 150), and at the
/// bottom of the list a line that is always there (change 138).
struct ColorPickWords: View {
    let state: AppState
    @Environment(\.animationTime) private var fixedTime

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: fixedTime != nil)) { context in
                let now = fixedTime ?? context.date.timeIntervalSinceReferenceDate
                let hint = ColorPick.hint(openedAt: state.colorAt, turnedAt: state.colorTurnAt, now: now)
                Text(hint.text)
                    .font(.helvetica(11))
                    .foregroundStyle(Color(hex: 0x5d6772))
                    .opacity(hint.opacity)
            }
            .padding(.top, 8)
            Spacer(minLength: 0)
            Text("You can always change it in Settings.")
                .font(.helvetica(10))
                .foregroundStyle(Color(hex: 0x5d6772))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 6)
                .padding(.bottom, 10)
        }
        .padding(.leading, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The right side of a setup screen: the small device on a white glow (card AW, change 138).
/// It is our device drawing at 30% of its size (20% of the board's 1.5x drawing), with a soft
/// floor shadow and no drop shadow of its own. Its screen shows a still Nano Rainbow hello,
/// or on the login screens (card AX) faint rows or the green check, with the sync cable.
struct SetupPreview: View {
    let color: DeviceColor
    var screen: PreviewScreen = .hello
    var cable: SyncCable.Plug?

    /// The top left corner of the device's screen in `PocketSkin`: the bezel is centered, and
    /// the glass is 6.6 points inside it, under the 25.8 point top padding.
    static let glass = CGPoint(x: (PocketSkin.size.width - Pocket.screenWidth) / 2, y: 25.8 + 6.6)

    static let scale: CGFloat = 0.3

    var body: some View {
        ZStack {
            // radial-gradient(circle at 50% 42%, #ffffff, #d6e2ec 78%) on the 150 x 225 side.
            RadialGradient(
                colors: [.white, Color(hex: 0xd6e2ec)], center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 0, endRadius: 0.78 * hypot(75, 225 * 0.58))
            ZStack(alignment: .topLeading) {
                // The floor shadow: 10 points in from each side, 5 points under the box, 12 tall.
                EllipticalGradient(colors: [Color(hex: 0x141e28, opacity: 0.28), Color(hex: 0x141e28, opacity: 0)])
                    .frame(width: 90, height: 12)
                    .offset(x: 10, y: 183)
                ZStack(alignment: .topLeading) {
                    PocketSkin(state: Self.state(color), interactive: false)
                    if screen != .hello {
                        PreviewScreenContent(screen: screen)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                            .offset(x: Self.glass.x, y: Self.glass.y)
                    }
                }
                .environment(\.pocketPreview, true)
                .scaleEffect(Self.scale, anchor: .topLeading)
                .frame(width: PocketSkin.size.width * Self.scale, height: PocketSkin.size.height * Self.scale, alignment: .topLeading)
                if let cable { SyncCable(plug: cable) }
            }
            .frame(width: 110, height: 190, alignment: .topLeading)
        }
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("\(color.rawValue) device")
    }

    /// The small device's state: Hello, in the color.
    static func state(_ color: DeviceColor) -> AppState {
        var s = AppState()
        s.stack = [Frame(screen: .hello)]
        s.deviceColor = color
        return s
    }
}

/// The comet on the wheel (card AW, change 201), drawn at 3 o'clock and turned into place.
/// A dot head #8cc2f8 with a small white shine and a #5aa3f0 glow, at radius 105. A short tail
/// of 15° always shows; the long tail of 60° shows by `longTail`. Each tail tapers from 4.2 pt
/// to a point and fades from 90% at the head to 0. The paths never change: a frame changes
/// only the rotation and two opacities.
struct Comet: View {
    var longTail: Double
    static let radius: CGFloat = 105

    var body: some View {
        let head = CGPoint(x: ClickWheel.size / 2 + Self.radius, y: ClickWheel.size / 2)
        ZStack {
            Self.tail(60).opacity(longTail)
            Self.tail(15)
            Circle().fill(Color(hex: 0x5aa3f0, opacity: 0.45)).frame(width: 11, height: 11).blur(radius: 2.5)
                .position(head)
            Circle().fill(Color(hex: 0x8cc2f8)).frame(width: 5.4, height: 5.4).position(head)
            Circle().fill(Color.white.opacity(0.85)).frame(width: 1.8, height: 1.8)
                .position(x: head.x - 0.8, y: head.y - 0.9)
        }
        .frame(width: ClickWheel.size, height: ClickWheel.size)
        .clipShape(Circle())  // the glow stays on the wheel
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func tail(_ span: Double) -> some View {
        let fill = AngularGradient(
            stops: [.init(color: Color(hex: 0x6aaef5, opacity: 0), location: 0), .init(color: Color(hex: 0x6aaef5, opacity: 0.9), location: 1)],
            center: .center, startAngle: .degrees(-span), endAngle: .degrees(0))
        return Tail(span: span).fill(fill)
            .shadow(color: Color(hex: 0x5aa3f0, opacity: 0.45), radius: 2.5)
    }

    /// A tail behind a clockwise head at 3 o'clock: 4.2 pt wide at the head, to a point.
    struct Tail: Shape {
        let span: Double

        func path(in rect: CGRect) -> Path {
            let c = CGPoint(x: rect.midX, y: rect.midY), steps = 24
            func point(_ k: Int, _ side: CGFloat) -> CGPoint {
                let f = Double(k) / Double(steps), a = -span * f * .pi / 180
                let r = Comet.radius + side * 2.1 * (1 - f)
                return CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            }
            var path = Path()
            path.move(to: point(0, 1))
            for k in 1...steps { path.addLine(to: point(k, 1)) }
            for k in stride(from: steps, through: 0, by: -1) { path.addLine(to: point(k, -1)) }
            path.closeSubpath()
            return path
        }
    }
}

/// The waiting comet until the first touch (change 200).
struct WaitingComet: View {
    let from: Double
    @Environment(\.animationTime) private var fixedTime

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: fixedTime != nil)) { context in
            let t = (fixedTime ?? context.date.timeIntervalSinceReferenceDate) - from
            let light = ColorPick.waiting(at: t)
            Comet(longTail: light?.longTail ?? 0)
                .rotationEffect(.degrees(light?.angle ?? 0))
                .opacity(light?.opacity ?? 0)
        }
    }
}

/// The light under the thumb (change 202). It glides to each new angle, head first in the
/// turn direction, and fades out after the last move.
struct ThumbComet: View {
    let light: ClickWheel.ThumbLight

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { context in
            let now = context.date.timeIntervalSinceReferenceDate
            let shown = ColorPick.following(since: now - light.from, idle: now - light.last)
            Comet(longTail: shown.longTail)
                .scaleEffect(x: 1, y: light.clockwise ? 1 : -1)  // the tail behind the head
                .rotationEffect(.degrees(light.angle))
                .animation(.easeOut(duration: ColorPick.glide), value: light.angle)
                .opacity(shown.opacity)
        }
    }
}
