import AppKit
import ClasifyCore
import SwiftUI

/// The Pocket colors, from the mockup's inline styles.
enum Pocket {
    /// The LCD in points: the iPod's 4:3 shape, a 19 point title bar over 9 rows of 22.9.
    static let screenWidth: CGFloat = 300, screenHeight: CGFloat = 225
    /// A half screen's list pane: half the screen, as on the iPod. The covers take the rest.
    static let paneWidth: CGFloat = 150
    /// The title bar: 19 points with its line, as in the photo.
    static let headerHeight: CGFloat = 18
    /// The bar for the playing track: 22.9 points with its line, like a row.
    static let barHeight: CGFloat = 21.9
    /// The list under the title bar.
    static let listHeight: CGFloat = 206
    /// Where the text's baseline falls in the bar note's 11 point frame. The note's ink spans y 1
    /// to 15.8 of its 16 unit view box, so its middle is 5.77 points down; the baseline is half
    /// an x-height of the 10.5 point bold font below that.
    static let barNoteBaseline: CGFloat = {
        let xHeight = NSFont(name: "HelveticaNeue-Bold", size: 10.5)?.xHeight ?? 5.5
        return (1 + 15.79) / 2 / 16 * 11 + xHeight / 2
    }()
    /// The dark bezel around the screen of the Silver body (card BH, change 239).
    static let bezel = Color(hex: 0x2a2c2e)
    /// The title bar's play and pause marks: glossy blue with a thin dark blue edge.
    static var markGloss: LinearGradient { .vertical(Color(hex: 0x9fd0f5), Color(hex: 0x3f8fd8)) }
    static let markEdge = Color(hex: 0x3a7ab8)
    static let ink = Color(hex: 0x1b1f24)
    static let gray = Color(hex: 0x3d454e)
    static let line = Color(hex: 0x8f99a3)
    /// A two-line row's detail line (Round 10 card AI): Helvetica Neue Medium 11, light gray, or
    /// pale blue on the selected row.
    static let detailFont = Font.helvetica(11, weight: .medium)
    static let detail = Color(hex: 0x9ba3ad)
    static let detailSelected = Color(hex: 0xe3efff)
    /// The faint 1 point line between two-line rows (card AI).
    static let divider = Color.black.opacity(0.02)
    /// The LCD's glass, behind the lists.
    static var glass: LinearGradient { .vertical(Color(hex: 0xf4f8fb), Color(hex: 0xd6e2ec)) }
    static var selection: LinearGradient { .vertical(Color(hex: 0x5aa3f0), Color(hex: 0x1f6fd1)) }
    /// The photo's soft blue: the fill of the progress and volume bars, the scrub diamond and the slider knob.
    static var soft: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(hex: 0x8ea6d6), location: 0), .init(color: Color(hex: 0x6993c5), location: 0.55),
                .init(color: Color(hex: 0x7eb6e7), location: 0.85), .init(color: Color(hex: 0x82adcd), location: 1),
            ],
            startPoint: .top, endPoint: .bottom)
    }
    /// The empty part of the four Now Playing bars: white, with no border.
    static var barTrack: LinearGradient { .vertical(.white, Color(hex: 0xeef2f5)) }
    /// The four Now Playing bars are 13.2 points tall.
    static let softBarHeight: CGFloat = 13.2
    static let offline = Color(hex: 0xa3261c)
    /// The title bar's play and pause mark.
    static let blue = Color(hex: 0x1f6fd1)
}

/// The LCD: the header, then a list, a message or Now Playing, then the bar and the toast.
struct PocketScreen: View {
    let state: AppState
    var input: @MainActor (Action) -> Void = { _ in }
    /// Draws only the screen's parts, with no glass, bezel or toast: the main menu's doors
    /// over Cover Flow (`doorsMenu`).
    var doorsOnly = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// SPIKE (CLA-101): BL only with the hidden switch.
    @Environment(\.pocketLook) private var look
    /// The last `navSeq` whose cover flight to Now Playing has landed.
    @State private var landedSeq = -1
    /// The last `wholeSeq` whose doors have opened.
    @State private var openedSeq = -1

