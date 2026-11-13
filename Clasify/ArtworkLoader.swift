import ClasifyCore
import ClasifySkins
import CoreGraphics
import Foundation
import ImageIO
import os

/// TEMP (cover blink, 2026-11-05): how covers load and how the playing track changes. Only
/// states and times, never an ID or a name. Remove once the cause of the blink is known.
private let timing = Logger(subsystem: "app.clasify.Clasify", category: "timing")

/// Loads album covers from Spotify's image CDN for the skins. It keeps them in memory only:
/// an NSCache of about 50 images, and a URLSession with no URL cache, so nothing goes to disk.
@MainActor @Observable
final class ArtworkLoader {
    /// Bumped when a cover arrives. `image(for:)` reads it, so a skin that asked redraws.
    private var arrived = 0
    private let cache = NSCache<NSString, CGImage>()
    /// TEMP (cover blink): logs when NSCache drops a cover. Kept here, because the delegate is weak.
    @ObservationIgnored private let evictionLog = EvictionLog()
    /// The covers on screen or next to show, held outside the NSCache. NSCache can
    /// drop any cover at any time, for example under memory pressure. When it dropped the playing
    /// cover, each redraw loaded it again and showed the square for a moment: the blink.
    @ObservationIgnored private var kept: [String: CGImage] = [:]
    /// The cover IDs that `kept` holds: the playing track's, the next track's, the main menu's
    /// and the ones Cover Flow draws.
    @ObservationIgnored private var wanted: Set<String> = []
    /// The main menu covers that the panel shows: the last set with a cover in memory. The
    /// panel keeps them until a cover of the new set loads, so they stay wanted until then.
    @ObservationIgnored private var mainShown: Set<String> = []
    /// The default cover IDs of `mainShown`. The panel decides when to switch sets from these
    /// only, not from the large covers, so this check must too.
    @ObservationIgnored private var mainShownDefaults: Set<String> = []
    /// The set before `mainShown`, kept while the panel fades from it, until `fadeEnds`.
    @ObservationIgnored private var mainFading: Set<String> = []
    @ObservationIgnored private var fadeEnds = ContinuousClock.now
    /// When the main menu closed. Its covers stay on screen while the next screen slides in.
    @ObservationIgnored private var leftMainAt: ContinuousClock.Instant?
    @ObservationIgnored private var loading: Set<String> = []
    /// When each cover arrived, so the main menu shows a large cover only from the turn after it loads.
    @ObservationIgnored private var arrivedAt: [String: Double] = [:]
    /// When a cover last failed, so it is not asked for again on every redraw.
    @ObservationIgnored private var failedAt: [String: ContinuousClock.Instant] = [:]
    /// TEMP: the playing track at the last `prefetchNext`, for the blink log.
    @ObservationIgnored private var lastRef: TrackRef?
    @ObservationIgnored private var previousRef: TrackRef?
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    init() {
        cache.countLimit = 50
        cache.delegate = evictionLog
    }

    /// For the skins: `.environment(\.artwork, loader.artwork)`.
    var artwork: Artwork {
        Artwork({ [self] in image(for: $0) }, pending: { [self] in isLoading($0) }, loadedAt: { [self] in arrivedAt[$0] })
    }

    /// The cover if it is in memory. Else it starts the load and returns nil.
    func image(for coverID: String) -> CGImage? {
        _ = arrived
        if let image = cached(coverID) { return image }
        load(coverID)
        return nil
    }

    /// The cover is on its way, so a skin can keep showing the cover it had.
    func isLoading(_ coverID: String) -> Bool {
        _ = arrived  // a load that ends bumps it, also when it fails
        return loading.contains(coverID)
    }

    /// Keeps the playing track's cover, and loads the cover of the track after it, so it shows
    /// at once on Next. The app's ticker calls it every 250 ms.
    func prefetchNext(in state: AppState) {
        logChange(in: state)
        var ids = Self.wantedCovers(in: state)
        ids.formUnion(heldMainCovers(in: state))
        if ids != wanted {
            wanted = ids
            kept = kept.filter { ids.contains($0.key) }
        }
        for id in ids where cached(id) == nil { load(id) }
    }

    /// The covers that the half-screen panel (main menu, Playlists) still shows or fades from, as `MainArtPanel` does:
    /// it switches to a new set once one of its covers is loaded, then fades over 1 s.
    private func heldMainCovers(in state: AppState) -> Set<String> {
        guard state.isHalf(state.top.screen) else {
            let left = leftMainAt ?? .now
            leftMainAt = left
            // The 0.22 s slide, with a margin. The old set only while its fade still runs.
            if ContinuousClock.now - left < .milliseconds(500) {
                return ContinuousClock.now < fadeEnds ? mainShown.union(mainFading) : mainShown
            }
            mainShown = []
            mainShownDefaults = []
            mainFading = []
            return []
        }
        leftMainAt = nil
        // As `MainArtPanel.switches`: a default cover of the new set is loaded, or none of the old.
        let defaults = Set(state.mainArt.compactMap(\.coverID))
        let ids = defaults.union(state.mainArt.compactMap(\.largeCoverID))
        if ids != mainShown
            && (defaults.contains { cached($0) != nil } || !mainShownDefaults.contains { cached($0) != nil }) {
            mainFading = mainShown
            mainShown = ids
            mainShownDefaults = defaults
            fadeEnds = .now + .seconds(2)  // the 1 s fade, with a margin
        }
        return ContinuousClock.now < fadeEnds ? mainShown.union(mainFading) : mainShown
    }

