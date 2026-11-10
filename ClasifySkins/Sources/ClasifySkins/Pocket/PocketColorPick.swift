import ClasifyCore
import SwiftUI

/// The color pick's times (Round 13, card AW, changes 148 to 150).
enum ColorPick {
    /// The rim light goes once around the wheel every 3 s until the first turn (change 148).
    static let rimRound = 3.0
    /// "Turn the wheel to try one" fades in after 3 rounds (change 149).
    static let turnHintAfter = 9.0
    /// "Then press center button" fades in after 3 pulses of the center glow (change 150).
    static let pressHintAfter = 7.2

    /// The rim light's angle in degrees, clockwise from 3 o'clock, `t` seconds after the pick
    /// opened. Each round eases in and out.
    static func rimAngle(at t: Double) -> Double {
        let round = max(0, t).truncatingRemainder(dividingBy: rimRound) / rimRound
        return Hello.ease(round) * 360
    }

    /// The hint under the rows and its opacity at time `now`: before the first turn, the turn
    /// hint after 9 s; after it, the press hint 7.2 s after the turn. Each fades in 0.4 s.
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

/// The light that goes around the wheel's outer edge until the first turn (card AW, change
/// 148): 10% of the rim, a 2 point core #7db7f5 at radius 111 and a 9 point glow #5aa3f0.
struct RimLight: View {
    let from: Double
    @Environment(\.animationTime) private var fixedTime

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: fixedTime != nil)) { context in
            let t = (fixedTime ?? context.date.timeIntervalSinceReferenceDate) - from
            ZStack {
                Circle().trim(from: 0, to: 0.1)
                    .stroke(Color(hex: 0x5aa3f0, opacity: 0.45), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .frame(width: 220, height: 220)
                    .blur(radius: 3)
                Circle().trim(from: 0, to: 0.1)
                    .stroke(Color(hex: 0x7db7f5, opacity: 0.95), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 222, height: 222)
            }
            .rotationEffect(.degrees(ColorPick.rimAngle(at: t)))
        }
        .frame(width: ClickWheel.size, height: ClickWheel.size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
