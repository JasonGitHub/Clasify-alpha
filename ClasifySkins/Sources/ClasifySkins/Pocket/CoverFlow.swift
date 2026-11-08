import ClasifyCore
import QuartzCore
import SwiftUI

/// Cover Flow (Round 9, card AE): the albums of Liked Songs as covers in a row. The album in
/// the middle faces you. The others turn 70° toward it, stacked on each side. The names of the
/// middle album show under the covers. The covers glide when the selection moves (card AE
/// change 91), and a fast spin shows the big letter (card AG). The points are the mockup's,
/// from the top left of the 300 x 206 area under the title bar.
struct PocketCoverFlow: View {
    let state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let albums = state.albums
        CoverFlowStrip(albums: albums, covers: state.albumCovers, pos: Double(state.top.sel))
            // Fast steps retarget the glide, so the covers stream and then ease to a stop.
            .animation(reduceMotion ? nil : CoverFlowStrip.glide, value: state.top.sel)
            .overlay(alignment: .topLeading) { LetterBox(letter: state.coverFlowLetter) }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The covers at `pos`, which moves smoothly between two albums while they glide.
struct CoverFlowStrip: View, Animatable {
    let albums: [Album]
    /// The cover ID of each album, by album ID.
    let covers: [String: String]
    var pos: Double
    @Environment(\.artwork) private var artwork

    // `Animatable` is nonisolated while `View` is on the main actor. `pos` is a plain Double
    // in a value type, so reading and writing it from any isolation is safe.
    nonisolated var animatableData: Double {
        get { pos }
        set { pos = newValue }
    }

    /// About 0.3 s, slowing down at the end. A new step keeps the speed it has.
    static let glide = Animation.spring(response: 0.3, dampingFraction: 1)
    /// The middle cover's side and its top.
    static let side: CGFloat = 120, top: CGFloat = 22
    /// The most covers that show on each side. `ArtworkLoader.wantedCovers` keeps one more on
    /// each side (7) in memory, the ones that fade in at the ends.
    static let perSide = 6

    /// Where an album `d` places from the middle shows: its center's offset from the middle in
    /// points, its turn in degrees, its scale, how dark it is (0 to 1), and its opacity. Within
    /// one place of the middle the cover turns and moves gradually, so half way two covers
    /// meet in a V.
    struct Pose: Equatable {
        var x: Double, angle: Double, scale: Double, dark: Double, opacity: Double
    }

    static func pose(_ d: Double) -> Pose {
        let m = abs(d), sign: Double = d > 0 ? 1 : -1
        let x = m <= 1 ? sign * 72 * m : sign * (72 + (m - 1) * 27)
        let angle = -sign * 70 * min(m, 1)
        let scale = 1 - 0.1 * min(m, 1)
        return Pose(x: x, angle: angle, scale: scale, dark: 0.04 * min(m, 6), opacity: max(0, min(1, 7 - m)))
    }

    var body: some View {
        let shown = albums.isEmpty ? nil : albums[max(0, min(albums.count - 1, Int(pos.rounded())))]
        let low = max(0, Int(pos.rounded(.down)) - Self.perSide - 1)
        let high = min(albums.count - 1, Int(pos.rounded(.up)) + Self.perSide + 1)
        ZStack(alignment: .topLeading) {
            if low <= high {
                ForEach(low...high, id: \.self) { k in
                    let p = Self.pose(Double(k) - pos)
                    cover(albums[k])
                        // The mockup's brightness filter: darker away from the middle. A multiply
                        // keeps the clear end of the reflection clear.
                        .colorMultiply(Color(white: 1 - p.dark))
                        .modifier(TurnY(angle: p.angle, scale: p.scale))
                        .opacity(p.opacity)
                        .offset(x: Pocket.screenWidth / 2 + p.x - Self.side / 2, y: Self.top)
                        .zIndex(100 - abs(Double(k) - pos) * 10)
                }
            }
            // The names change when a cover passes the middle.
            if let shown {
                VStack(spacing: 0) {
                    name(shown.name, color: .black)
                    name(shown.artist ?? "", color: Pocket.ink)
                }
                .offset(y: 164 - 2)  // the mockup's 14 pt lines start 2 pt above the text
                .zIndex(200)
            }
        }
        .frame(width: Pocket.screenWidth, alignment: .topLeading)
        .accessibilityElement()
        .accessibilityLabel(shown.map { "\($0.name), \($0.artist ?? "")" } ?? "")
    }

    /// One line under the covers: bold 14, centered, 10 points in from each side.
    private func name(_ text: String, color: Color) -> some View {
        FadeLine(Text(text)).font(.helvetica(14, bold: true)).foregroundStyle(color)
            .frame(height: 17)
            .frame(width: Pocket.screenWidth - 20)
            .padding(.horizontal, 10)
    }

    /// A cover with its reflection, which turns with it: the cover, a 1 point gap, then 30
    /// points of the cover turned over, from 35% to clear.
    private func cover(_ album: Album) -> some View {
        let image = covers[album.id].flatMap { artwork.lookup($0) }
        let art = CoverArt(image: image, notesSize: 51)
        return VStack(spacing: 1) {
            art.frame(width: Self.side, height: Self.side).clipped()
                .overlay { Rectangle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5) }
            art.reflection(side: Self.side, height: Self.side / 4)
        }
        .frame(width: Self.side, height: Self.side * 1.25 + 1, alignment: .top)
    }
}

/// The mockup's `perspective(360px) rotateY(angle) scale(scale)` about the cover's center
/// (60, 60), which leaves the reflection under it turning with it.
struct TurnY: GeometryEffect {
    var angle: Double, scale: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(angle, scale) }
        set { (angle, scale) = (newValue.first, newValue.second) }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let c: CGFloat = 60  // half of `CoverFlowStrip.side`
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / 360
        var t = CATransform3DMakeTranslation(-c, -c, 0)
        t = CATransform3DConcat(t, CATransform3DMakeScale(scale, scale, 1))
        t = CATransform3DConcat(t, CATransform3DMakeRotation(angle * .pi / 180, 0, 1, 0))
        t = CATransform3DConcat(t, perspective)
        t = CATransform3DConcat(t, CATransform3DMakeTranslation(c, c, 0))
        return ProjectionTransform(t)
    }
}

/// The big letter of a fast spin (card AG): a 62 point box, radius 10, dark 78%, with the
/// letter in bold 40 white, over the middle cover. It fades in over 0.15 s and out over 0.3 s.
struct LetterBox: View {
    let letter: String?
    /// The letter that fades out after the spin ends.
    @State private var last = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(letter ?? last)
            .font(.helvetica(40, bold: true)).foregroundStyle(.white)
            .frame(width: 62, height: 62)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x1c2026).opacity(0.78)))
            .opacity(letter == nil ? 0 : 1)
            .animation(reduceMotion ? nil : .linear(duration: letter == nil ? 0.3 : 0.15), value: letter == nil)
            .offset(x: 119, y: 51)
            .onChange(of: letter) { _, new in if let new { last = new } }
            .accessibilityHidden(letter == nil)
            .allowsHitTesting(false)
    }
}
