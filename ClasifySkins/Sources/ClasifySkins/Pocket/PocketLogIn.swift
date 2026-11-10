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
    /// "Linked", change 174; "Premium", screen 135), else the gray cross ("Not found", change
    /// 174; "No Premium", screen 135).
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
        // Card AX, screen 135: the cable stays plugged in. Its light flows once when "Check
        // again" is pressed, and again when Premium is found.
        case .premium where state.premiumFound:
            return (screen: PreviewScreen.mark(ok: true, word: "Premium"), cable: SyncCable.Plug.once(from: state.premiumAt))
        case .premium:
            let cable = state.premiumAt > 0 ? SyncCable.Plug.once(from: state.premiumAt) : SyncCable.Plug.on
            return (screen: PreviewScreen.mark(ok: false, word: "No Premium"), cable: cable)
        case .yourMusic where state.top.error: return nil  // the error message fills the screen
        case .yourMusic where state.top.loading:
            let names = state.namesAt > 0 ? state.firstReadNames : []
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
            mark(ok: false, word: Self.failWord(screen)).opacity(shown == 1 ? 1 : 0)
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
        min(max((t - AppState.nameStart - AppState.nameGap * Double(i)) / AppState.nameFade, 0), 1)
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

    /// The word of the gray cross: "Not found" or "No Premium".
    static func failWord(_ screen: PreviewScreen) -> String {
        if case .mark(false, let word) = screen { return word }
        return "Not found"
    }

    /// The word of the green check: "Logged in", "Linked" or "Premium".
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
        /// Plugged in, and the light travels up once, in `onceTime`, from time `from` (screen 135).
        case once(from: Double)
    }

    nonisolated static let onceTime = 1.0

    let plug: Plug
    @Environment(\.animationTime) private var fixedTime

    nonisolated static let lightRound = 2.4

    /// The light's distance along the cable from its far end, and its opacity, at time `t`.
    nonisolated static func light(at t: Double) -> (distance: Double, opacity: Double) {
        lightPart(max(0, t).truncatingRemainder(dividingBy: lightRound) / lightRound)
    }

    /// The single light of `.once`, `t` seconds after it starts: gone before and after.
    nonisolated static func lightOnce(at t: Double) -> (distance: Double, opacity: Double) {
        guard t >= 0, t <= onceTime else { return (0, 0) }
        return lightPart(t / onceTime)
    }

    /// The light at part `u` (0 to 1) of its way: it fades in, travels and fades out.
    private nonisolated static func lightPart(_ u: Double) -> (distance: Double, opacity: Double) {
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
            if plug == .light { flow { Self.light(at: $0) } }
            if case .once(let from) = plug { flow { Self.lightOnce(at: $0 - from) } }
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
    private func flow(_ at: @escaping (Double) -> (distance: Double, opacity: Double)) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: fixedTime != nil)) { context in
            let light = at(fixedTime ?? context.date.timeIntervalSinceReferenceDate)
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
/// the selection blue. Until the library knows the total, a part of the blue moves to and fro.
/// Under it, three counts (change 188): "107 playlists", "84 albums", "455 liked songs".
struct SetupProgress: View {
    let done: Int, total: Int
    /// nil until the playlist list came.
    var playlists: Int?
    var albums = 0
    @Environment(\.animationTime) private var fixedTime

    /// The three count lines, as a number and its words. A line is nil until its number is
    /// known: the playlists when the list came, the albums and songs when the read has a total.
    nonisolated static func counts(done: Int, total: Int, playlists: Int?, albums: Int) -> [(number: String, words: String)?] {
        func line(_ n: Int?, _ one: String, _ many: String) -> (number: String, words: String)? {
            n.map { ($0.formatted(), $0 == 1 ? one : many) }
        }
        let read = total > 0
        return [
            line(playlists, "playlist", "playlists"),
            line(read ? albums : nil, "album", "albums"),
            line(read ? min(done, total) : nil, "liked song", "liked songs"),
        ]
    }

    /// The moving part's left edge, as a part of the free track, at time `t`: 0 to 1 and back in 2.4 s, eased.
    static func position(at t: Double) -> Double {
        let u = max(0, t).truncatingRemainder(dividingBy: 2.4) / 2.4
        return u < 0.5 ? Hello.ease(u * 2) : 1 - Hello.ease((u - 0.5) * 2)
    }

    var body: some View {
        let counts = Self.counts(done: done, total: total, playlists: playlists, albums: albums)
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
            // The numbers right-aligned in one column, the words after them. A line not known
            // yet keeps its place, so the lines never jump. 11 pt with a 1.35 line height.
            Grid(alignment: .leading, horizontalSpacing: 3, verticalSpacing: 11 * 0.35) {
                ForEach(counts.indices, id: \.self) { i in
                    GridRow {
                        Text(counts[i]?.number ?? "0").gridColumnAlignment(.trailing)
                        Text(counts[i]?.words ?? "")
                    }
                    .opacity(counts[i] == nil ? 0 : 1)
                }
            }
            .font(.helvetica(11))
            .monospacedDigit()
            .foregroundStyle(Color(hex: 0x5d6772))
            .fixedSize()
        }
        .padding(.horizontal, 9)
        .accessibilityElement()
        .accessibilityLabel(Self.label(counts))
    }

    /// "107 playlists, 84 albums, 455 liked songs", or "Getting your music" before any count.
    nonisolated static func label(_ counts: [(number: String, words: String)?]) -> String {
        let known = counts.compactMap { $0.map { "\($0.number) \($0.words)" } }
        return known.isEmpty ? "Getting your music" : known.joined(separator: ", ")
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
