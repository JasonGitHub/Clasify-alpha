// TEMP (CLA-103, Jason 16:34 JST 11-14): a hidden probe of other ways to get Apple Music covers.
// Delete this file and its one call in `AppleMusicReads.tracks(_:)` after the next build's log.
// It shows nothing, keeps nothing and writes nothing. It logs counts only: no titles, no IDs.
// MusicKit's types are not Sendable in the macOS 15 SDK: songs stay on the main actor, and
// only title keys (strings) go to the iTunesLibrary read off the main actor.
import AppKit
import ClasifyCore
import iTunesLibrary
@preconcurrency import MusicKit
import os
import SwiftUI

private let timing = Logger(subsystem: "app.clasify.Clasify", category: "timing")

@MainActor
enum AppleMusicCoverProbe {
    private static var ran = false

    /// Runs the probe once a launch, on the first 10 songs of the first song list read.
    static func runOnce(_ songs: [Song]) {
        guard !ran, !songs.isEmpty else { return }
        ran = true
        let sample = Array(songs.prefix(10))
        Task { await Self.run(sample) }
    }

    private static func run(_ songs: [Song]) async {
        log("shape", shape(songs))
        log("B ArtworkImage", await snapshots(songs))
        let keys = songs.map { LibraryKey.of(title: $0.title, artist: $0.artistName, album: $0.albumTitle) }
        log("C iTunesLibrary", await Task.detached { Self.musicLibrary(keys) }.value)
        log("E catalog with", await catalogWith(songs))
        log("F catalog search", await search(songs))
    }

    private static func log(_ way: String, _ counts: String) {
        timing.notice("apple covers probe (TEMP): \(way, privacy: .public): \(counts, privacy: .public)")
    }

    /// The artwork URL's scheme and host, and the ID's shape, of each song.
    private static func shape(_ songs: [Song]) -> String {
        var urls: [String: Int] = [:], ids: [String: Int] = [:]
        for song in songs {
            let url = song.artwork?.url(width: 300, height: 300)
            urls["\(url?.scheme ?? "none") \(url?.host ?? "none")", default: 0] += 1
            let id = song.id.rawValue
            let kind = id.allSatisfy(\.isNumber) ? "digits" : id.hasPrefix("i.") ? "i." : id.hasPrefix("l.") ? "l." : "other"
            ids["\(kind) length \(id.count)", default: 0] += 1
        }
        return "songs \(songs.count), url \(describe(urls)), id \(describe(ids))"
    }

    /// B: MusicKit's own `ArtworkImage`, drawn by ImageRenderer every 0.2 s for about 2 s.
    private static func snapshots(_ songs: [Song]) async -> String {
        let renderers = songs.compactMap(\.artwork).map { ImageRenderer(content: ArtworkImage($0, width: 64, height: 64)) }
        let start = ContinuousClock.now
        var done = Set<Int>(), first: Int?
        while ContinuousClock.now - start < .seconds(2), done.count < renderers.count {
            for (i, renderer) in renderers.enumerated() where !done.contains(i) {
                guard let image = renderer.cgImage, varies(image) else { continue }
                done.insert(i)
                if first == nil { first = Int((ContinuousClock.now - start) / .milliseconds(1)) }
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return "with artwork \(renderers.count), non-empty \(done.count), ms to first \(first.map(String.init) ?? "none")"
    }

    /// True when an image is not one flat color: some channel differs across an 8 x 8 copy.
    private static func varies(_ image: CGImage) -> Bool {
        var pixels = [UInt8](repeating: 0, count: 8 * 8 * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 8, height: 8))
            return true
        }
        return drawn && (0..<4).contains { c in
            let channel = stride(from: c, to: pixels.count, by: 4).map { pixels[$0] }
            return (channel.max() ?? 0) - (channel.min() ?? 0) > 8
        }
    }

    /// C: Apple's iTunesLibrary framework, read-only, off the main actor. Matched by
    /// `LibraryKey`. The image stays in this function; only its size class is counted.
    nonisolated private static func musicLibrary(_ keys: [String]) -> String {
        let library: ITLibrary
        do { library = try ITLibrary(apiVersion: "1.0") } catch { return "opened no (\(kind(error)))" }
        let wanted = Set(keys)
        var seen = Set<String>(), withImage = 0, sizes: [String: Int] = [:]
        let items = library.allMediaItems
        for item in items {
            let key = LibraryKey.of(title: item.title, artist: item.artist?.name ?? "", album: item.album.title)
            guard wanted.contains(key), seen.insert(key).inserted else { continue }
            guard item.hasArtworkAvailable, let image = item.artwork?.image else { continue }
            withImage += 1
            let side = max(image.size.width, image.size.height)
            sizes[side >= 600 ? "600+" : side >= 300 ? "300-599" : "under 300", default: 0] += 1
        }
        return "opened yes, items \(items.count), matched \(seen.count) of \(wanted.count), "
            + "with image \(withImage), sizes \(describe(sizes))"
    }

    /// E: each song asked again with the catalog as the preferred source.
    private static func catalogWith(_ songs: [Song]) async -> String {
        var returned = 0, passes = 0, threw = Set<String>()
        for song in songs {
            do {
                let found = try await song.with([.albums], preferredSource: .catalog)
                returned += 1
                if AppleMusicReads.cover(found.artwork) != nil { passes += 1 }
            } catch { threw.insert(kind(error)) }
        }
        return "returned \(returned), passes CoverURL \(passes), threw \(threw.isEmpty ? "no" : threw.sorted().joined(separator: ", "))"
    }

    /// F: a catalog search by title and artist; the top hit.
    private static func search(_ songs: [Song]) async -> String {
        var returned = 0, same = 0, passes = 0, threw = Set<String>()
        for song in songs {
            var request = MusicCatalogSearchRequest(term: "\(song.title) \(song.artistName)", types: [Song.self])
            request.limit = 5
            do {
                guard let top = try await request.response().songs.first else { continue }
                returned += 1
                if top.title.lowercased() == song.title.lowercased(), top.artistName.lowercased() == song.artistName.lowercased() {
                    same += 1
                }
                if AppleMusicReads.cover(top.artwork) != nil { passes += 1 }
            } catch { threw.insert(kind(error)) }
        }
        return "returned \(returned), top hit same title and artist \(same), passes CoverURL \(passes), "
            + "threw \(threw.isEmpty ? "no" : threw.sorted().joined(separator: ", "))"
    }

    nonisolated private static func kind(_ error: any Error) -> String { "\(type(of: error)) \((error as NSError).code)" }

    nonisolated private static func describe(_ counts: [String: Int]) -> String {
        "[" + counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ") + "]"
    }
}
