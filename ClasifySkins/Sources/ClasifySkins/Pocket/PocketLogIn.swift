import ClasifyCore
import SwiftUI

/// What the small device on a setup screen shows on its screen (Round 13).
enum PreviewScreen: Equatable {
    /// A still Nano Rainbow hello (card AW).
    case hello
    /// Six faint empty rows: your music will appear here (card AX, change 134). While the
    /// browser is open they breathe slowly (change 170).
    case rows(breathe: Bool)
    /// One big mark and one big word: the green check for success ("Logged in", change 175;
    /// "Linked", change 174), else the gray cross ("Not found", change 174).
    case mark(ok: Bool, word: String)
    /// The playlist names fill in one by one from time `from`, like an iPod sync (card AY, 141).
    case names([String], from: Double)

    /// The small device's screen and its sync cable on a setup screen. Nil on other screens.
    static func of(_ screen: Screen, in state: AppState) -> (screen: PreviewScreen, cable: SyncCable.Plug?)? {
        switch screen {
        case .spotifyApp where state.spotifyApp == true:
            return (screen: PreviewScreen.mark(ok: true, word: "Linked"), cable: SyncCable.Plug.light)
        case .spotifyApp: return (screen: PreviewScreen.mark(ok: false, word: "Not found"), cable: SyncCable.Plug.off)
        case .color: return (screen: PreviewScreen.hello, cable: nil)
        case .login, .loginFailed: return (screen: PreviewScreen.rows(breathe: false), cable: SyncCable.Plug.off)
        case .auth: return (screen: PreviewScreen.rows(breathe: true), cable: SyncCable.Plug.light)
        case .loggedIn: return (screen: PreviewScreen.mark(ok: true, word: "Logged in"), cable: SyncCable.Plug.light)
        case .yourMusic where state.top.error: return nil  // the error message fills the screen
        case .yourMusic where state.top.loading:
            let names = state.namesAt > 0
                ? Array(state.library.filter { $0.id != Playlist.likedSongsID && !Album.isID($0.id) }.prefix(6).map(\.name))
                : []
            return (screen: PreviewScreen.names(names, from: state.namesAt), cable: SyncCable.Plug.light)
        case .yourMusic: return (screen: PreviewScreen.mark(ok: true, word: "Synced"), cable: SyncCable.Plug.on)
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
        // The rows, the cross and the check crossfade in 0.3 s.
        let shown: Int = switch screen {
        case .mark(let ok, _): ok ? 2 : 1
        case .names: 3
        default: 0
        }
        ZStack {
            rows.opacity(shown == 0 ? 1 : 0)
            if case .names(let list, let from) = screen { names(list, from: from) }
            mark(ok: false, word: "Not found").opacity(shown == 1 ? 1 : 0)
            mark(ok: true, word: Self.okWord(screen)).opacity(shown == 2 ? 1 : 0)
        }
        .animation(.easeInOut(duration: 0.3), value: shown)
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

    /// Row `i`'s opacity at `t` seconds after the read began: each name fades in and rises
    /// over 0.3 s, 0.6 s after the one before it.
    static func nameOpacity(_ i: Int, at t: Double) -> Double {
        min(max((t - 0.5 - 0.6 * Double(i)) / 0.3, 0), 1)
    }

    /// The playlist names: bold 17 point rows, 27 points tall, from 20 points down.
    private func names(_ list: [String], from: Double) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: fixedTime != nil)) { context in
            let t = (fixedTime ?? context.date.timeIntervalSinceReferenceDate) - from
            VStack(alignment: .leading, spacing: 0) {
                ForEach(list.indices, id: \.self) { i in
                    let shown = Self.nameOpacity(i, at: t)
                    Text(list[i])
                        .font(.helvetica(17, bold: true))
                        .foregroundStyle(Pocket.ink)
                        .lineLimit(1)
                        .frame(height: 27)
                        .opacity(shown)
                        .offset(y: 4 * (1 - shown))
                }
            }
            .padding(EdgeInsets(top: 20, leading: 22, bottom: 0, trailing: 22))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// The word of the green check: "Logged in" or "Linked".
    static func okWord(_ screen: PreviewScreen) -> String {
        if case .mark(true, let word) = screen { return word }
        return "Logged in"
    }

    /// The green check (#34c759) with its word in #248a3d: a green check always means success.
    /// Else a gray cross (#9aa4ae) with its word in #5d6772: gray, no red (change 174).
    private func mark(ok: Bool, word: String) -> some View {
        VStack(spacing: 6) {
            Path { p in
                if ok {
                    p.move(to: CGPoint(x: 28, y: 52))
                    p.addLine(to: CGPoint(x: 48, y: 72))
                    p.addLine(to: CGPoint(x: 82, y: 30))
                } else {
                    p.move(to: CGPoint(x: 32, y: 32))
                    p.addLine(to: CGPoint(x: 78, y: 78))
                    p.move(to: CGPoint(x: 78, y: 32))
                    p.addLine(to: CGPoint(x: 32, y: 78))
                }
            }
            .stroke(
                Color(hex: ok ? 0x34c759 : 0x9aa4ae),
                style: StrokeStyle(lineWidth: ok ? 13 : 12, lineCap: .round, lineJoin: .round))
            .frame(width: 110, height: 110)
            .scaleEffect(84.0 / 110)
            .frame(width: 84, height: 84)
            Text(word)
                .font(.helvetica(38, bold: true))
                .kerning(-0.5)
                .foregroundStyle(Color(hex: ok ? 0x248a3d : 0x5d6772))
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

/// The first library read's bar (card AY, change 141): 6 points, a faint track and a fill in
/// the selection blue, with "312 of 1,240 songs" under it. Until the library knows the total,
/// a part of the blue moves to and fro, with no number.
struct SetupProgress: View {
    let done: Int, total: Int
    @Environment(\.animationTime) private var fixedTime

    /// "312 of 1,240 songs", or nil before the total is known.
    static func count(done: Int, total: Int) -> String? {
        total > 0 ? "\(min(done, total).formatted()) of \(total.formatted()) songs" : nil
    }

    /// The moving part's left edge, as a part of the free track, at time `t`: 0 to 1 and back in 2.4 s, eased.
    static func position(at t: Double) -> Double {
        let u = max(0, t).truncatingRemainder(dividingBy: 2.4) / 2.4
        return u < 0.5 ? Hello.ease(u * 2) : 1 - Hello.ease((u - 0.5) * 2)
    }

    var body: some View {
        let count = Self.count(done: done, total: total)
        VStack(alignment: .leading, spacing: 6) {
            if total > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(hex: 0x1b1f24, opacity: 0.10))
                        Capsule().fill(Pocket.selection)
                            .frame(width: max(6, geo.size.width * CGFloat(min(done, total)) / CGFloat(total)))
                    }
                }
                .frame(height: 6)
                .animation(.linear(duration: 0.3), value: done)  // the fill grows between the library's reports
            } else {
                sweep
            }
            if let count {
                Text(count)
                    .font(.helvetica(11))
                    .monospacedDigit()
                    .foregroundStyle(Color(hex: 0x5d6772))
            }
        }
        .padding(.horizontal, 9)
        .accessibilityElement()
        .accessibilityLabel(count ?? "Getting your music")
    }

    /// Before the total is known: a part of the blue moves to and fro.
    private var sweep: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: fixedTime != nil)) { context in
            let x = Self.position(at: fixedTime ?? context.date.timeIntervalSinceReferenceDate)
            GeometryReader { geo in
                let part = geo.size.width * 0.35
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: 0x1b1f24, opacity: 0.10))
                    Capsule().fill(Pocket.selection)
                        .frame(width: part)
                        .offset(x: (geo.size.width - part) * x)
                }
            }
            .frame(height: 6)
        }
    }
}
