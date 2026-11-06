import ClasifyCore
import SwiftUI

/// The main menu's right side: the covers take turns, as on the classic pocket players. Each
/// cover stays `slot` seconds and pans slowly sideways at a fixed scale: left to right, then
/// right to left for the next cover.
/// The next cover fades in on top of it, and the one under stays fully shown until the fade
/// ends, so the dark background never shows through. A cover that is not loaded yet shows the
/// cover before it until it loads. Only when no cover is loaded does the colored square show.
struct MainArt: View {
    let tracks: [ClasifyCore.Track]  // not the skin's Track view
    @Environment(\.artwork) private var artwork
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.animationTime) private var fixedTime
    /// When this view appeared. Leaving the main menu ends the view, so a return starts over.
    @State private var start = Date.timeIntervalSinceReferenceDate

    /// Seconds that each cover shows, and seconds of the fade to the next.
    static let slot = 8.0, fade = 1.0
    /// The fixed scale of each cover.
    static let baseScale = 1.15
    /// The farthest a cover moves from the center, as a part of its width. It stays inside the
    /// margin that `baseScale` gives, (1.15 - 1) / 2 = 7.5 %, so no edge shows.
    static let pan = 0.06

    /// One layer at time `t`: opacity, scale, the pan as a part of the size, and its order.
    struct Pose: Equatable {
        var opacity: Double, scale: Double, dx: Double, dy: Double
        /// A newer layer has a higher order, so the incoming cover is on top.
        var order: Double
    }

    /// Layer `index` of `count` at time `t`. At `t` = 0, the first cover is fully shown.
    static func pose(at t: Double, index: Int, count: Int) -> Pose {
        let span = slot + fade
        let u: Double  // seconds since this layer started to fade in
        let opacity: Double
        let turn: Int  // counts the covers shown so far, so the direction alternates
        if count <= 1 {
            // One cover: it always shows, and pans to and fro.
            let cycle = (t / span).truncatingRemainder(dividingBy: 2)
            u = (cycle < 1 ? cycle : 2 - cycle) * span
            opacity = 1
            turn = 0
        } else {
            let period = slot * Double(count)
            let shifted = t + fade - Double(index) * slot
            let loops = (shifted / period).rounded(.down)
            u = shifted - loops * period
            opacity = u < fade ? u / fade : u < span ? 1 : 0
            turn = Int(loops) * count + index
        }
        let p = min(u, span) / span  // 0 to 1 over the pan, at a constant speed
        let toRight = turn % 2 == 0
        return Pose(opacity: opacity, scale: baseScale, dx: pan * (toRight ? 2 * p - 1 : 1 - 2 * p), dy: 0, order: -u)
    }

    /// Each missing item takes the nearest one before it, wrapping around, so a cover that has
    /// not loaded yet shows the cover before it. The timing stays the same when it loads late.
    /// All nil stays all nil.
    static func filled<T>(_ items: [T?]) -> [T?] {
        sources(items.map { $0 != nil }).map { $0.flatMap { items[$0] } }
    }

    /// For each item, the index of the item that it shows: itself when it is there, otherwise
    /// the nearest one before it that is there, wrapping around. Nil when none is there.
    static func sources(_ present: [Bool]) -> [Int?] {
        guard let last = present.lastIndex(of: true) else { return present.map { _ in nil } }
        var previous = last
        return present.indices.map { i in
            if present[i] { previous = i }
            return previous
        }
    }

    var body: some View {
        // 30 frames a second. The pan moves about 1.4 points a second (12 % of 104 points in
        // 9 s). The offset is never rounded here, so it moves smoothly unless the drawing
        // snaps it to whole pixels. Check that on a Mac.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || fixedTime != nil)) { context in
            let t = fixedTime ?? context.date.timeIntervalSinceReferenceDate - start
            let images = tracks.map { track in track.coverID.flatMap { artwork.lookup($0) } }
            let sources = Self.sources(images.map { $0 != nil })
            GeometryReader { geo in
                ZStack {
                    if sources.allSatisfy({ $0 == nil }) {
                        layer(tracks.first, image: nil).frame(width: geo.size.width, height: geo.size.height)
                    } else {
                        ForEach(images.indices, id: \.self) { i in
                            // With Reduce Motion on, the first cover stays still.
                            let f = reduceMotion
                                ? Pose(opacity: i == 0 ? 1 : 0, scale: Self.baseScale, dx: 0, dy: 0, order: 0)
                                : Self.pose(at: t, index: i, count: images.count)
                            let source = sources[i] ?? i
                            // When the layer's own cover loads late, it fades in over the cover
                            // that stood in for it, which stays fully shown under it: no cut.
                            ZStack {
                                layer(tracks.first, image: images[source])
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .id(source)
                                    .zIndex(source == i ? 1 : 0)
                                    .transition(Self.crossfade)
                            }
                            .animation(.linear(duration: Self.fade), value: source)
                            .scaleEffect(f.scale)
                            .offset(x: f.dx * geo.size.width, y: f.dy * geo.size.height)
                            .opacity(f.opacity)
                            .zIndex(f.order)
                        }
                    }
                }
            }
        }
        .clipped()
    }

    /// The new view fades in, and the old one stays fully shown until the fade ends, so the
    /// dark background never shows through.
    static var crossfade: AnyTransition {
        .asymmetric(insertion: .opacity, removal: .opacity.animation(.linear(duration: 0).delay(fade)))
    }

    private func layer(_ track: ClasifyCore.Track?, image: CGImage?) -> some View {
        CoverArt(artist: track?.artist ?? "", coverID: track?.coverID, image: image, noteSize: 40, notesSize: 60)
    }
}

