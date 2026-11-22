import ClasifyCore
import QuartzCore
import SwiftUI

/// Cover Flow (Round 9, card AE): the albums of Liked Songs as covers in a row. The album in
/// the middle faces you. The others turn 61° toward it, stacked on each side. The names of the
/// middle album show under the covers. The covers glide when the selection moves (card AE
/// change 91), and a fast spin shows the big letter (card AG). The points are the mockup's,
/// from the top left of the 300 x 206 area under the title bar.
struct PocketCoverFlow: View {
    let state: AppState
    var input: @MainActor (Action) -> Void = { _ in }
    /// False from a screen move until the cover flight's 0.4 s end (`PocketScreen.landedSeq`).
    var landed = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The song panel that showed last, so it can turn back into the cover after MENU.
    @State private var lastPanel: AlbumPanel.Shown?

    var body: some View {
        let albums = state.albums
        let frame = state.stack.last { $0.screen == .coverFlow } ?? state.top
        let panel = AlbumPanel.Shown(state)
        // Card AH: on a song, the covers and the panel go at once and the cover flies to Now
        // Playing. On MENU they come back when it lands on the panel's place, 0.4 s later.
        let flying = state.nowOverPanel
        // On MENU the cover flies back, and the covers and the panel show when it lands. A timer
        // ends the flight, not a delayed animation: a zero-length animation can skip its delay
        // and show them at once (CLA-64). The flight keeps the move's own curve.
        let flyingBack = state.navMove == .fly && !state.navForward && !landed && !reduceMotion
        let inFlight = flying || flyingBack
        ZStack(alignment: .topLeading) {
            CoverFlowTurn(turn: panel == nil ? 0 : 1, panel: panel ?? lastPanel, state: state) {
                CoverFlowStrip(albums: albums, covers: state.albumCovers, pos: Double(frame.sel), spread: $0, hidesMiddle: $0 > 0)
                    // Fast steps retarget the glide, so the covers stream and then ease to a stop.
                    .animation(reduceMotion ? nil : CoverFlowStrip.glide, value: frame.sel)
            }
            .animation(nil) { $0.opacity(inFlight ? 0 : 1) }
            .accessibilityHidden(flying)
            if let shown = panel ?? lastPanel {
                CoverFly(fly: flying ? 1 : 0, panel: shown, state: state)
                    // Only while it flies: before, the panel shows; after, Now Playing's own cover.
                    .animation(nil) { $0.opacity(inFlight ? 1 : 0) }
                    .accessibilityHidden(true)
            }
            if flying {
                // Now Playing's text and time bar fade in over 0.1 s when the cover lands, and go
                // at once on MENU, leaving the cover.
                PocketNowPlaying(state: state, input: input)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)  // placed as on its own screen
                    .transition(reduceMotion ? .identity : .asymmetric(
                        insertion: .opacity.animation(.linear(duration: 0.1).delay(Self.flyTime)), removal: .identity))
            }
        }
        .overlay(alignment: .topLeading) { LetterBox(letter: state.coverFlowLetter) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: panel, initial: true) { _, new in if let new { lastPanel = new } }
    }

    /// The cover's flight between the song panel and Now Playing: 0.4 s, ease-in-out (card AH).
    static let flyTime = 0.4
    static let flyAnimation = Animation.easeInOut(duration: flyTime)
}

/// The covers at `pos`, which moves smoothly between two albums while they glide.
struct CoverFlowStrip: View, Animatable {
    let albums: [Album]
    /// The cover ID of each album, by album ID.
    let covers: [String: String]
    var pos: Double
    /// How far the side covers have moved out for the song panel, 0 to 1 (card AF): 44 points.
    var spread = 0.0
    /// The song panel shows: the middle cover and the names hide (card AF).
    var hidesMiddle = false
    @Environment(\.artwork) private var artwork
    /// The doors move hides the names until they fade in (card AE, change 82).
    @Environment(\.doorsStage) private var doors

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
    /// points, its turn in degrees, its scale and its opacity. Within one place of the middle
    /// the cover turns and moves gradually, so half way two covers meet in a V. All covers are
    /// equally bright (card AE.1).
    struct Pose: Equatable {
        var x: Double, angle: Double, scale: Double, opacity: Double
    }

    /// The side covers move out by `spread` x 44 points for the song panel (card AF).
    static let spreadWidth = 44.0

    static func pose(_ d: Double, spread: Double = 0) -> Pose {
        let m = abs(d), sign: Double = d > 0 ? 1 : -1
        // Card AE.1 (change 127): the first side cover 68 points out, then one every 27, turned
        // 61° and scaled to 0.63.
        let x = (m <= 1 ? sign * 68 * m : sign * (68 + (m - 1) * 27)) + (m > 0.001 ? sign * spreadWidth * spread : 0)
        let angle = -sign * 61 * min(m, 1)
        let scale = 1 - 0.37 * min(m, 1)
        return Pose(x: x, angle: angle, scale: scale, opacity: max(0, min(1, 7 - m)))
    }

