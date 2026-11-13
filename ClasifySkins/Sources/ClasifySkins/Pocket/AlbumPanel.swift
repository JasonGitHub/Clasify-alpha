import ClasifyCore
import QuartzCore
import SwiftUI

/// Cover Flow with the song panel (Round 9, card AF). Center turns the middle cover over into
/// the panel with the album's songs, and the side covers move 44 points out. MENU turns it
/// back. `turn` goes from 0 (the cover) to 1 (the panel) on the move's 0.35 s ease-in-out.
struct CoverFlowTurn<Strip: View>: View, Animatable {
    var turn: Double
    /// The panel to show, or the one that turns back into the cover.
    let panel: AlbumPanel.Shown?
    let state: AppState
    /// The covers, with the side covers moved out by the given part of 44 points.
    @ViewBuilder let strip: (Double) -> Strip

    // `Animatable` is nonisolated while `View` is on the main actor. `turn` is a plain Double
    // in a value type, so reading and writing it from any isolation is safe.
    nonisolated var animatableData: Double {
        get { turn }
        set { turn = newValue }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            strip(turn)
            if turn > 0, let panel {
                AlbumPanelCard(turn: turn, panel: panel, state: state)
            }
        }
    }
}

/// The card that turns over: the album's cover on the front, the song panel on the back.
/// It is the panel's size, scaled down to the cover's 120 points while the cover faces you.
struct AlbumPanelCard: View {
    let turn: Double
    let panel: AlbumPanel.Shown
    let state: AppState
    @Environment(\.artwork) private var artwork

    var body: some View {
        let text = panel.text(in: state)
        let height = AlbumPanel.height(songs: text.songs.count, bar: panel.bar)
        Group {
            if turn < 0.5 {
                // The cover, stretched to the card, so the card's scale makes it 120 x 120 again.
                CoverArt(image: state.albumCovers[panel.album].flatMap { artwork.lookup($0) }, notesSize: 51)
                    .frame(width: CoverFlowStrip.side, height: CoverFlowStrip.side).clipped()
                    .scaleEffect(x: AlbumPanel.width / CoverFlowStrip.side, y: height / CoverFlowStrip.side, anchor: .topLeading)
                    .frame(width: AlbumPanel.width, height: height, alignment: .topLeading)
            } else {
                AlbumPanel(text: text, sel: panel.sel, off: panel.off, height: height, scrollBar: state.scrollUntil > 0,
                           message: panel.message, now: panel.bar ? Labels.now(in: state) : nil, t: state.t)
                    // The back of the card: turned over once more, so it reads the right way.
                    .scaleEffect(x: turn < 1 ? -1 : 1, y: 1)
            }
        }
        .frame(width: AlbumPanel.width, height: height)
        .modifier(CoverTurn(turn: turn))
        .offset(x: AlbumPanel.left, y: AlbumPanel.top)
    }
}

/// The mockup's `cfFlipIn`: `perspective(800px) translateY(ty) scale(sx, sy) rotateY(angle)`
/// about the card's center. At 0 the card is the 120 point cover, at the cover's place; at 1
/// it is the panel, turned 180°. At 1 it is the plain panel, with no transform.
struct CoverTurn: GeometryEffect {
    let turn: Double

    func effectValue(size: CGSize) -> ProjectionTransform {
        guard turn < 1 else { return ProjectionTransform() }
        let p = CGFloat(max(0, turn))
        // The numbers are `CoverFlowStrip.side` (120) and the cover's and the panel's tops (22
        // and 9): this runs off the main actor, so it cannot read the views' constants.
        let side: CGFloat = 120
        // The cover's center is 22 + 60 = 82 points down; the panel's is 9 + height / 2.
        let ty = (82 - 9 - size.height / 2) * (1 - p)
        let sx = side / size.width + (1 - side / size.width) * p
        let sy = side / size.height + (1 - side / size.height) * p
        let cx = size.width / 2, cy = size.height / 2
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / 800
        var t = CATransform3DMakeTranslation(-cx, -cy, 0)
        t = CATransform3DConcat(t, CATransform3DMakeRotation(.pi * p, 0, 1, 0))
        t = CATransform3DConcat(t, CATransform3DMakeScale(sx, sy, 1))
        t = CATransform3DConcat(t, CATransform3DMakeTranslation(0, ty, 0))
        t = CATransform3DConcat(t, perspective)
        t = CATransform3DConcat(t, CATransform3DMakeTranslation(cx, cy, 0))
        return ProjectionTransform(t)
    }
}

