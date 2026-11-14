import AppKit
import ClasifyCore
import CoreGraphics
import iTunesLibrary

/// Apple Music library covers from Apple's iTunesLibrary framework (CLA-103). On macOS 27
/// MusicKit gives a library song only a `musicKit://` artwork URL that no request can load
/// (build 191), but the library item has the image (build 194). Read-only. The library opens
/// once a session, off the main actor; `forget()` drops it, so the next read opens it again.
/// Images stay in memory: `ArtworkLoader` asks for one at the side it shows, never larger.
actor AppleMusicArt {
    static let shared = AppleMusicArt()

    /// An image from the library. CGImage is immutable, so it is safe to hand to another
    /// actor; the wrapper only says so to the compiler.
    struct Image: @unchecked Sendable { let cgImage: CGImage }

    private var library: ITLibrary?
    private var items: [UInt64: ITLibMediaItem] = [:]
    private var byKey: [String: UInt64] = [:]

    func forget() { library = nil; items = [:]; byKey = [:] }

    /// For each song (its MusicKit ID and `LibraryKey`), the persistent ID of its library item
    /// when that item has artwork: by the song's own ID, else by title, artist and album.
    func match(_ songs: [(id: String, key: String)]) -> (found: [String: UInt64], byID: Int, byName: Int) {
        open()
        var found: [String: UInt64] = [:], byID = 0, byName = 0
        for song in songs {
            let item: ITLibMediaItem
            if let pid = LibraryCover.persistentID(musicKitID: song.id), let hit = items[pid] { item = hit; byID += 1 }
            else if let pid = byKey[song.key], let hit = items[pid] { item = hit; byName += 1 }
            else { continue }
            if item.hasArtworkAvailable { found[song.id] = item.persistentID.uint64Value }
        }
        return (found, byID, byName)
    }

    /// The item's artwork, scaled down to fill a square of `side` pixels. nil when it has none.
    func image(_ persistentID: UInt64, side: Int) -> Image? {
        open()
        guard let item = items[persistentID], item.hasArtworkAvailable,
              let source = item.artwork?.image?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(
                  data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let scale = Double(side) / Double(min(source.width, source.height))
        let width = Double(source.width) * scale, height = Double(source.height) * scale
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: (Double(side) - width) / 2, y: (Double(side) - height) / 2, width: width, height: height))
        return context.makeImage().map { Image(cgImage: $0) }
    }

    /// Opens the library once. A failed open is tried again on the next call.
    private func open() {
        guard library == nil, let opened = try? ITLibrary(apiVersion: "1.0") else { return }
        library = opened
        for item in opened.allMediaItems {
            let pid = item.persistentID.uint64Value
            items[pid] = item
            let key = LibraryKey.of(title: item.title, artist: item.artist?.name ?? "", album: item.album.title)
            if byKey[key] == nil { byKey[key] = pid }
        }
    }
}
