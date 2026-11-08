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
        let text = Labels.panel(panel.album, in: state)
        let height = AlbumPanel.height(songs: text.songs.count)
        Group {
            if turn < 0.5 {
                // The cover, stretched to the card, so the card's scale makes it 120 x 120 again.
                CoverArt(image: state.albumCovers[panel.album].flatMap { artwork.lookup($0) }, notesSize: 51)
                    .frame(width: CoverFlowStrip.side, height: CoverFlowStrip.side).clipped()
                    .scaleEffect(x: AlbumPanel.width / CoverFlowStrip.side, y: height / CoverFlowStrip.side, anchor: .topLeading)
                    .frame(width: AlbumPanel.width, height: height, alignment: .topLeading)
            } else {
                AlbumPanel(text: text, sel: panel.sel, off: panel.off, height: height, scrollBar: state.scrollUntil > 0)
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

    /// 244 points wide, 28 from each side and 9 under the title bar.
    static let width: CGFloat = 244, left: CGFloat = 28, top: CGFloat = 9
    static let barHeight: CGFloat = 41, rowHeight: CGFloat = 23

    /// 41 + 23 a song, at least 188 (the same 9 point gap below as above) and at most 197.
    static func height(songs: Int) -> CGFloat {
        max(188, min(197, barHeight + rowHeight * CGFloat(songs)))
    }

    /// How far the rows move up: `off` rows, but never past the last row's bottom at the
    /// panel's bottom.
    static func scroll(off: Int, songs: Int, height: CGFloat) -> CGFloat {
        min(CGFloat(max(off, 0)) * rowHeight, max(0, rowHeight * CGFloat(songs) - (height - barHeight)))
    }

    /// The scroll bar's thumb in a track `track` points long: its length shows the part of the
    /// list on screen, at least `PocketList.minThumb`. Nil when all rows fit.
    static func thumb(track: CGFloat, songs: Int, scroll: CGFloat, height: CGFloat) -> (length: CGFloat, offset: CGFloat)? {
        let view = height - barHeight, all = rowHeight * CGFloat(songs)
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
        let scroll = Self.scroll(off: off, songs: text.songs.count, height: height)
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
            VStack(spacing: 0) {
                ForEach(text.songs.indices, id: \.self) { i in row(text.songs[i], selected: i == sel) }
            }
            .offset(y: -scroll)
            .frame(width: Self.width, height: height - Self.barHeight, alignment: .top)
            .clipped()
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
        let track = height - Self.barHeight - 4
        if let thumb = Self.thumb(track: track, songs: text.songs.count, scroll: scroll, height: height) {
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

        /// Nil unless the song panel is on top.
        init?(_ state: AppState) {
            guard case .albumPanel(let album) = state.top.screen else { return nil }
            self.album = album
            sel = state.top.sel
            off = state.top.off
        }
    }
}