/// The song panel (card AF): a 41 point blue top bar with the album and its artist, over
/// 23 point song rows in our song list style. The wheel moves the selection.
struct AlbumPanel: View {
    let text: Labels.PanelText
    let sel: Int
    /// The first row on screen, as the reducer keeps it.
    let off: Int
    let height: CGFloat
    let scrollBar: Bool
    /// Loading, an error or no songs: it shows in place of the rows (CLA-46).
    var message: Labels.Message? = nil
    /// The playing song, for the bar inside the panel's bottom edge (card AK, change 112). Nil: no bar.
    var now: Labels.NowText? = nil
    var t: Double = 0

    /// 244 points wide, 28 from each side and 9 under the title bar.
    static let width: CGFloat = 244, left: CGFloat = 28, top: CGFloat = 9
    static let barHeight: CGFloat = 41, rowHeight: CGFloat = 23

    /// The bar for the playing song inside the bottom edge: 22.9 points with its line (card AK).
    static let nowBarHeight = Pocket.barHeight + 1

    /// 41 + 23 a song (+ 22.9 for the bar), at least 188 (the same 9 point gap below as above)
    /// and at most 197.
    static func height(songs: Int, bar: Bool = false) -> CGFloat {
        max(188, min(197, barHeight + rowHeight * CGFloat(songs) + (bar ? nowBarHeight : 0)))
    }

    /// The height of the rows' room: under the top bar, and over the bar for the playing song.
    static func rowsHeight(_ height: CGFloat, bar: Bool = false) -> CGFloat {
        height - barHeight - (bar ? nowBarHeight : 0)
    }

    /// How far the rows move up: `off` rows, but never past the last row's bottom at the
    /// bottom of the rows' room.
    static func scroll(off: Int, songs: Int, height: CGFloat, bar: Bool = false) -> CGFloat {
        min(CGFloat(max(off, 0)) * rowHeight, max(0, rowHeight * CGFloat(songs) - rowsHeight(height, bar: bar)))
    }

    /// The scroll bar's thumb in a track `track` points long: its length shows the part of the
    /// list on screen, at least `PocketList.minThumb`. Nil when all rows fit.
    static func thumb(track: CGFloat, songs: Int, scroll: CGFloat, height: CGFloat, bar: Bool = false) -> (length: CGFloat, offset: CGFloat)? {
        let view = rowsHeight(height, bar: bar), all = rowHeight * CGFloat(songs)
        guard all > view else { return nil }
        let length = max(PocketList.minThumb, track * view / all)
        return (length, (track - length) * scroll / (all - view))
    }

