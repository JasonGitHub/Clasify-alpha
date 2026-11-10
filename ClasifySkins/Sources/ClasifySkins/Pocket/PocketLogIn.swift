import ClasifyCore
import SwiftUI

/// What the small device on a setup screen shows on its screen (Round 13).
enum PreviewScreen: Equatable {
    /// A still Nano Rainbow hello (card AW).
    case hello
    /// Six faint empty rows: your music will appear here (card AX, change 134). While the
    /// browser is open they breathe slowly (change 170).
    case rows(breathe: Bool)
    /// The big green check and "Logged in" (change 175).
    case loggedIn

    /// The small device's screen and its sync cable on a setup screen. Nil on other screens.
    static func of(_ screen: Screen) -> (screen: PreviewScreen, cable: SyncCable.Plug?)? {
        switch screen {
        case .color: return (screen: PreviewScreen.hello, cable: nil)
        case .login, .loginFailed: return (screen: PreviewScreen.rows(breathe: false), cable: SyncCable.Plug.off)
        case .auth: return (screen: PreviewScreen.rows(breathe: true), cable: SyncCable.Plug.light)
        case .loggedIn: return (screen: PreviewScreen.loggedIn, cable: SyncCable.Plug.light)
        default: return nil
        }
    }
}

/// The login screens' words over the rows (card AX, change 134): a 14 point bold headline and
/// an 11 point line. The block is 77 points tall on every login screen, so the rows start at
/// the same place and the blue bar never jumps.
struct SetupMessage: View {
    let words: Labels.SetupWords

    static let height: CGFloat = 77

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(words.headline)
                .font(.helvetica(14, bold: true))
                .foregroundStyle(Color(hex: 0x1b1f24))
            Text(words.line)
                .font(.helvetica(11))
                .lineSpacing(2)
                .foregroundStyle(Color(hex: 0x5d6772))
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(EdgeInsets(top: 9, leading: 9, bottom: 0, trailing: 9))
        .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height, alignment: .topLeading)
    }
}

/// The small device's screen on the login screens, in the screen's own 300 x 225 points.
struct PreviewScreenContent: View {
    let screen: PreviewScreen
    @Environment(\.animationTime) private var fixedTime

    /// The faint rows' widths, as parts of the row width.
    static let rowWidths: [CGFloat] = [0.78, 0.62, 0.70, 0.54, 0.66, 0.48]

    /// The breathing rows' opacity at time `t`: 0.55 to 1 and back, over 2.4 s, eased.
    static func breath(at t: Double) -> Double {
        let u = max(0, t).truncatingRemainder(dividingBy: 2.4) / 2.4
        let e: Double = u < 0.5 ? Hello.ease(u * 2) : 1 - Hello.ease((u - 0.5) * 2)
        return 0.55 + 0.45 * e
    }

    var body: some View {
        let check = screen == .loggedIn
        ZStack {
            rows.opacity(check ? 0 : 1)
            mark.opacity(check ? 1 : 0)
        }
        .animation(.easeInOut(duration: 0.3), value: check)  // the rows crossfade to the check
        .frame(width: Pocket.screenWidth, height: Pocket.screenHeight)
        .background(Pocket.glass)
    }

    private var rows: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: fixedTime != nil || screen != .rows(breathe: true))) { context in
            let t = fixedTime ?? context.date.timeIntervalSinceReferenceDate
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Self.rowWidths.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: 0x1b1f24, opacity: 0.10))
                        .frame(width: (Pocket.screenWidth - 44) * Self.rowWidths[i], height: 15)
                }
            }
            .padding(EdgeInsets(top: 26, leading: 22, bottom: 0, trailing: 22))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .opacity(screen == .rows(breathe: true) ? Self.breath(at: t) : 1)
        }
    }

    /// The big green check (#34c759) and "Logged in" (#248a3d): a green check always means success.
    private var mark: some View {
        VStack(spacing: 6) {
            Path { p in
                p.move(to: CGPoint(x: 28, y: 52))
                p.addLine(to: CGPoint(x: 48, y: 72))
                p.addLine(to: CGPoint(x: 82, y: 30))
            }
            .stroke(Color(hex: 0x34c759), style: StrokeStyle(lineWidth: 13, lineCap: .round, lineJoin: .round))
            .frame(width: 110, height: 110)
            .scaleEffect(84.0 / 110)
            .frame(width: 84, height: 84)
            Text("Logged in")
                .font(.helvetica(38, bold: true))
                .kerning(-0.5)
                .foregroundStyle(Color(hex: 0x248a3d))
        }
    }
}

