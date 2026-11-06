import ClasifyCore
import SwiftUI

/// The Pocket colors, from the mockup's inline styles.
enum Pocket {
    /// The LCD in points: the iPod's 4:3 shape at the mockup's height.
    static let screenWidth: CGFloat = 266, screenHeight: CGFloat = 200
    /// A half screen's list pane: half the screen, as on the iPod. The covers take the rest.
    static let paneWidth: CGFloat = 133
    static let ink = Color(hex: 0x1b1f24)
    static let gray = Color(hex: 0x3d454e)
    static let line = Color(hex: 0x8f99a3)
    static let frame = Color(hex: 0x4b5056)
    /// The LCD's glass, behind the lists.
    static var glass: LinearGradient { .vertical(Color(hex: 0xf4f8fb), Color(hex: 0xd6e2ec)) }
    static var selection: LinearGradient { .vertical(Color(hex: 0x5aa3f0), Color(hex: 0x1f6fd1)) }
    /// The glossy blue of the progress fill and the slider knobs.
    static var gloss: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(hex: 0x9fd0ff), location: 0), .init(color: Color(hex: 0x3d8ae8), location: 0.55),
                .init(color: Color(hex: 0x2a73d4), location: 1),
            ],
            startPoint: .top, endPoint: .bottom)
    }
    static let offline = Color(hex: 0xa3261c)
    /// The title bar's play and pause mark.
    static let blue = Color(hex: 0x1f6fd1)
}

/// The LCD: the header, then a list, a message or Now Playing, then the bar and the toast.
struct PocketScreen: View {
    let state: AppState
    var input: @MainActor (Action) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var top: Frame { state.top }

    /// The mockup's push and pop over 0.22 s. The new screen slides in from the right when it
    /// opens and from the left on a way back, and pushes the old screen out to the other side.
    /// The pane's width moves in the same animation. No slide with Reduce Motion.
    private var slide: AnyTransition {
        if reduceMotion { return .identity }
        return .asymmetric(insertion: .modifier(active: Push(side: 1), identity: Push(side: 0)),
                           removal: .modifier(active: Push(side: -1), identity: Push(side: 0)))
    }

    static let slideAnimation = Animation.timingCurve(0.2, 0.7, 0.3, 1, duration: 0.22)

    /// Shows at once, and on removal stays until the slide ends.
    private var stay: AnyTransition {
        if reduceMotion { return .identity }
        return .asymmetric(insertion: .identity, removal: .opacity.animation(.linear(duration: 0).delay(0.22)))
    }

