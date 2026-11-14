// MusicKit's request types are not Sendable in the macOS 15 SDK. Only `page(_:)` uses one, and
// it returns plain Data.
import ClasifyCore
import Foundation
@preconcurrency import MusicKit
import os

/// TEMP (Apple Music covers, build 191): counts only, never a title or an ID.
private let timing = Logger(subsystem: "app.clasify.Clasify", category: "timing")

/// Covers from the Apple Music API's list of the user's library songs (CLA-103). On macOS 27
/// MusicKit gives a library song only a `musicKit://` artwork URL, no catalog ID and no ISRC
/// (build 191). The API list gives each song an artwork template, and its catalog song. Its
/// IDs can differ from MusicKit's, so a song is matched by ID, else by title, artist and album
/// (`LibraryKey`). Read-only: GET requests only. Not checked on a Mac.
extension AppleMusicReads {
    /// One song of the API list.
    struct APISong: Sendable {
        let templates: [String]  // its library artwork, then its catalog song's artwork
        let catalogID: String?

        func cover(_ size: Int) -> String? { templates.lazy.compactMap { CoverURL.apple(template: $0, size: size) }.first }
    }

    /// The API list by song ID and by `LibraryKey`, with TEMP counts of what it held.
    struct APILibrary: Sendable {
        var byID: [String: APISong] = [:], byKey: [String: APISong] = [:]
        var songs = 0, withArtwork = 0, passes = 0, withCatalog = 0, pages = 0, ms = 0
        var firstFailing = "none", errors: [String] = []
    }

    /// The API list, read once a session. `forgetAlbums()` forgets it.
    static var apiLibrary: Task<APILibrary, Never>?

    /// How long a song list waits for the API list. After that the list shows with the
    /// blue-grey squares, and the read goes on for the lists read later.
    static let apiWait = Duration.seconds(5)

    /// Starts the API list read, if it is not running or done. The playlists read calls it,
    /// so the list is often ready before the first song list.
    @discardableResult static func startAPILibrary() -> Task<APILibrary, Never> {
        let read = apiLibrary ?? Task { await Self.readAPILibrary() }
        apiLibrary = read
        return read
    }

    /// Covers for library songs from the API list. It also keeps the catalog IDs found, for
    /// the whole-album read and the queue keys.
    static func libraryAPICovers(_ songs: [Song]) async -> [MusicItemID: Cover] {
        guard !songs.isEmpty else { return [:] }
        guard let library = await value(of: startAPILibrary(), within: apiWait) else {
            timing.notice("apple covers (TEMP): asked \(songs.count, privacy: .public), api list not ready after 5 s")
            return [:]
        }
        var covers: [MusicItemID: Cover] = [:], byID = 0, byName = 0
        for song in songs {
            let found: APISong
            if let hit = library.byID[song.id.rawValue] { found = hit; byID += 1 }
            else if let hit = library.byKey[LibraryKey.of(title: song.title, artist: song.artistName, album: song.albumTitle)] {
                found = hit; byName += 1
            } else { continue }
            if let id = found.catalogID, foundCatalogIDs[song.id] == nil { foundCatalogIDs[song.id] = id }
            if let small = found.cover(300) { covers[song.id] = Cover(small: small, large: found.cover(640) ?? small) }
        }
        let threw = library.errors.isEmpty ? "no" : library.errors.joined(separator: ", ")
        timing.notice("""
            apple covers (TEMP): asked \(songs.count, privacy: .public), api songs \(library.songs, privacy: .public), \
            with artwork \(library.withArtwork, privacy: .public), passes CoverURL \(library.passes, privacy: .public), \
            first failing [\(library.firstFailing, privacy: .public)], catalog included \(library.withCatalog, privacy: .public), \
            matched by id \(byID, privacy: .public), matched by name \(byName, privacy: .public), \
            covers \(covers.count, privacy: .public), pages \(library.pages, privacy: .public), \
            ms \(library.ms, privacy: .public), threw \(threw, privacy: .public)
            """)
        return covers
    }