    /// The top bar: iPhone 4 blue, light over dark with a hard line in the middle.
    static var bar: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(hex: 0xb0bccd), location: 0), .init(color: Color(hex: 0x8a9db6), location: 0.5),
                .init(color: Color(hex: 0x7d92ae), location: 0.5), .init(color: Color(hex: 0x6d84a2), location: 1),
            ],
            startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        let scroll = Self.scroll(off: off, songs: text.songs.count, height: height, bar: now != nil)
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                FadeLine(Text(text.album)).font(.helvetica(15, bold: true)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 0, y: -1)
                FadeLine(Text(text.artist)).font(.helvetica(12, bold: true)).foregroundStyle(.white.opacity(0.88))
                    .shadow(color: .black.opacity(0.4), radius: 0, y: -1)
            }
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .frame(height: Self.barHeight - 1)
            .background(Self.bar)
            Color(hex: 0x2d3642).frame(height: 1)
            Group {
                if let message {
                    MessageView(message: message).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        ForEach(text.songs.indices, id: \.self) { i in row(text.songs[i], selected: i == sel) }
                    }
                    .offset(y: -scroll)
                }
            }
            .frame(width: Self.width, height: Self.rowsHeight(height, bar: now != nil), alignment: .top)
            .clipped()
            if let now {
                Pocket.line.frame(height: 1)
                NowBar(now: now, t: t)
            }
        }
        .overlay(alignment: .topTrailing) { scrollBarView(scroll: scroll) }
        .frame(width: Self.width, height: height)
        .background(Color(hex: 0xf4f6f8))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3))
        .overlay {
            UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3)
                .stroke(.black.opacity(0.25), lineWidth: 1).padding(-0.5)
        }
        .shadow(color: .black.opacity(0.35), radius: 7, y: 4)
        .accessibilityElement(children: .contain)
    }

    /// A song row: bold 13, the title on the left and the length on the right, 11 points in
    /// from each side. The selected row has our blue bar and white text, and a long title scrolls.
    private func row(_ song: Labels.PanelText.Song, selected: Bool) -> some View {
        HStack(spacing: 12) {
            let label = Text(song.title)
            if selected {
                ViewThatFits(in: .horizontal) {
                    label.lineLimit(1)
                    Marquee(text: label, loop: Labels.marqueeLoop(song.title))
                }
            } else {
                FadeLine(label)
            }
            Spacer(minLength: 0)
            Text(song.length).monospacedDigit().fixedSize()
        }
        .font(.helvetica(13, bold: true))
        .padding(.horizontal, 11)
        .frame(height: Self.rowHeight)
        .foregroundStyle(selected ? Color.white : Pocket.ink)
        .background { if selected { Pocket.selection } }
        .overlay(alignment: .bottom) { Color.black.opacity(0.06).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Our song list's scroll bar: 3 points, #5d6772, 2 points under the top bar and 2 from
    /// the right. It shows on open and while the wheel moves, then fades out over 0.4 s.
    @ViewBuilder private func scrollBarView(scroll: CGFloat) -> some View {
        let track = Self.rowsHeight(height, bar: now != nil) - 4
        if let thumb = Self.thumb(track: track, songs: text.songs.count, scroll: scroll, height: height, bar: now != nil) {
            Capsule().fill(Color(hex: 0x5d6772))
                .frame(width: 3, height: thumb.length)
                .offset(y: thumb.offset)
                .frame(height: track, alignment: .top)
                .padding(.top, Self.barHeight + 2)
                .padding(.trailing, 2)
                .opacity(scrollBar ? 1 : 0)
                .animation(.easeInOut(duration: 0.4), value: scrollBar)
                .accessibilityHidden(true)
        }
    }

    /// The panel that shows: its album, the selected song and the first row on screen.
    struct Shown: Equatable {
        let album: String
        let sel: Int, off: Int
        /// Loading, an error or no songs (CLA-46).
        let message: Labels.Message?
        /// The bar for the playing song shows inside the panel (card AK, change 112).
        let bar: Bool

        /// Nil unless the song panel is on top, or under Now Playing while its cover flies there.
        init?(_ state: AppState) {
            let frame = state.nowOverPanel ? state.stack[state.stack.count - 2] : state.top
            guard case .albumPanel(let album) = frame.screen else { return nil }
            self.album = album
            sel = frame.sel
            off = frame.off
            message = Labels.message(for: frame, in: state)
            bar = state.showsPanelBar
        }

        /// The panel's text. While a message shows, it has no songs, so the panel is its
        /// smallest size.
        func text(in state: AppState) -> Labels.PanelText {
            var text = Labels.panel(album, in: state)
            if message != nil { text.songs = [] }
            return text
        }
    }
}

/// The song panel's cover on its flight to Now Playing (card AH), the mockup's `cfFly`. At 0
/// the card is the panel, as `AlbumPanelCard` leaves it. While it flies, it turns over once
/// more (180° to 360°) into the cover, and lands on Now Playing's 126.6 point tilted cover at
/// (9, 14.6). `fly` goes from 0 to 1 on the move's 0.4 s ease-in-out; MENU plays it back.
struct CoverFly: View, Animatable {
    var fly: Double
    let panel: AlbumPanel.Shown
    let state: AppState
    @Environment(\.artwork) private var artwork

    // `Animatable` is nonisolated while `View` is on the main actor. `fly` is a plain Double
    // in a value type, so reading and writing it from any isolation is safe.
    nonisolated var animatableData: Double {
        get { fly }
        set { fly = newValue }
    }

    var body: some View {
        let text = panel.text(in: state)
        let height = AlbumPanel.height(songs: text.songs.count, bar: panel.bar)
        Group {
            if fly < 0.5 {
                // The panel's back, turned the right way, as in `AlbumPanelCard`.
                AlbumPanel(text: text, sel: panel.sel, off: panel.off, height: height, scrollBar: false,
                           message: panel.message, now: panel.bar ? Labels.now(in: state) : nil, t: state.t)
                    .scaleEffect(x: -1, y: 1)
            } else {
                CoverArt(image: state.albumCovers[panel.album].flatMap { artwork.lookup($0) }, notesSize: 51)
                    .frame(width: CoverFlowStrip.side, height: CoverFlowStrip.side).clipped()
                    .scaleEffect(x: AlbumPanel.width / CoverFlowStrip.side, y: height / CoverFlowStrip.side, anchor: .topLeading)
                    .frame(width: AlbumPanel.width, height: height, alignment: .topLeading)
            }
        }
        .frame(width: AlbumPanel.width, height: height)
        .modifier(FlyEffect(fly: fly))
        .offset(x: AlbumPanel.left, y: AlbumPanel.top)
    }
}

/// The mockup's `cfFly` about the card's top left: `perspective(800px) translate(tx, ty)
/// translate(cx) rotateY(angle) translate(-cx) matrix3d(tilt) scale(sx, sy)`, each part
/// going straight from its start to its end.
struct FlyEffect: GeometryEffect {
    let fly: Double

    func effectValue(size: CGSize) -> ProjectionTransform {
        let f = CGFloat(min(max(fly, 0), 1))
        func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * f }
        // Lands as the 126.6 point cover (`PocketNowPlaying.coverSide`) at (9, 14.6): this
        // runs off the main actor, so it cannot read the views' constants.
        let side: CGFloat = 126.6
        var t = CATransform3DMakeScale(lerp(1, side / size.width), lerp(1, side / size.height), 1)
        var tilt = CATransform3DIdentity  // `Tilt`, from none to all of it
        tilt.m11 = lerp(1, 1.164835)
        tilt.m12 = lerp(0, 0.082418)
        tilt.m14 = lerp(0, 0.001259)
        t = CATransform3DConcat(t, tilt)
        let cx = lerp(size.width / 2, 74)  // the turn's axis: the panel's middle, then 74 points in
        t = CATransform3DConcat(t, CATransform3DMakeTranslation(-cx, 0, 0))
        t = CATransform3DConcat(t, CATransform3DMakeRotation(.pi * (1 + f), 0, 1, 0))
        t = CATransform3DConcat(t, CATransform3DMakeTranslation(cx, 0, 0))
        t = CATransform3DConcat(t, CATransform3DMakeTranslation(lerp(0, -19), lerp(0, 5.6), 0))
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / 800
        t = CATransform3DConcat(t, perspective)
        return ProjectionTransform(t)
    }
}
