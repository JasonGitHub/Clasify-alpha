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
    @ObservationIgnored private var loading: Set<String> = []
    /// When a cover last failed, so it is not asked for again on every redraw.
    @ObservationIgnored private var failedAt: [String: ContinuousClock.Instant] = [:]
    /// TEMP: the playing track at the last `prefetchNext`, for the blink log.
    @ObservationIgnored private var lastRef: TrackRef?, previousRef: TrackRef?
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    init() {
        cache.countLimit = 50
    }

    /// For the skins: `.environment(\.artwork, loader.artwork)`.
    var artwork: Artwork {
        Artwork({ [self] in image(for: $0) }, pending: { [self] in isLoading($0) })
    }

    /// The cover if it is in memory. Else it starts the load and returns nil.
    func image(for coverID: String) -> CGImage? {
        _ = arrived
        if let image = cache.object(forKey: coverID as NSString) { return image }
        load(coverID)
        return nil
    }

    /// The cover is on its way, so a skin can keep showing the cover it had.
    func isLoading(_ coverID: String) -> Bool {
        _ = arrived  // a load that ends bumps it, also when it fails
        return loading.contains(coverID)
    }

    /// Loads the cover of the track after the current one, so it shows at once on Next.
    func prefetchNext(in state: AppState) {
        logChange(in: state)
        guard let ref = state.current else { return }
        let tracks = state.tracks(in: ref.playlist)
        guard let index = tracks.firstIndex(where: { $0.id == ref.track }), index + 1 < tracks.count,
              let next = tracks[index + 1].coverID, cache.object(forKey: next as NSString) == nil
        else { return }
        load(next)
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
                cover = cache.object(forKey: id as NSString) != nil ? "cover in memory" : loading.contains(id) ? "cover loading" : "cover not loaded"
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