    /// The cover IDs of the playing track and of the track after it, on a half screen the
    /// covers that take turns there, and on Cover Flow the covers it draws, so none of them
    /// drops out of memory and blinks.
    static func wantedCovers(in state: AppState) -> Set<String> {
        var ids: Set<String> = []
        // The large covers too, which load in the background when the menu opens.
        if state.isHalf(state.top.screen) {
            ids.formUnion(state.mainArt.flatMap { [$0.coverID, $0.largeCoverID] }.compactMap { $0 })
        }
        // Cover Flow: the middle album and the 7 on each side that `CoverFlowStrip` draws, also
        // behind the song panel.
        if let frame = state.coverFlowFrame {
            let albums = state.albums, covers = state.albumCovers
            if !albums.isEmpty {
                let sel = min(max(frame.sel, 0), albums.count - 1)
                for album in albums[max(0, sel - 7)...min(albums.count - 1, sel + 7)] {
                    if let id = covers[album.id] { ids.insert(id) }
                }
            }
        }
        guard let ref = state.current else { return ids }
        if let id = state.track(ref)?.coverID { ids.insert(id) }
        let tracks = state.tracks(in: ref.playlist)
        if let index = tracks.firstIndex(where: { $0.id == ref.track }), index + 1 < tracks.count,
           let next = tracks[index + 1].coverID {
            ids.insert(next)
        }
        return ids
    }

    /// The cover from `kept` or the NSCache. A wanted cover found only in the NSCache goes into `kept`.
    private func cached(_ coverID: String) -> CGImage? {
        if let image = kept[coverID] { return image }
        guard let image = cache.object(forKey: coverID as NSString) else { return nil }
        if wanted.contains(coverID) { kept[coverID] = image }
        return image
    }

    private func load(_ coverID: String) {
        // A cover ID is 40 hex digits. Anything else never goes into a URL.
        guard coverID.count == 40, coverID.allSatisfy(\.isHexDigit), !loading.contains(coverID),
              let url = URL(string: "https://i.scdn.co/image/\(coverID)")
        else { return }
        if let failed = failedAt[coverID], ContinuousClock.now - failed < .seconds(30) { return }
        loading.insert(coverID)
        let start = ContinuousClock.now
        Task {
            defer { loading.remove(coverID); arrived += 1 }
            if let data = await Self.fetch(url, with: session),
               let source = CGImageSourceCreateWithData(data as CFData, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                cache.setObject(image, forKey: coverID as NSString)
                arrivedAt[coverID] = Date.timeIntervalSinceReferenceDate
                if wanted.contains(coverID) { kept[coverID] = image }
                failedAt[coverID] = nil
                timing.notice("cover: loaded in \(Self.ms(since: start), privacy: .public) ms")
            } else {
                failedAt[coverID] = .now
                timing.notice("cover: failed after \(Self.ms(since: start), privacy: .public) ms")
            }
        }
    }

    /// TEMP: logs each change of the playing track that the ticker sees, and its cover state.
    private func logChange(in state: AppState) {
        guard state.current != lastRef else { return }
        defer { lastRef = state.current }
        guard let ref = state.current else { return timing.notice("now playing: nothing") }
        let cover: String
        if let track = state.track(ref) {
            if let id = track.coverID {
                cover = cached(id) != nil ? "cover in memory" : loading.contains(id) ? "cover loading" : "cover not loaded"
            } else {
                cover = "no cover"
            }
        } else {
            cover = "not in Clasify's list, so no cover"
        }
        let back = previousRef == ref  // A, then B, then A again
        previousRef = lastRef
        timing.notice("now playing: \(back ? "back to the track before" : "new track", privacy: .public), \(cover, privacy: .public)")
    }

    private static func ms(since start: ContinuousClock.Instant) -> Int {
        Int((ContinuousClock.now - start) / .milliseconds(1))
    }

    /// The image bytes, or nil on any failure. It runs off the main actor. The decode of
    /// a cover of about 300 px stays on the main actor, so no image crosses actors.
    private nonisolated static func fetch(_ url: URL, with session: URLSession) async -> Data? {
        guard let result = try? await session.data(from: url),
              (result.1 as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return result.0
    }
}

/// TEMP (cover blink): logs each cover that the NSCache drops. Only the fact, never an ID.
private final class EvictionLog: NSObject, NSCacheDelegate {
    // NSCache can call this on any thread. It only writes to `Logger`, which is thread-safe.
    func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        timing.notice("cover: NSCache dropped a cover")
    }
}
