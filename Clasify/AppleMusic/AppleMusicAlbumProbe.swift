// TEMP (CLA-103, Jason OK 19:19 JST 11-14): a hidden probe of ways to read a whole Apple Music
// album, because an album in Albums and Cover Flow shows only its favorited songs on macOS 27.
// Delete this file and its one call in `AppleMusicLibrary.readTracks` after the next build's log.
// Read-only. It shows nothing, keeps nothing and writes nothing. Counts only: no titles, no IDs.
import ClasifyCore
import Foundation
@preconcurrency import MusicKit
import os

private let timing = Logger(subsystem: "app.clasify.Clasify", category: "timing")

@MainActor
enum AppleMusicAlbumProbe {
    private static var ran = false

    /// Runs once a launch, on at most 5 albums of "Favorite Songs" with the fewest songs.
    static func runOnce(_ favorites: [Song]) {
        guard !ran, !favorites.isEmpty else { return }
        ran = true
        let albums = Dictionary(grouping: favorites.filter { $0.albumTitle != nil }) { albumKey($0.albumTitle ?? "", $0.artistName) }
        let picks = albums.values.sorted { $0.count < $1.count }.prefix(5).compactMap { group -> (song: Song, own: Int)? in
            group.first.map { (song: $0, own: group.count) }
        }
        Task { await Self.run(picks) }
    }

    private static func run(_ picks: [(song: Song, own: Int)]) async {
        let api = await apiAlbums()
        timing.notice("apple albums probe (TEMP): api library albums \(api.summary, privacy: .public)")
        for (song, own) in picks {
            var parts = ["own \(own)"]
            // Today: the song's library album, read with its tracks.
            let libraryAlbum = try? await song.with([.albums]).albums?.first
            parts.append("library " + (await count { libraryAlbum }))
            // 1a. The same library album, asked again with the catalog as the preferred source.
            parts.append("w1 album catalog " + (await count { try await libraryAlbum?.with([.tracks], preferredSource: .catalog) }))
            // 1b. The song's albums, asked with the catalog as the preferred source.
            parts.append("w1 song catalog " + (await count { try await song.with([.albums], preferredSource: .catalog).albums?.first }))
            // 2. The Apple Music API library album with its catalog album: by ID, else by name.
            let key = albumKey(song.albumTitle ?? "", song.artistName)
            let join = libraryAlbum.flatMap { api.byID[$0.id.rawValue] }.map { ("id", $0) } ?? api.byKey[key].map { ("name", $0) }
            if let join {
                let (how, catalogID) = join
                parts.append("w2 join \(how) catalog \(catalogID == nil ? "no" : "yes") " + (await count {
                    guard let catalogID else { return nil }
                    return try await MusicCatalogResourceRequest<MusicKit.Album>(matching: \.id, equalTo: MusicItemID(catalogID)).response().items.first
                }))
            } else {
                parts.append("w2 join no")
            }
            // 4. A catalog search by title and artist; the hit on the same album and artist.
            parts.append("w4 search " + (await count {
                var request = MusicCatalogSearchRequest(term: "\(song.title) \(song.artistName)", types: [Song.self])
                request.limit = 10
                let hit = try await request.response().songs.first { albumKey($0.albumTitle ?? "", $0.artistName) == key }
                return try await hit?.with([.albums]).albums?.first
            }))
            timing.notice("apple albums probe (TEMP): \(parts.joined(separator: ", "), privacy: .public)")
        }
    }

    private static func albumKey(_ title: String, _ artist: String) -> String { LibraryKey.of(title: title, artist: artist, album: nil) }

    /// The song count of the album that `read` gives, and ms: "N (ms M)", "none (ms M)" or
    /// "threw <type> <code> (ms M)".
    private static func count(_ read: () async throws -> MusicKit.Album?) async -> String {
        let start = ContinuousClock.now
        let result: String
        do {
            if let album = try await read() { result = (await AppleMusicReads.songs(of: album)).map { "\($0.count)" } ?? "tracks failed" }
            else { result = "none" }
        } catch { result = "threw \(type(of: error)) \((error as NSError).code)" }
        return "\(result) (ms \(Int((ContinuousClock.now - start) / .milliseconds(1))))"
    }

    /// 2. The Apple Music API list of library albums with their catalog albums, at most 10 pages.
    private static func apiAlbums() async -> (byID: [String: String?], byKey: [String: String?], summary: String) {
        let start = ContinuousClock.now
        var byID: [String: String?] = [:], byKey: [String: String?] = [:], albums = 0, withCatalog = 0, pages = 0
        var threw = "no"
        for offset in stride(from: 0, to: 1000, by: 100) {
            guard let url = URL(string: "https://api.music.apple.com/v1/me/library/albums?limit=100&offset=\(offset)&include=catalog") else { break }
            pages += 1
            do {
                let data = try await MusicDataRequest(urlRequest: URLRequest(url: url)).response().data
                let page = try JSONDecoder().decode(Page.self, from: data)
                for item in page.data {
                    albums += 1
                    let catalogID = item.relationships?.catalog?.data?.first?.id
                    if catalogID != nil { withCatalog += 1 }
                    byID[item.id] = catalogID
                    if let name = item.attributes?.name, let artist = item.attributes?.artistName { byKey[albumKey(name, artist)] = catalogID }
                }
                if page.data.count < 100 || page.next == nil { break }
            } catch {
                threw = "\(type(of: error)) \((error as NSError).code)"
                break
            }
        }
        let ms = Int((ContinuousClock.now - start) / .milliseconds(1))
        return (byID, byKey, "\(albums), with catalog \(withCatalog), pages \(pages), threw \(threw), ms \(ms)")
    }

    // The parts of the API's JSON that this file reads.
    private struct Page: Decodable { let data: [Item]; let next: String? }
    private struct Item: Decodable { let id: String; let attributes: Attributes?; let relationships: Relationships? }
    private struct Attributes: Decodable { let name: String?; let artistName: String? }
    private struct Relationships: Decodable { let catalog: Related? }
    private struct Related: Decodable { let data: [Item]? }
}