    private var top: Frame { state.top }

    /// While the cover flies to Now Playing, the title bar still says "Cover Flow". It changes
    /// when the cover lands, 0.4 s after Center (card AH).
    private var title: String {
        let flying = state.navMove == .fly && state.navForward && state.nowOverPanel
        guard flying, !reduceMotion, landedSeq != state.navSeq else { return Labels.title(top.screen, in: state) }
        return Labels.title(.coverFlow, in: state)
    }

    /// The mockup's push and pop over 0.22 s. The new screen slides in from the right when it
    /// opens and from the left on a way back, and pushes the old screen out to the other side.
    /// The pane's width moves in the same animation. No slide with Reduce Motion.
    private var slide: AnyTransition {
        if reduceMotion { return .identity }
        return .asymmetric(insertion: .modifier(active: Push(side: 1), identity: Push(side: 0)),
                           removal: .modifier(active: Push(side: -1), identity: Push(side: 0)))
    }

    static let slideAnimation = Animation.timingCurve(0.2, 0.7, 0.3, 1, duration: 0.22)

    /// A whole-screen move: a push, or the doors between the main menu and Cover Flow.
    private var whole: AnyTransition {
        if reduceMotion { return .identity }
        return .asymmetric(insertion: .modifier(active: ScreenMove(side: 1), identity: ScreenMove(side: 0)),
                           removal: .modifier(active: ScreenMove(side: -1), identity: ScreenMove(side: 0)))
    }

    /// Cover Flow's cover turns over into the song panel and back: 0.35 s, ease-in-out (card AF).
    static let flipAnimation = Animation.easeInOut(duration: 0.35)

    /// The slide's curve, the turn of the song panel, or for the doors a linear time that
    /// `DoorsStage` shapes.
    private var moveAnimation: Animation? {
        if reduceMotion { return nil }
        switch state.navMove {
        case .doors: return .linear(duration: state.navForward ? DoorsStage.openTime : DoorsStage.closeTime)
        case .flip: return Self.flipAnimation
        case .fly: return PocketCoverFlow.flyAnimation
        case .push: return Self.slideAnimation
        }
    }

    /// The content's identity: a new one slides in. Cover Flow and its song panel are one
    /// view, so the cover turns over in place, and so is Now Playing when the cover flies there
    /// (card AH). A negative ID never meets a `navSeq`.
    private var contentID: Int {
        guard state.coverFlowFrame != nil || state.nowOverPanel,
            let i = state.stack.lastIndex(where: { $0.screen == .coverFlow })
        else {
            return state.navSeq
        }
        return -1 - i
    }

    /// Shows at once, and on removal stays until the slide ends.
    private var stay: AnyTransition {
        if reduceMotion { return .identity }
        return .asymmetric(insertion: .identity, removal: .opacity.animation(.linear(duration: 0).delay(0.22)))
    }

