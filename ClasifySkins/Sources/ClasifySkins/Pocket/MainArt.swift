import ClasifyCore
import SwiftUI

/// The main menu's right side: the covers take turns, as on the classic pocket players. Each
/// cover stays `slot` seconds and pans slowly sideways at a fixed scale: left to right, then
/// right to left for the next cover.
/// The next cover fades in on top of it, and the one under stays fully shown until the fade
/// ends, so the dark background never shows through. A cover that is not loaded yet is
/// skipped. Only when no cover is loaded does the colored square show.
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

    var body: some View {
        // 30 frames a second: the pan moves about 1.4 points a second (12 % of 104 points in
        // 9 s), so each frame moves about 0.05 point, and SwiftUI draws the offset smoothly.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || fixedTime != nil)) { context in
            let t = fixedTime ?? context.date.timeIntervalSinceReferenceDate - start
            let loaded = tracks.compactMap { track in track.coverID.flatMap { artwork.lookup($0) } }
            GeometryReader { geo in
                ZStack {
                    if loaded.isEmpty {
                        layer(tracks.first, image: nil).frame(width: geo.size.width, height: geo.size.height)
                    }
                    ForEach(loaded.indices, id: \.self) { i in
                        // With Reduce Motion on, the first cover stays still.
                        let f = reduceMotion
                            ? Pose(opacity: i == 0 ? 1 : 0, scale: Self.baseScale, dx: 0, dy: 0, order: 0)
                            : Self.pose(at: t, index: i, count: loaded.count)
                        layer(tracks.first, image: loaded[i])
                            .frame(width: geo.size.width, height: geo.size.height)
                            .scaleEffect(f.scale)
                            .offset(x: f.dx * geo.size.width, y: f.dy * geo.size.height)
                            .opacity(f.opacity)
                            .zIndex(f.order)
                    }
                }
            }
        }
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

    private func layer(_ track: ClasifyCore.Track?, image: CGImage?) -> some View {
        CoverArt(artist: track?.artist ?? "", coverID: track?.coverID, image: image, noteSize: 40, notesSize: 60)
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