/// A thin white sync cable by the small device, like an iPod's (card AX, change 173).
/// Plugged in means that Clasify is connected to Spotify. Points are in the 110 x 190 preview.
struct SyncCable: View {
    enum Plug: Equatable {
        /// Unplugged, lying beside the device.
        case off
        /// Plugged in, with no light: connected, nothing happens.
        case on
        /// Plugged in, and a soft blue light travels up into the device every 2.4 s.
        case light
    }

    let plug: Plug
    @Environment(\.animationTime) private var fixedTime

    static let lightRound = 2.4

    /// The light's distance along the cable from its far end, and its opacity, at time `t`.
    static func light(at t: Double) -> (distance: Double, opacity: Double) {
        let u = max(0, t).truncatingRemainder(dividingBy: lightRound) / lightRound
        var opacity: Double = 1
        if u < 0.1 { opacity = Hello.ease(u / 0.1) } else if u > 0.8 { opacity = 1 - Hello.ease((u - 0.8) / 0.2) }
        return (150 * Hello.ease(u), opacity)
    }

    /// From the far end to the plug, which overlaps the device's bottom edge.
    static var pluggedPath: Path {
        Path { p in
            p.move(to: CGPoint(x: 140, y: 197))
            p.addLine(to: CGPoint(x: 72, y: 197))
            p.addCurve(to: CGPoint(x: 55, y: 187), control1: CGPoint(x: 62, y: 197), control2: CGPoint(x: 55, y: 196))
        }
    }

    static var unpluggedPath: Path {
        Path { p in
            p.move(to: CGPoint(x: 140, y: 196))
            p.addLine(to: CGPoint(x: 86, y: 196))
        }
    }

    var body: some View {
        let plugged = plug != .off
        ZStack(alignment: .topLeading) {
            cable(Self.unpluggedPath) {
                ZStack(alignment: .topLeading) {
                    plugBody.offset(x: 76, y: 193)
                    RoundedRectangle(cornerRadius: 0.6).fill(Color(hex: 0xc3cad1))
                        .frame(width: 4, height: 3).offset(x: 72, y: 194.5)
                }
            }
            .opacity(plugged ? 0 : 1)
            cable(Self.pluggedPath) { plugBody.offset(x: 50, y: 181) }
                .opacity(plugged ? 1 : 0)
            if plug == .light { flow }
        }
        .animation(.easeInOut(duration: 0.4), value: plugged)  // it plugs in, in 0.4 s
        .frame(width: 160, height: 210, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A white cable with a gray edge, and its plug.
    private func cable<P: View>(_ path: Path, @ViewBuilder plug: () -> P) -> some View {
        ZStack(alignment: .topLeading) {
            path.stroke(Color(hex: 0xb9c2cb), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            path.stroke(Color(hex: 0xf7f8f9), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
            plug()
        }
    }

    private var plugBody: some View {
        RoundedRectangle(cornerRadius: 1.5).fill(Color(hex: 0xe9ecef))
            .overlay(RoundedRectangle(cornerRadius: 1.5).stroke(Color(hex: 0x9aa4ae), lineWidth: 0.8))
            .frame(width: 10, height: 6)
    }

    /// The light: a 14 point dash with a soft glow, the same blue as the rim light.
    private var flow: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: fixedTime != nil)) { context in
            let light = Self.light(at: fixedTime ?? context.date.timeIntervalSinceReferenceDate)
            let dash: [CGFloat] = [14, 200]
            ZStack(alignment: .topLeading) {
                Self.pluggedPath
                    .stroke(Color(hex: 0x5aa3f0, opacity: 0.5),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: dash, dashPhase: -light.distance))
                    .blur(radius: 1.5)
                Self.pluggedPath
                    .stroke(Color(hex: 0x7db7f5),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: dash, dashPhase: -light.distance))
            }
            .opacity(light.opacity)
        }
    }
}