    /// The screen's parts: the title bar, the content and the bar, and on a half screen (the
    /// main menu and Playlists) the covers beside the pane.
    @ViewBuilder private var parts: some View {
        // A half screen (the main menu, Playlists) is a 150 point pane (half the screen) with a shadow, over
        // covers on the right. The panel stays between them, so it does not start again.
        // With Album Art set to Now Playing or Off, they are full-width lists and load no covers.
        // The setup screens are split the same way, with the small device on the right (cards AW, AX).
        let preview = setupPreview
        let split = state.isHalf(top.screen) || preview != nil
        let width: CGFloat = split ? Pocket.paneWidth : Pocket.screenWidth
        ZStack(alignment: .leading) {
            if split {
                // On the way out, the covers stay until the pane has widened over them.
                Group {
                    if let preview {
                        SetupPreview(color: state.shownColor, screen: preview.screen, cable: preview.cable)
                            .frame(width: Pocket.screenWidth - Pocket.paneWidth)
                    } else {
                        MainArtPanel(tracks: state.mainArt)
                    }
                }
                .padding(.leading, Pocket.paneWidth).transition(stay)
                .modifier(DoorHalf(side: 1))
            }
            VStack(spacing: 0) {
                if top.screen != .hello {  // Hello fills the whole screen, with no title bar
                    VStack(spacing: 0) {
                        header
                        Pocket.line.frame(height: 1)
                    }
                    .modifier(DoorsHeader())
                }
                ZStack(alignment: .leading) {
                    // Each screen keeps its own width while it slides, so its text does not reflow.
                    content.frame(width: width).frame(maxHeight: .infinity)
                        .id(contentID)
                        .transition(slide)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
                .environment(\.navForward, state.navForward)
                if state.showsBar, let now = Labels.now(in: state) {
                    Pocket.line.frame(height: 1)
                    NowBar(now: now, t: state.t)
                }
            }
            .frame(width: width)
            .background {
                if split {
                    // Like the covers, the pane's glass stays while it widens over them.
                    Pocket.glass.shadow(color: .black.opacity(0.4), radius: 5, x: 4, y: 0)
                        .transition(stay)
                }
            }
            .modifier(DoorHalf(side: -1))
        }
    }

    /// The main menu as it was under Cover Flow, while its doors open over Cover Flow. A
    /// removed screen keeps the transition and the environment of its last update, so the old
    /// main menu cannot open its own doors: this new copy of it does (CLA-63). MENU closes the
    /// doors with the main menu's insertion, as before.
    private var doorsMenu: AppState? {
        guard !reduceMotion, state.navMove == .doors, state.navForward, top.screen == .coverFlow,
            openedSeq != state.wholeSeq, state.stack.count >= 2
        else { return nil }
        var menu = state
        menu.stack.removeLast()
        return menu
    }

    /// The doors open as the main menu's removal did: from closed (`side` 0) to open (-1).
    private static var doorsOpen: AnyTransition {
        .asymmetric(insertion: .modifier(active: ScreenMove(side: 0), identity: ScreenMove(side: -1)), removal: .identity)
    }

    @ViewBuilder var body: some View {
        if doorsOnly {
            parts.frame(width: Pocket.screenWidth, height: Pocket.screenHeight, alignment: .leading)
        } else {
            device
        }
    }

    private var device: some View {
        ZStack {
            // Between a half screen and a full one, and to and from Hello, the whole screen moves,
            // with its title bar, the pane and the covers. Other moves slide only the content (`parts`).
            // The newer screen is on top. In the doors move, the main menu's doors open over Cover
            // Flow (`doorsMenu`) and close over it. Cover Flow has its own glass, so the old main
            // menu under it does not show.
            parts.frame(width: Pocket.screenWidth, height: Pocket.screenHeight, alignment: .leading)
                .background { if top.screen == .coverFlow { Pocket.glass } }
                .id(state.wholeSeq)
                .transition(whole)
                .zIndex(Double(state.wholeSeq))
            if let menu = doorsMenu {
                PocketScreen(state: menu, doorsOnly: true)
                    .id(state.wholeSeq)
                    .transition(Self.doorsOpen)
                    .zIndex(Double(state.wholeSeq) + 0.5)
                    .accessibilityHidden(true)
            }
        }
        .clipped()
        .environment(\.navForward, state.navForward)
        .environment(\.navDoors, state.navMove == .doors)
        .task(id: state.navSeq) {
            let seq = state.navSeq
            try? await Task.sleep(for: .seconds(PocketCoverFlow.flyTime))
            if !Task.isCancelled { landedSeq = seq }
        }
        .task(id: state.wholeSeq) {
            // The open doors leave when the move ends.
            let seq = state.wholeSeq
            try? await Task.sleep(for: .seconds(DoorsStage.openTime + 0.05))
            if !Task.isCancelled { openedSeq = seq }
        }
        .animation(moveAnimation, value: state.navSeq)
        .overlay(alignment: .bottom) {
            if !state.toast.isEmpty {
                Self.toast(state.toast, bottom: top.screen == .now ? 44 : 16)
            } else if state.hintTip, let hint = state.hint {
                HintTip(hint: hint, from: state.hintTipAt)
            }
        }
        .frame(width: Pocket.screenWidth, height: Pocket.screenHeight)
        .background(Pocket.glass)  // the photo's glass has no inner shadow
        .clipShape(RoundedRectangle(cornerRadius: 2))
        // The bezel: 6.6 points at the sides and the top, 7.8 at the bottom, with a thin white
        // highlight under it.
        .padding(EdgeInsets(top: 6.6, leading: 6.6, bottom: 7.8, trailing: 6.6))
        .background {
            // Near black on the black device (round 8, card Z), with a fainter highlight. BL uses
            // its own bezel for both colors.
            RoundedRectangle(cornerRadius: 7.8)
                .fill(look == .bl ? Color(hex: BL.bezel) : state.shownColor == .black ? Color(hex: 0x050505) : Pocket.bezel)
                .shadow(color: .white.opacity(state.shownColor == .black ? 0.18 : 0.7), radius: 0, y: 1)
        }
        .foregroundStyle(Pocket.ink)
        // .contain, not .combine: the shuffle and repeat buttons on Now Playing must stay
        // separate VoiceOver controls.
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        // The title on the left; OFF and the blue play or pause mark on the right.
        HStack(spacing: 6) {
            FadeLine(Text(title))
                .frame(maxWidth: .infinity, alignment: .leading)
            if state.offline {
                Text("OFF").font(.helvetica(9, bold: true)).foregroundStyle(Pocket.offline)
            }
            switch Labels.playMark(in: state) {
            case .playing: mark(.play, label: "Playing")
            case .paused: mark(.pause, label: "Paused")
            case nil: EmptyView()
            }
            // The battery, 7 points after the play mark. A Mac with no battery shows none, and
            // the setup screens show none (Round 13).
            if setupPreview == nil, let battery = Labels.battery(in: state) {
                BatteryView(battery: battery).padding(.leading, 1)
            }
        }
        .font(.helvetica(11.7, bold: true))
        .padding(EdgeInsets(top: 1, leading: 9, bottom: 0, trailing: 8))
        .frame(height: Pocket.headerHeight)  // 19 with the line under it, as in the mockup
        .background(LinearGradient.vertical(.white, Color(hex: 0xc9d2db)))
    }

    /// A 10 x 11 play or pause mark, glossy blue with a dark blue edge.
    private func mark(_ icon: Icon, label: String) -> some View {
        let shape = icon.fill.applying(CGAffineTransform(scaleX: 10 / icon.viewBox.width, y: 11 / icon.viewBox.height))
        return ZStack {
            shape.fill(Pocket.markGloss)
            shape.stroke(Pocket.markEdge, lineWidth: 0.6)
        }
        .frame(width: 10, height: 11, alignment: .topLeading)
        .accessibilityElement()
        .accessibilityLabel(label)
    }

    /// The small device of a setup screen. Nil on other screens, and while a stored login is
    /// restored: that shows "Signing in…" on the whole screen.
    private var setupPreview: (screen: PreviewScreen, cable: SyncCable.Plug?)? {
        if top.screen == .login && state.restoring { return nil }
        return PreviewScreen.of(top.screen, in: state)
    }

    /// The message that shows in place of the content. The song panel shows its own, inside
    /// the panel, so its cover still turns over while the album loads (CLA-46).
    private var message: Labels.Message? {
        if case .albumPanel = top.screen { return nil }
        return Labels.message(for: top, in: state)
    }

    @ViewBuilder private var content: some View {
        if let message {
            MessageView(message: message)
        } else if state.coverFlowFrame != nil || state.nowOverPanel {
            // Cover Flow, its song panel over it, and Now Playing when the cover flew there.
            PocketCoverFlow(state: state, input: input, landed: landedSeq == state.navSeq)
        } else if top.screen == .now {
            PocketNowPlaying(state: state, input: input)
        } else if top.screen == .about {
            PocketAbout(state: state)
        } else if case .license(let i) = top.screen {
            PocketLicense(state: state, index: i)
        } else if top.screen == .hello {
            // A click on the screen begins setup too (change 167).
            PocketHello(helloAt: state.helloAt).contentShape(Rectangle()).onTapGesture { input(.select) }
        } else {
            PocketList(state: state)
        }
    }

    /// The toast (Round 15 card BD, changes 185 and 186): a dark rounded box that fits its
    /// text, at most 272 points wide, centered `bottom` points above the screen's bottom: 16,
    /// and 44 on Now Playing, over the time bar. The text wraps, with no "…". A first-time
    /// hint's tip has the same look (card BA, change 195).
    nonisolated static func toast(_ text: String, bottom: CGFloat) -> some View {
        toastBox(bottom: bottom) {
            Text(text).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The toast's box around any content, such as a tip with a wheel mark in its words.
    nonisolated static func toastBox<Content: View>(bottom: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        content()
            .font(.helvetica(11, weight: .medium))
            .foregroundStyle(.white)
            .padding(.vertical, 6)
            .padding(.horizontal, 13)
            .background {
                // #1b1f24 at 60% over a blur of the screen behind it, with 6 point corners (card
                // BD, change 194). The mockup's blur is 10 points. SwiftUI has no material
                // with a set blur radius, so this keeps `.ultraThinMaterial`.
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Color(hex: 0x1b1f24, opacity: 0.6)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            }
            .frame(maxWidth: 272)  // the box fits its text inside this
            .padding(.bottom, bottom)
    }
}

/// A first-time hint's tip (card BA, change 195), in the toast look, 16 points above the
/// screen's bottom. On Now Playing it sits 15 points up, in the time bar's place, and the
/// play/pause or next mark shows in white as on the wheel. It fades in over 0.4 s from
/// `from`, and out over the last 0.4 s of its 10 s. When the action is done, it goes at once.
/// A tour tip (card BA.1) waits for its press, so it does not fade out. With Reduce Motion,
/// nothing fades.
struct HintTip: View {
    let hint: Hint
    let from: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.animationTime) private var fixedTime

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || fixedTime != nil)) { context in
            let t = (fixedTime ?? context.date.timeIntervalSinceReferenceDate) - from
            let words = Labels.hintTip(hint)
            PocketScreen.toastBox(bottom: hint == .menu || hint == .tourPlay ? 16 : 15) {
                HStack(spacing: 4) {
                    Text(words.lead)
                    if let mark = words.mark {
                        // The wheel's marks at 7 points tall.
                        IconView(mark, width: mark == .playPause ? 17.5 : 13.3, height: 7)
                        Text(words.rest)
                    }
                }
            }
            .opacity(reduceMotion ? 1 : Self.opacity(at: t, ends: !hint.isTour))
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Labels.hintTip(hint).spoken)
    }

    /// The tip's opacity `t` seconds after it starts.
    static func opacity(at t: Double, ends: Bool = true) -> Double {
        max(0, min(1, t / 0.4, ends ? (AppState.hintTipTime - t) / 0.4 : 1))
    }
}