    var body: some View {
        let shown = albums.isEmpty ? nil : albums[max(0, min(albums.count - 1, Int(pos.rounded())))]
        let low = max(0, Int(pos.rounded(.down)) - Self.perSide - 1)
        let high = min(albums.count - 1, Int(pos.rounded(.up)) + Self.perSide + 1)
        ZStack(alignment: .topLeading) {
            if low <= high {
                ForEach(low...high, id: \.self) { k in
                    let d = Double(k) - pos
                    let p = Self.pose(d, spread: spread)
                    ZStack(alignment: .topLeading) {
                        // A side cover's outer edge (change 129). The middle cover shows none.
                        let side: Double = d > 0 ? 1 : -1
                        edge(albums[k], side: side)
                            .modifier(CoverEdge(side: side, angle: p.angle, scale: p.scale))
                            .opacity(abs(d) > 0.001 ? 1 : 0)
                        cover(albums[k]).modifier(TurnY(angle: p.angle, scale: p.scale))
                    }
                    .opacity(hidesMiddle && abs(d) < 0.5 ? 0 : p.opacity)
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
                .opacity(hidesMiddle ? 0 : doors.names)
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

    /// A cover with its reflection, which turns with it: the cover, then right under it 30
    /// points of the cover turned over, from 35% to clear (card AE.1, change 124).
    func cover(_ album: Album) -> some View {
        let art = CoverArt(image: image(album), notesSize: 51)
        return VStack(spacing: 0) {
            art.frame(width: Self.side, height: Self.side).clipped()
                .overlay { Rectangle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5) }
            art.reflection(side: Self.side, height: Self.side / 4)
        }
        .frame(width: Self.side, height: Self.side * 1.25, alignment: .top)
    }

    /// A cover's 1 point thick edge on the `side` of it (1 right, -1 left): the art's outer
    /// column, from the same image stretched and clipped, 12% darker (card AE.1, change 129).
    func edge(_ album: Album, side: Double) -> some View {
        CoverArt(image: image(album), notesSize: 51)
            .frame(width: Self.side, height: Self.side)
            .frame(width: 1, height: Self.side, alignment: side > 0 ? .trailing : .leading)
            .clipped()
            .overlay { Color.black.opacity(0.12) }
    }

    private func image(_ album: Album) -> CGImage? { covers[album.id].flatMap { artwork.lookup($0) } }
}

/// The mockup's `perspective(86px) rotateY(angle) scale(scale)` about the cover's center
/// (60, 60), which leaves the reflection under it turning with it. Card AE.1 (change 127)
/// makes the depth stronger: 86 points, from 360.
struct TurnY: GeometryEffect {
    var angle: Double, scale: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(angle, scale) }
        set { (angle, scale) = (newValue.first, newValue.second) }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(Self.matrix(angle: angle, scale: scale))
    }

    static func matrix(angle: Double, scale: Double) -> CATransform3D {
        let c: CGFloat = 60  // half of `CoverFlowStrip.side`
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / 86
        var t = CATransform3DMakeTranslation(-c, -c, 0)
        t = CATransform3DConcat(t, CATransform3DMakeScale(scale, scale, 1))
        t = CATransform3DConcat(t, CATransform3DMakeRotation(angle * .pi / 180, 0, 1, 0))
        t = CATransform3DConcat(t, perspective)
        return CATransform3DConcat(t, CATransform3DMakeTranslation(c, c, 0))
    }
}

/// A cover's 1 point edge strip (card AE.1, change 129), as the mockup draws it: the strip
/// stands on the cover's right edge (`side` 1) or left edge (-1), turned 90° so it goes 1
/// point back from the face, and then turns with the cover (`TurnY`). Its view is 1 x 120
/// points at the cover's top left.
struct CoverEdge: GeometryEffect {
    let side: Double
    var angle: Double, scale: Double

    /// Animates like `TurnY`, so the strip stays on the face while the cover turns.
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(angle, scale) }
        set { (angle, scale) = (newValue.first, newValue.second) }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(Self.matrix(side: side, angle: angle, scale: scale))
    }

    static func matrix(side: Double, angle: Double, scale: Double) -> CATransform3D {
        // The strip turns about its edge on the cover: its left on the right edge, or its right
        // on the left edge. Then it moves there: x 120 or 0.
        let pivot: CGFloat = side > 0 ? 0 : 1, at: CGFloat = side > 0 ? 120 : 0
        var t = CATransform3DMakeTranslation(-pivot, -60, 0)
        t = CATransform3DConcat(t, CATransform3DMakeRotation(side * .pi / 2, 0, 1, 0))
        t = CATransform3DConcat(t, CATransform3DMakeTranslation(at, 60, 0))
        return CATransform3DConcat(t, TurnY.matrix(angle: angle, scale: scale))
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