/// The main menu's cover panel. When the selected row brings new covers, the new set fades
/// in on top over `MainArt.fade` and starts at its own time 0, while the old set stays fully
/// shown under it. It switches once one of the new covers is loaded, so the square never
/// replaces covers that show.
struct MainArtPanel: View {
    let tracks: [ClasifyCore.Track]
    @Environment(\.artwork) private var artwork
    /// The set that shows, and a count that names it, so a new set is a new view on top.
    @State private var shown: [ClasifyCore.Track]
    @State private var generation = 0

    init(tracks: [ClasifyCore.Track]) {
        self.tracks = tracks
        _shown = State(initialValue: tracks)
    }

    /// True when the panel moves from the `old` covers to the `new` ones: they differ, and one
    /// of the new covers is loaded, or none of the old ones is.
    static func switches(to new: [String?], from old: [String?], loaded: (String?) -> Bool) -> Bool {
        new != old && (new.contains(where: loaded) || !old.contains(where: loaded))
    }

    var body: some View {
        let ready = Self.switches(
            to: tracks.map(\.coverID), from: shown.map(\.coverID),
            loaded: { id in id.flatMap { artwork.lookup($0) } != nil })
        ZStack {
            MainArt(tracks: shown)
                .id(generation)
                .zIndex(Double(generation))
                .transition(MainArt.crossfade)
        }
        .onChange(of: ready ? tracks.map(\.coverID) : nil) { _, ids in
            guard ids != nil else { return }
            withAnimation(.linear(duration: MainArt.fade)) {
                shown = tracks
                generation += 1
            }
        }
        // Behind the covers, and over them the gloss, once for the whole panel, so a fade
        // never shows them twice.
        .background(Pocket.ink)
        .overlay(alignment: .top) {
            GeometryReader { geo in
                LinearGradient.vertical(.white.opacity(0.22), .white.opacity(0))
                    .frame(height: geo.size.height * 0.45)
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

private struct AnimationTimeKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}

extension EnvironmentValues {
    /// A fixed time for the skin's loops, so snapshots draw one known frame. Nil runs them live.
    var animationTime: Double? {
        get { self[AnimationTimeKey.self] }
        set { self[AnimationTimeKey.self] = newValue }
    }
}