/// The rows of a list screen, with the selection and a scroll bar for long lists.
struct PocketList: View {
    let state: AppState

    var body: some View {
        let top = state.top
        let rows = state.rows(for: top)
        let first = top.off  // the reducer keeps the selection inside state.shownRows
        let shown = Array(rows.indices.dropFirst(first).prefix(state.shownRows))
        let scrolls = rows.count > state.shownRows
        // The rows fill the list exactly: 206 points under the title bar, 183.1 over the bar
        // (card AK). Menus show 9 rows of 22.9, or 8 over the bar. Song rows have two lines, so
        // 5 of them fit: 36.6 points over the bar, 41.2 with no bar.
        let height = (state.showsBar ? Pocket.listHeight - Pocket.barHeight - 1 : Pocket.listHeight)
            / CGFloat(state.shownRows)
        let words = Labels.setupWords(for: top, in: state)
        VStack(spacing: 0) {
            if let words { SetupMessage(words: words) }  // card AX: the rows start under it
            if top.screen == .yourMusic && top.loading {  // card AY, at the row place
                SetupProgress(done: state.readDone, total: state.readTotal,
                              playlists: state.namesAt > 0 ? state.playlistCount : nil, albums: state.readAlbums,
                              namesFrom: state.namesAt > 0 ? state.namesAt : nil, names: state.firstReadNames.count,
                              waitsForNames: state.refreshing.contains(AppState.readKey(.playlists)))
            }
            ForEach(shown, id: \.self) { index in
                PocketRow(text: Labels.row(rows[index], on: top.screen, in: state),
                          selected: index == top.sel, scrolls: scrolls, height: height)
            }
            if top.screen == .color { ColorPickWords(state: state).layoutPriority(1) }  // its line sits at the bottom
            Spacer(minLength: 0)
            if let footnote = words?.footnote, !footnote.isEmpty {  // at the bottom, as on the color pick
                Text(footnote)
                    .font(.helvetica(10))
                    .foregroundStyle(Color(hex: 0x5d6772))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EdgeInsets(top: 0, leading: 9, bottom: 10, trailing: 6))
            }
        }
        .overlay(alignment: .topTrailing) {
            if scrolls { scrollBar(first: first, count: rows.count) }
        }
    }

    /// The shortest thumb, so a long list does not shrink it to a thin line.
    static let minThumb: CGFloat = 12

    /// The thumb's length and its offset from the top of a track `height` points long. The
    /// length shows the part of the list on screen, but never under `minThumb`. At the last
    /// row, the thumb's bottom touches the track's bottom.
    static func thumb(height: CGFloat, shown: Int, count: Int, first: Int) -> (length: CGFloat, offset: CGFloat) {
        let length = min(height, max(minThumb, height * CGFloat(shown) / CGFloat(max(count, 1))))
        let last = max(1, count - shown)
        return (length, (height - length) * CGFloat(min(first, last)) / CGFloat(last))
    }

    private func scrollBar(first: Int, count: Int) -> some View {
        GeometryReader { geo in
            let thumb = Self.thumb(height: geo.size.height, shown: state.shownRows, count: count, first: first)
            Capsule().fill(Color(hex: 0x5d6772))
                .frame(height: thumb.length)
                .offset(y: thumb.offset)
        }
        // A 3 point thumb with round ends and no track, 1.5 points from the right edge.
        .frame(width: 3)
        .padding(.vertical, 2)
        .padding(.trailing, 1.5)
        // It shows for 1.5 s after a wheel step or a screen change, then fades out over 0.4 s.
        .opacity(state.scrollUntil > 0 ? 1 : 0)
        .animation(.easeInOut(duration: 0.4), value: state.scrollUntil > 0)
        .accessibilityHidden(true)
    }
}

