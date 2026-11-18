import ClasifyCore
import SwiftUI

/// The main menu's right side: the covers take turns, as on the classic pocket players. Each
/// cover stays `slot` seconds. It is drawn larger than the panel, at no zoom, and pans slowly at
/// a constant speed: to the left, then to the right and down for the next cover, in turn.
/// The next cover fades in on top of it, and the one under stays fully shown until the fade
/// ends, so the dark background never shows through. A cover that is not loaded yet shows the
/// cover before it until it loads. Only when no cover is loaded does the blue-grey square show.
/// The Playlists half screen uses the same panel.
struct MainArt: View {
    let tracks: [ClasifyCore.Track]  // not the skin's Track view
    @Environment(\.artwork) private var artwork
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.animationTime) private var fixedTime
    /// Build 308 (the 3D front showed a yellow box with a red "no" sign for the cover): the 3D
    /// front's picture (`K3DSpike.snapshot`) cannot draw an AppKit view, so it draws the covers
    /// in SwiftUI, at the time of the menu that shows (`liveStart`).
    @Environment(\.pocketSnapshot) private var snapshot
    /// When the main menu that shows on the screen appeared, for the 3D front's picture.
    @MainActor static var liveStart: Double?
    /// When this view appeared. Leaving the main menu ends the view, so a return starts over.
    @State private var start = Date.timeIntervalSinceReferenceDate

    /// Seconds that each cover shows, and seconds of the fade to the next (as on the device).
    static let slot = 6.8, fade = 0.6
    /// The side of each cover in points, centered in the 150 x 225 panel, with no zoom
    /// (card AL: 250, so people on a cover are not cut off).
    static let coverSide = 250.0
    /// The sideways pan speed in points a second.
    static let panSpeed = 6.7
    /// How far a cover moves sideways in its turn: it pans for all of `slot + fade` seconds,
    /// about 49.6 points. Half of it, 24.8, stays inside the side margin, (250 - 150) / 2 = 50.
    static let travel = panSpeed * (slot + fade)
    /// How far every second cover moves down in its turn, over the same time. Half of it,
    /// 12.5, is the whole top and bottom margin, (250 - 225) / 2, so no edge shows.
    static let drop = 25.0

    /// A point offset from the centered cover. A positive `y` moves it down.
    struct Offset: Equatable {
        var x: Double, y: Double
    }

    /// One layer at time `t`: opacity, the pan in points, and its order.
    struct Pose: Equatable {
        var opacity: Double, dx: Double, dy: Double
        /// A newer layer has a higher order, so the incoming cover is on top.
        var order: Double
    }

    /// Layer `index` of `count` at time `t`. At `t` = 0, the first cover is fully shown.
    static func pose(at t: Double, index: Int, count: Int) -> Pose {
        let (u, opacity, _) = phase(at: t, index: index, count: count)
        let m = motion(at: t, index: index, count: count)
        let e = (t - m.start) / (slot + fade)  // 0 to 1 over the pan, at a constant speed
        let c = e.truncatingRemainder(dividingBy: 2)
        let q = m.reverses ? (c < 1 ? c : 2 - c) : min(e, 1)
        return Pose(
            opacity: opacity, dx: m.from.x + (m.to.x - m.from.x) * q, dy: m.from.y + (m.to.y - m.from.y) * q,
            order: -u)
    }

    /// One layer's pan in its current turn: it starts at time `start`, moves from `from` to `to`
    /// (points) at a constant speed over `slot + fade` seconds, then holds. A single cover goes
    /// to and fro (`reverses`). The app draws it with Core Animation from these values, so the
    /// pan moves below a pixel. `turn` names the turn.
    struct Pan: Equatable {
        var start: Double, from: Offset, to: Offset, reverses: Bool, turn: Int
    }

    static func motion(at t: Double, index: Int, count: Int) -> Pan {
        let h = travel / 2
        let left = (from: Offset(x: h, y: 0), to: Offset(x: -h, y: 0))
        let rightDown = (from: Offset(x: -h, y: -drop / 2), to: Offset(x: h, y: drop / 2))
        if count <= 1 { return Pan(start: 0, from: left.from, to: left.to, reverses: true, turn: 0) }
        let (_, _, turn) = phase(at: t, index: index, count: count)
        // The direction alternates with each cover shown: left, then right and down.
        let way = turn % 2 == 0 ? left : rightDown
        // From whole numbers only, with no `t`, so it is exactly the same on every frame of the
        // turn. Else it could differ by a rounding error, and the view would restart the pan.
        let loops = (turn - index) / count
        let start = Double(loops) * slot * Double(count) + Double(index) * slot - fade
        return Pan(start: start, from: way.from, to: way.to, reverses: false, turn: turn)
    }

    /// Seconds since the layer started to fade in, its opacity, and its turn.
    private static func phase(at t: Double, index: Int, count: Int) -> (u: Double, opacity: Double, turn: Int) {
        if count <= 1 { return (t, 1, 0) }  // one cover always shows
        let period = slot * Double(count)
        let shifted = t + fade - Double(index) * slot
        let loops = (shifted / period).rounded(.down)
        let u = shifted - loops * period
        return (u, u < fade ? u / fade : u < slot + fade ? 1 : 0, Int(loops) * count + index)
    }

    /// The cover that a layer shows for its whole turn: the large one (about 640 px, sharp at
    /// 250 pt) when it was in memory when the turn began, else the default one (about 300 px).
    /// So a cover never changes while it shows: a large cover that loads during a turn shows
    /// from that cover's next turn. `turnStart` and `loadedAt` are seconds since the reference date.
    /// One cover only (a one-album list): its single turn lasts as long as the panel. So with
    /// a cold cache it keeps the default cover until the panel is made again, and never swaps
    /// while it shows. With the large cover already in memory, it is sharp from the start.
    static func coverID(
        for track: ClasifyCore.Track, turnStart: Double, loaded: (String) -> Bool, loadedAt: (String) -> Double?
    ) -> String? {
        if let large = track.largeCoverID, loaded(large), let at = loadedAt(large), at <= turnStart { return large }
        return track.coverID
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
        // 30 frames a second, for the fades. The pan moves only `panSpeed` points a second, and
        // SwiftUI snapped it to whole pixels, so it stepped.
        // Core Animation draws the pan instead (`PanningCover`).
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || fixedTime != nil)) { context in
            let base = snapshot ? Self.liveStart ?? start : start
            let t = fixedTime ?? context.date.timeIntervalSinceReferenceDate - base
            // Asking for each large cover also starts its load, in the background.
            let images = tracks.indices.map { i in
                let turnStart = base + Self.motion(at: t, index: i, count: tracks.count).start
                let id = Self.coverID(
                    for: tracks[i], turnStart: turnStart,
                    loaded: { artwork.lookup($0) != nil }, loadedAt: { artwork.loadedAt($0) })
                return id.flatMap { artwork.lookup($0) }
            }
            let sources = Self.sources(images.map { $0 != nil })
            GeometryReader { geo in
                ZStack {
                    if sources.allSatisfy({ $0 == nil }) {
                        layer(nil).frame(width: geo.size.width, height: geo.size.height)
                    } else {
                        ForEach(images.indices, id: \.self) { i in
                            // With Reduce Motion on, the first cover stays still.
                            let f = reduceMotion
                                ? Pose(opacity: i == 0 ? 1 : 0, dx: 0, dy: 0, order: 0)
                                : Self.pose(at: t, index: i, count: images.count)
                            let source = sources[i] ?? i
                            // When the layer's own cover loads late, it fades in over the cover
                            // that stood in for it, which stays fully shown under it: no cut.
                            ZStack {
                                cover(i, image: images[source], pose: f, t: t, count: images.count)
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .id(source)
                                    .zIndex(source == i ? 1 : 0)
                                    .transition(Self.crossfade)
                            }
                            .animation(.linear(duration: Self.fade), value: source)
                            .opacity(f.opacity)
                            .zIndex(f.order)
                        }
                    }
                }
            }
        }
        .clipped()
        .onAppear { if !snapshot { Self.liveStart = start } }
    }

    /// The new view fades in, and the old one stays fully shown until the fade ends, so the
    /// dark background never shows through.
    static var crossfade: AnyTransition {
        .asymmetric(insertion: .opacity, removal: .opacity.animation(.linear(duration: 0).delay(fade)))
    }

    /// One layer's cover. In the app, Core Animation pans it, so it moves below a pixel and
    /// does not step. A snapshot (a fixed time) cannot draw an AppKit view, so it draws the
    /// same pose in SwiftUI.
    @ViewBuilder
    private func cover(_ i: Int, image: CGImage?, pose f: Pose, t: Double, count: Int) -> some View {
        if fixedTime == nil, !snapshot, let image {
            let m = Self.motion(at: t, index: i, count: count)
            PanningCover(image: image, side: Self.coverSide, pan: reduceMotion ? nil : m, elapsed: t - m.start)
        } else {
            GeometryReader { geo in
                layer(image)
                    .frame(width: Self.coverSide, height: Self.coverSide)
                    .offset(x: f.dx, y: f.dy)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }

    private func layer(_ image: CGImage?) -> some View {
        CoverArt(image: image, notesSize: 60)
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

    /// The skin draws the 3D front's picture (`K3DSpike.snapshot`), with no AppKit views.
    var pocketSnapshot: Bool {
        get { self[PocketSnapshotKey.self] }
        set { self[PocketSnapshotKey.self] = newValue }
    }
}

private struct PocketSnapshotKey: EnvironmentKey {
    static let defaultValue = false
}