    /// The read's result, or nil when it does not end within `wait`. The read is not stopped.
    private static func value(of read: Task<APILibrary, Never>, within wait: Duration) async -> APILibrary? {
        await withCheckedContinuation { (done: CheckedContinuation<APILibrary?, Never>) in
            let once = Once(done)
            Task { @MainActor in once.resume(await read.value) }
            Task { @MainActor in try? await Task.sleep(for: wait); once.resume(nil) }
        }
    }

    /// Resumes a continuation once: the first of the read and the timer wins.
    @MainActor private final class Once {
        private var done: CheckedContinuation<APILibrary?, Never>?
        nonisolated init(_ done: CheckedContinuation<APILibrary?, Never>) { self.done = done }
        func resume(_ value: APILibrary?) { done?.resume(returning: value); done = nil }
    }

    /// Reads the whole API list: the first page, then 8 pages at a time until a page is short.
    private static func readAPILibrary() async -> APILibrary {
        let start = ContinuousClock.now
        var library = APILibrary()
        var offsets = [0]
        while !offsets.isEmpty {
            let pages = await withTaskGroup(of: (Int, Data?, String?).self) { group in
                for offset in offsets { group.addTask { await Self.page(offset) } }
                return await group.reduce(into: [(Int, Data?, String?)]()) { $0.append($1) }.sorted { $0.0 < $1.0 }
            }
            var full = true
            for (_, data, error) in pages {
                library.pages += 1
                if let error { library.errors.append(error); full = false; continue }
                guard let data, let page = try? JSONDecoder().decode(Page.self, from: data) else {
                    library.errors.append("decode"); full = false; continue
                }
                for item in page.data { add(item, to: &library) }
                if page.data.count < 100 || page.next == nil { full = false }
            }
            let next = (offsets.last ?? 0) + 100
            offsets = full ? Array(stride(from: next, to: next + 800, by: 100)) : []
        }
        library.ms = Int((ContinuousClock.now - start) / .milliseconds(1))
        return library
    }

    private static func add(_ item: Item, to library: inout APILibrary) {
        let catalog = item.relationships?.catalog?.data?.first
        let templates = [item.attributes?.artwork?.url, catalog?.attributes?.artwork?.url].compactMap { $0 }
        let song = APISong(templates: templates, catalogID: catalog?.id ?? item.attributes?.playParams?.catalogId)
        library.songs += 1
        if !templates.isEmpty { library.withArtwork += 1 }
        if catalog != nil { library.withCatalog += 1 }
        if song.cover(300) != nil { library.passes += 1 }
        else if let template = templates.first, library.firstFailing == "none" {
            let parts = URLComponents(string: template)  // scheme and host only: no path, no ID
            library.firstFailing = "scheme \(parts?.scheme ?? "none") host \(parts?.host ?? "none")"
        }
        if library.byID[item.id] == nil { library.byID[item.id] = song }
        if let a = item.attributes, let title = a.name, let artist = a.artistName {
            let key = LibraryKey.of(title: title, artist: artist, album: a.albumName)
            if library.byKey[key] == nil { library.byKey[key] = song }
        }
    }

    /// One page of 100 library songs with their catalog songs: the data, or the error's type
    /// and code (TEMP).
    nonisolated private static func page(_ offset: Int) async -> (Int, Data?, String?) {
        var parts = URLComponents(string: "https://api.music.apple.com/v1/me/library/songs")
        parts?.queryItems = [.init(name: "limit", value: "100"), .init(name: "offset", value: "\(offset)"),
                             .init(name: "include", value: "catalog")]
        guard let url = parts?.url else { return (offset, nil, "url") }
        do { return (offset, try await MusicDataRequest(urlRequest: URLRequest(url: url)).response().data, nil) } catch {
            return (offset, nil, "\(type(of: error)) \((error as NSError).code)")
        }
    }

    // The parts of the API's JSON that this file reads.
    private struct Page: Decodable { let data: [Item]; let next: String? }
    struct Item: Decodable { let id: String; let attributes: Attributes?; let relationships: Relationships? }
    struct Attributes: Decodable {
        let name: String?, artistName: String?, albumName: String?, artwork: Art?, playParams: Params?
    }
    struct Art: Decodable { let url: String? }
    struct Params: Decodable { let catalogId: String? }
    struct Relationships: Decodable { let catalog: Related? }
    struct Related: Decodable { let data: [Item]? }
}