struct PocketRow: View {
    let text: Labels.RowText
    let selected: Bool
    /// A scroll bar shows, so the row leaves room for it.
    let scrolls: Bool
    var height: CGFloat = 22.9

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                let label = Text(text.label).font(.helvetica(13, bold: true))
                if selected {
                    // The label as it is when it fits the room left by the row's other parts, else the marquee.
                    ViewThatFits(in: .horizontal) {
                        label.lineLimit(1)
                        Marquee(text: label, loop: Labels.marqueeLoop(text.label))
                    }
                } else {
                    FadeLine(label)
                }
                if !text.detail.isEmpty {
                    FadeLine(Text(text.detail))
                        .font(Pocket.detailFont)
                        .foregroundStyle(selected ? Pocket.detailSelected : Pocket.detail)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                if !text.value.isEmpty {
                    // A setting's value: bold and blue, or white on the selected row.
                    Text(text.value).font(.helvetica(12, bold: true)).foregroundStyle(selected ? Color.white : Pocket.blue)
                }
                if text.playing {
                    // The photo's soft blue, or white on the selected row.
                    IconView(.speakerLoud, width: 13, height: 11, label: "Now playing")
                        .foregroundStyle(selected ? Color.white : Color(hex: 0x6993c5))
                }
                // Only the selected row shows its chevron, in white.
                if text.opens && selected { IconView(.chevron, width: 8, height: 12) }
            }
            .fixedSize()
        }
        .padding(.leading, 9)
        .padding(.trailing, scrolls ? 14 : 10)
        .frame(height: height)
        .foregroundStyle(selected ? Color.white : Pocket.ink)
        .background { if selected { Pocket.selection } }
        .overlay {
            // Two-line rows have a faint line between them, except under the selection.
            if !text.detail.isEmpty && !selected { RowDivider() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The 1 point line at the bottom of a two-line row. Rows are 36.6 or 41.2 points tall, so a row's
/// bottom is often between two display pixels. The line moves up to the pixel above it, so every
/// line is equally sharp and thick.
struct RowDivider: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { g in
            let scale = max(displayScale, 1)
            let bottom = g.frame(in: .global).maxY
            let snapped = (bottom * scale).rounded(.down) / scale
            Pocket.divider
                .frame(width: g.size.width, height: 1)
                .offset(y: g.size.height - 1 - (bottom - snapped))
        }
    }
}

