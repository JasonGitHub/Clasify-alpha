import ClasifyCore
import SwiftUI

/// The main menu's right side: four covers that take turns, each with a slow zoom and drift.
/// This is the mockup's `kbx` keyframes: 24 s a loop, and each layer starts 6 s after the one before.
struct MainArt: View {
    let tracks: [ClasifyCore.Track]  // not the skin's Track view
    @Environment(\.artwork) private var artwork
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.animationTime) private var fixedTime

    static let loop = 24.0

    /// One layer at time `t` of its own loop: opacity, scale, and the drift as a part of the size.
    struct Pose: Equatable {
        var opacity: Double, scale: Double, dx: Double, dy: Double
    }

    /// 0 %: hidden, scale 1.08, moved (-3 %, -2 %). 4 %: shown. 25 %: still shown.
    /// 29 %: hidden, scale 1.22, moved (3 %, 2 %). Then hidden until 100 %.
    static func pose(at t: Double, delay: Double) -> Pose {
        let local = t - delay
        let p = local < 0 ? 0 : local.truncatingRemainder(dividingBy: loop) / loop
        let opacity = p < 0.04 ? p / 0.04 : p < 0.25 ? 1 : p < 0.29 ? 1 - (p - 0.25) / 0.04 : 0
        let q = min(p / 0.29, 1)
        return Pose(opacity: opacity, scale: 1.08 + 0.14 * q, dx: -0.03 + 0.06 * q, dy: -0.02 + 0.04 * q)
    }

    var body: some View {
        // 30 frames a second is smooth for a 24 s drift, and costs less than the display rate.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || fixedTime != nil)) { context in
            let t = fixedTime ?? context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                ZStack {
                    if tracks.isEmpty { layer(nil).frame(width: geo.size.width, height: geo.size.height) }  // nothing read yet: the blue-grey square
                    ForEach(tracks.indices, id: \.self) { i in
                        // With Reduce Motion on, the first cover stays still.
                        let f = reduceMotion
                            ? Pose(opacity: i == 0 ? 1 : 0, scale: 1.08, dx: 0, dy: 0)
                            : Self.pose(at: t, delay: Double(i) * 6)
                        layer(tracks[i])
                            .frame(width: geo.size.width, height: geo.size.height)
                            .scaleEffect(f.scale)
                            .offset(x: f.dx * geo.size.width, y: f.dy * geo.size.height)
                            .opacity(f.opacity)
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

    private func layer(_ track: ClasifyCore.Track?) -> some View {
        CoverArt(artist: track?.artist ?? "", coverID: track?.coverID,
                 image: track?.coverID.flatMap { artwork.lookup($0) }, noteSize: 40, notesSize: 60)
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
