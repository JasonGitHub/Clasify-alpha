import ClasifyCore
import SwiftUI

/// The color pick's times (Round 13, card AW, changes 149, 150, 179 and 203; Round 20, card
/// BQ, change 287). No light follows the turn (card AW.1, change 236 removed change 202).
enum ColorPick {
    /// Change 287: until the first turn, a fingertip dot shows the turn. It loops every 4.6 s.
    static let fingerLoop = 4.6
    /// The fingertip dot fades out in 0.3 s at the first color step, and does not come back.
    static let fingerOut = 0.3
    /// Change 203: the device color crossfades in 0.45 s, on the device and the small preview.
    static let colorFade = 0.45
    /// "Turn the wheel to try one" fades in 2 s after the pick opens (changes 149 and 179).
    static let turnHintAfter = 2.0
    /// "Then press center button" fades in after 3 pulses of the center glow (change 150).
    static let pressHintAfter = 7.2

    /// The fingertip dot `t` seconds after the pick opened (the mock's keyframes `fgr` and
    /// `fgo`): its angle in degrees, clockwise from 12 o'clock, and its opacity. In each loop it
    /// is hidden to 0.6 s, fades in by 0.8 s at 10 o'clock (-60°), turns to 3 o'clock (90°) by
    /// 2.0 s and back to -60° by 3.1 s, and fades out by 3.3 s. The turns ease as
    /// cubic-bezier(.45, 0, .55, 1); the fades as CSS `ease`, cubic-bezier(.25, .1, .25, 1).
    static func finger(at t: Double) -> (angle: Double, opacity: Double) {
        guard t >= 0 else { return (-60, 0) }
        let x = t.truncatingRemainder(dividingBy: fingerLoop)
        func turn(_ a: Double, _ b: Double, _ from: Double, _ to: Double) -> Double {
            a + (b - a) * bezier((x - from) / (to - from), 0.45, 0, 0.55, 1)
        }
        func fade(_ from: Double, _ to: Double) -> Double { bezier((x - from) / (to - from), 0.25, 0.1, 0.25, 1) }
        let angle: Double = x < 0.8 ? -60 : x < 2.0 ? turn(-60, 90, 0.8, 2.0) : x < 3.1 ? turn(90, -60, 2.0, 3.1) : -60
        let opacity: Double = x < 0.6 ? 0 : x < 0.8 ? fade(0.6, 0.8) : x < 3.1 ? 1 : x < 3.3 ? 1 - fade(3.1, 3.3) : 0
        return (angle, opacity)
    }

    /// CSS cubic-bezier(x1, y1, x2, y2) at `x`: finds the curve point with that x by bisection,
    /// and returns its y.
    static func bezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        func curve(_ s: Double, _ a: Double, _ b: Double) -> Double {
            3 * (1 - s) * (1 - s) * s * a + 3 * (1 - s) * s * s * b + s * s * s
        }
        var low = 0.0, high = 1.0
        for _ in 0..<40 {
            let mid = (low + high) / 2
            if curve(mid, x1, x2) < x { low = mid } else { high = mid }
        }
        return curve((low + high) / 2, y1, y2)
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

/// The fingertip dot on the wheel (card BQ, change 287), as on the launch page: 33 pt round,
/// CSS `radial-gradient(rgba(90,163,240,.6), rgba(90,163,240,0) 70%)`, its center on a circle
/// 83 pt from the wheel's center. The same on Silver and Black. It turns about the wheel's
/// center from `from`, the time the pick opened.
struct FingerDot: View {
    let from: Double
    @Environment(\.animationTime) private var fixedTime
    static let size: CGFloat = 33, radius: CGFloat = 83

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: fixedTime != nil)) { context in
            let finger = ColorPick.finger(at: (fixedTime ?? context.date.timeIntervalSinceReferenceDate) - from)
            // A CSS radial gradient with no size is an ellipse to the farthest corner: on a
            // square, a circle of half the diagonal.
            Circle()
                .fill(RadialGradient(
                    stops: [
                        .init(color: Color(hex: 0x5aa3f0, opacity: 0.6), location: 0),
                        .init(color: Color(hex: 0x5aa3f0, opacity: 0), location: 0.7),
                    ],
                    center: .center, startRadius: 0, endRadius: Self.size / 2 * 2.0.squareRoot()))
                .frame(width: Self.size, height: Self.size)
                .position(x: ClickWheel.size / 2, y: ClickWheel.size / 2 - Self.radius)
                .frame(width: ClickWheel.size, height: ClickWheel.size)
                .rotationEffect(.degrees(finger.angle))
                .opacity(finger.opacity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