/// The mockup's `mq2` marquee: two copies of the label, each with 28 points after it.
/// They hold still for the first 18 % of a loop, then move left by one copy, and the loop starts again.
/// A new selection makes a new view, so it starts from the left. With Reduce Motion it stays still.
struct Marquee: View {
    let text: Text
    let loop: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.animationTime) private var fixedTime
    @State private var start = Date.timeIntervalSinceReferenceDate

    /// How far the copies have moved at time `t`, as a part of one copy's width.
    static func shift(at t: Double, loop: Double) -> Double {
        let p = max(0, t).truncatingRemainder(dividingBy: loop) / loop
        return p < 0.18 ? 0 : (p - 0.18) / 0.82
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || fixedTime != nil)) { context in
            let t = reduceMotion ? 0 : fixedTime ?? context.date.timeIntervalSinceReferenceDate - start
            Self.copies(text, shift: Self.shift(at: t, loop: loop))
        }
        .clipped()
    }

    /// The two copies, moved left by `shift` of one copy's width, in a frame as wide as its room.
    static func copies(_ text: Text, shift: Double) -> some View {
        HStack(spacing: 0) {
            text.padding(.trailing, 28)
            text.padding(.trailing, 28).accessibilityHidden(true)
        }
        .fixedSize()
        .visualEffect { content, geo in content.offset(x: -shift * geo.size.width / 2) }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)  // minWidth 0: else the frame is as wide as both copies
    }
}

/// A screen with no list: a spinner, a title and a line of help.
struct MessageView: View {
    let message: Labels.Message

    var body: some View {
        VStack(spacing: 8) {
            if message.spinner { Spinner() }
            Text(message.title).font(.helvetica(14, bold: true))
            if !message.body.isEmpty {
                Text(message.body)
                    .font(.helvetica(11))
                    .lineSpacing(2)
                    .foregroundStyle(Pocket.gray)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 18)
    }
}

/// The mockup's spinner: a gray ring with a dark top quarter that turns every 0.8 s.
struct Spinner: View {
    var body: some View {
        TimelineView(.animation) { context in
            let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.8) / 0.8
            ZStack {
                Circle().stroke(Color(hex: 0x9aa6b2), lineWidth: 2)
                Circle().trim(from: 0.625, to: 0.875).stroke(Pocket.ink, lineWidth: 2)
            }
            .rotationEffect(.degrees(turn * 360))
        }
        .frame(width: 20, height: 20)  // with the 2 point ring: 22 points, as CSS content-box gives
        .padding(1)
        .accessibilityHidden(true)
    }
}