    /// The screen's parts: the title bar, the content and the bar, and on a half screen (the
    /// main menu and Playlists) the covers beside the pane.
    @ViewBuilder private var parts: some View {
        // A half screen (the main menu, Playlists) is a 133 point pane (half the screen) with a shadow, over
        // covers on the right. The panel stays between them, so it does not start again.
        // With Album Art set to Now Playing or Off, they are full-width lists and load no covers.
        let split = state.isHalf(top.screen)
        let width: CGFloat = split ? Pocket.paneWidth : Pocket.screenWidth
        ZStack(alignment: .leading) {
            if split {
                // On the way out, the covers stay until the pane has widened over them.
                MainArtPanel(tracks: state.mainArt).padding(.leading, Pocket.paneWidth).transition(stay)
            }
            VStack(spacing: 0) {
                header
                Pocket.line.frame(height: 1)
                ZStack(alignment: .leading) {
                    // Each screen keeps its own width while it slides, so its text does not reflow.
                    content.frame(width: width).frame(maxHeight: .infinity)
                        .id(state.navSeq)
                        .transition(slide)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
                .environment(\.navForward, state.navForward)
                if state.showsBar, let now = Labels.now(in: state) {
                    Pocket.line.frame(height: 1)
                    bar(now)
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
        }
    }

    var body: some View {
        ZStack {
            // Between a half screen and a full one, the whole screen moves, with its title bar,
            // the pane and the covers. Other moves slide only the content (`parts`).
            parts.frame(width: Pocket.screenWidth, height: Pocket.screenHeight, alignment: .leading)
                .id(state.wholeSeq)
                .transition(slide)
        }
        .clipped()
        .environment(\.navForward, state.navForward)
        .animation(reduceMotion ? nil : Self.slideAnimation, value: state.navSeq)
        .overlay(alignment: .bottom) {
            if !state.toast.isEmpty { toast }
        }
        .frame(width: Pocket.screenWidth, height: Pocket.screenHeight)
        .background {
            // The glass and its inset shadow. As in the mockup, the header, the selected row,
            // the bar and the scroll bar paint over the shadow.
            Pocket.glass
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.black.opacity(0.25), lineWidth: 6)
                        .blur(radius: 3)
                        .offset(y: 2)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .padding(2)
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Pocket.frame, lineWidth: 2) }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .foregroundStyle(Pocket.ink)
        // .contain, not .combine: the shuffle and repeat buttons on Now Playing must stay
        // separate VoiceOver controls.
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        // The title on the left; OFF and the blue play or pause mark on the right.
        HStack(spacing: 6) {
            Text(Labels.title(top.screen, in: state))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if state.offline {
                Text("OFF").font(.helvetica(9, bold: true)).foregroundStyle(Pocket.offline)
            }
            switch Labels.playMark(in: state) {
            case .playing: IconView(.play, width: 9, height: 10, label: "Playing").foregroundStyle(Pocket.blue)
            case .paused: IconView(.pause, width: 9, height: 10, label: "Paused").foregroundStyle(Pocket.blue)
            case nil: EmptyView()
            }
        }
        .font(.helvetica(11, bold: true))
        .padding(.horizontal, 8)
        .frame(height: 19)  // 20 with the line under it, as in the mockup
        .background(LinearGradient.vertical(.white, Color(hex: 0xc9d2db)))
    }

    @ViewBuilder private var content: some View {
        if let message = Labels.message(for: top, in: state) {
            MessageView(message: message)
        } else if top.screen == .now {
            PocketNowPlaying(state: state, input: input)
        } else {
            PocketList(state: state)
        }
    }

    private func bar(_ now: Labels.NowText) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                // A music note, the same when paused: play and pause show only in the title bar.
                IconView(.notes, width: 10, height: 10).accessibilityHidden(true)
                Text("\(now.title)\(now.artist.isEmpty ? "" : " — \(now.artist)")").lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Labels.time(state.t)).monospacedDigit()
        }
        .font(.helvetica(10))
        .padding(.horizontal, 8)
        .frame(height: 19)  // 20 with the line over it
        .background(Color(hex: 0xe8eef3))
    }

    private var toast: some View {
        Text(state.toast)
            .font(.helvetica(11))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)  // 26 points tall, as in the mockup
            .padding(.horizontal, 8)
            .background(Color(hex: 0x1b1f24, opacity: 0.88), in: RoundedRectangle(cornerRadius: 4))
            .padding(.horizontal, 14)
            .padding(.bottom, 26)
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
        // The rows fill the list exactly: 180 points under the title bar, 160 over the bar.
        // Song rows have two lines, so only state.shownRows of them fit: 36 or 40 points each.
        let height = (state.showsBar ? 160 : 180) / CGFloat(state.shownRows)
        VStack(spacing: 0) {
            ForEach(shown, id: \.self) { index in
                PocketRow(text: Labels.row(rows[index], on: top.screen, in: state),
                          selected: index == top.sel, scrolls: scrolls, height: height)
            }
            if top.screen == .login {
                Text("Opens your browser to sign in. Playlists are read-only.")
                    .font(.helvetica(11))
                    .lineSpacing(2)
                    .foregroundStyle(Pocket.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding([.horizontal, .top], 10)
            }
            Spacer(minLength: 0)
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
        .frame(width: 5)
        .background(Capsule().fill(Color(hex: 0xc3ccd5)))
        .padding(.vertical, 2)
        .padding(.trailing, 2)
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
    var height: CGFloat = 22.5

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
                    label.lineLimit(1)
                }
                if !text.detail.isEmpty {
                    Text(text.detail)
                        .font(.helvetica(11))
                        .lineLimit(1)
                        .foregroundStyle(selected ? Color(hex: 0xe3efff) : Color(hex: 0x6b7580))
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                if !text.value.isEmpty {
                    // A setting's value: bold and blue, or white on the selected row.
                    Text(text.value).font(.helvetica(12, bold: true)).foregroundStyle(selected ? Color.white : Pocket.blue)
                }
                if text.playing { IconView(.speakerLoud, width: 13, height: 11, label: "Now playing") }
                // Only the selected row shows its chevron, in white.
                if text.opens && selected { IconView(.chevron, width: 8, height: 12) }
            }
            .fixedSize()
        }
        .padding(.leading, 10)
        .padding(.trailing, scrolls ? 14 : 10)
        .frame(height: height)
        .foregroundStyle(selected ? Color.white : Pocket.ink)
        .background { if selected { Pocket.selection } }
        .overlay(alignment: .bottom) {
            // Two-line rows have a faint line between them, except under the selection.
            if !text.detail.isEmpty && !selected { Color.black.opacity(0.06).frame(height: 1) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
            let shift = Self.shift(at: t, loop: loop)
            HStack(spacing: 0) {
                text.padding(.trailing, 28)
                text.padding(.trailing, 28).accessibilityHidden(true)
            }
            .fixedSize()
            .visualEffect { content, geo in content.offset(x: -shift * geo.size.width / 2) }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)  // minWidth 0: else the frame is as wide as both copies
        }
        .clipped()
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
