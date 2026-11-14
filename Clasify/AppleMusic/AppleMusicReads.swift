// MusicKit's request and item types are not Sendable in the macOS 15 SDK. This file uses them
// only on the main actor.
import ClasifyCore
import Foundation
@preconcurrency import MusicKit
import os

/// TEMP (Apple Music covers, CLA-103): counts only, never a title or an ID.
private let timing = Logger(subsystem: "app.clasify.Clasify", category: "timing")

/// MusicKit reads that the player and the library share, so the two always agree (CLA-103).
/// Read-only: nothing here changes the library.
@MainActor
enum AppleMusicReads {
    /// A song from the user's library, or else from the catalog. nil for an unknown ID.
    static func song(_ id: String) async -> Song? {
        guard let itemID = AppleMusicID.itemID(id, prefix: AppleMusicID.songPrefix) else { return nil }
        var library = MusicLibraryRequest<Song>()
        library.filter(matching: \.id, equalTo: itemID)
        if let song = try? await library.response().items.first { return song }
        let catalog = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: itemID)
        return try? await catalog.response().items.first
    }

    /// The catalog ID of a library song, or nil. MusicKit keeps it only in the play
    /// parameters, which are opaque but Codable. Their JSON has "catalogId", as in the Apple
    /// Music API (not checked on a Mac).
    static func catalogID(_ song: Song) -> String? {
        guard let params = song.playParameters, let data = try? JSONEncoder().encode(params),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["catalogId"] as? String
        else { return foundCatalogIDs[song.id] }  // else from an ISRC read, if one matched its album title
        return id
    }

    /// Apple Music's name for the library playlist of favorited songs.
    static let favoritesName = "Favorite Songs"

    /// A library playlist by its store ID, or "Favorite Songs" for `Playlist.likedSongsID`.
    /// nil when there is no such playlist. Throws when the read fails.
    static func playlist(_ id: String) async throws -> MusicKit.Playlist? {
        if id == ClasifyCore.Playlist.likedSongsID {
            // Not checked on a Mac: Apple Music keeps favorited songs in a library playlist
            // with this name.
            let items = try await MusicLibraryRequest<MusicKit.Playlist>().response().items
            return items.first { $0.name == favoritesName }
        }
        guard let itemID = AppleMusicID.itemID(id, prefix: AppleMusicID.playlistPrefix) else { return nil }
        var request = MusicLibraryRequest<MusicKit.Playlist>()
        request.filter(matching: \.id, equalTo: itemID)
        return try await request.response().items.first
    }

    /// All songs of a playlist, in order, with every batch read. Music videos are left out.
    /// nil when a read fails, so a long list is never cut short.
    static func songs(of playlist: MusicKit.Playlist) async -> [Song]? {
        await songs(in: try? await playlist.with([.tracks]).tracks)
    }

    /// The songs of a track list, with every batch read. Music videos are left out.
    private static func songs(in first: MusicItemCollection<MusicKit.Track>?) async -> [Song]? {
        guard var batch = first else { return nil }
        var tracks = Array(batch)
        while batch.hasNextBatch {
            guard let next = try? await batch.nextBatch() else { return nil }
            tracks += next
            batch = next
        }
        return tracks.compactMap { track -> Song? in
            if case .song(let song) = track { song } else { nil }
        }
    }

    /// The songs that a store context plays: a playlist, "Favorite Songs", or an album
    /// (`applemusic:album:`, its library songs: `album(_:)`). nil when the context can't be read.
    static func songs(for context: String) async -> [Song]? {
        guard context.hasPrefix(AppleMusicID.albumPrefix) else {
            guard let playlist = try? await Self.playlist(context) else { return nil }
            return await Self.songs(of: playlist)
        }
        return await album(context)
    }

    /// The songs of the album that the Albums screen names `albumID` (its title and the song
    /// artist), from the library's own songs in disc and track order: the songs that the user
    /// has, as on an iPod (Jason, 11-14). nil when the library can't be read. The library
    /// list, the album screen and the player's queue are the same songs with the same IDs.
    static func album(_ albumID: String) async -> [Song]? {
        guard let songs = await librarySongs() else { return nil }
        return inOrder(songs.filter { track($0).album?.id == albumID })
    }

    /// All songs of the library, read once in this session and shared while the read runs.
    /// A failed read leaves. `forgetLibrary` clears it.
    static func librarySongs() async -> [Song]? {
        let read = libraryRead ?? Task { await readLibrary() }
        libraryRead = read
        let songs = await read.value
        if songs == nil { libraryRead = nil }
        return songs
    }

    private static var libraryRead: Task<[Song]?, Never>?

    /// Forgets the library read, so that the next read asks MusicKit again.
    static func forgetLibrary() { libraryRead = nil }

    /// Every library song, with every batch read, so the list is never cut short. nil when a
    /// read fails. Not checked on a Mac: the speed with a large library.
    private static func readLibrary() async -> [Song]? {
        let start = ContinuousClock.now
        guard var batch = try? await MusicLibraryRequest<Song>().response().items else { return nil }
        var songs = Array(batch)
        while batch.hasNextBatch {
            guard let next = try? await batch.nextBatch() else { return nil }
            songs += next
            batch = next
        }
        let ms = Int((ContinuousClock.now - start) / .milliseconds(1))
        let grouped = Set(songs.compactMap { track($0).album?.id }).count
        let albums = await libraryAlbumCount()
        timing.notice("""
            apple library (TEMP): songs \(songs.count, privacy: .public), albums grouped \(grouped, privacy: .public), \
            library albums \(albums.map { String($0) } ?? "failed", privacy: .public), ms \(ms, privacy: .public)
            """)
        return songs
    }

    /// TEMP: how many albums MusicKit's own library list has, to compare with our grouping.
    private static func libraryAlbumCount() async -> Int? {
        guard var batch = try? await MusicLibraryRequest<MusicKit.Album>().response().items else { return nil }
        var count = batch.count
        while batch.hasNextBatch {
            guard let next = try? await batch.nextBatch() else { return nil }
            count += next.count
            batch = next
        }
        return count
    }

    /// Songs in disc and track order, as `Album.songs` sorts them. Songs with no number keep
    /// their order, after the numbered ones of their disc.
    private static func inOrder(_ songs: [Song]) -> [Song] {
        let order = { (e: (offset: Int, element: Song)) in (e.element.discNumber ?? 1, e.element.trackNumber ?? Int.max, e.offset) }
        return songs.enumerated().sorted { order($0) < order($1) }.map(\.element)
    }

    /// Store `Track`s from MusicKit songs, with covers that `ArtworkLoader` can load.
    static func tracks(_ songs: [Song]) async -> [ClasifyCore.Track] {
        // Own cover first, then the catalog reads, then the iTunesLibrary item (macOS 27).
        var covers = await catalogCovers(songs)
        let missing = songs.filter { cover($0.artwork) == nil && covers[$0.id] == nil }
        let more = await libraryCovers(missing)
        covers.merge(more) { first, _ in first }
        return songs.map { track($0, cover: covers[$0.id]) }
    }

    /// Covers from Apple's iTunesLibrary framework (`AppleMusicArt`) for library songs with no
    /// usable cover: opaque `LibraryCover` IDs that `ArtworkLoader` reads in memory.
    private static func libraryCovers(_ songs: [Song]) async -> [MusicItemID: Cover] {
        guard !songs.isEmpty else { return [:] }
        let start = ContinuousClock.now
        let keys = songs.map { (id: $0.id.rawValue, key: LibraryKey.of(title: $0.title, artist: $0.artistName, album: $0.albumTitle)) }
        let match = await AppleMusicArt.shared.match(keys)
        var covers: [MusicItemID: Cover] = [:]
        for song in songs {
            guard let pid = match.found[song.id.rawValue] else { continue }
            covers[song.id] = Cover(
                small: LibraryCover.coverID(persistentID: pid, side: 300), large: LibraryCover.coverID(persistentID: pid, side: 640))
        }
        let ms = Int((ContinuousClock.now - start) / .milliseconds(1))
        timing.notice("""
            apple covers (TEMP): asked \(songs.count, privacy: .public), matched by id \(match.byID, privacy: .public), \
            by name \(match.byName, privacy: .public), with image \(covers.count, privacy: .public), ms \(ms, privacy: .public)
            """)
        return covers
    }

    /// A cover's two addresses, for `Track.coverID` and `Track.largeCoverID`.
    struct Cover { let small: String, large: String }

    /// The cover addresses of an Artwork that `CoverURL` allows, or nil:
    /// - its own URL, when that is https on `*.mzstatic.com` (catalog songs);
    /// - for a library song, whose URL is `musicKit://artwork/...` (build 188, macOS 27), the
    ///   https address in its `aat` query item, with any size template filled. Its `fat` item
    ///   (a local file) is never used: covers come only from Apple's image server.
    static func cover(_ art: Artwork?) -> Cover? {
        guard let art else { return nil }
        func at(_ size: Int) -> String? {
            guard let url = art.url(width: size, height: size) else { return nil }
            if CoverURL.url(for: url.absoluteString) != nil { return url.absoluteString }
            guard let aat = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "aat" })?.value else { return nil }
            return CoverURL.apple(template: aat, size: size)
        }
        guard let small = at(300) else { return nil }
        return Cover(small: small, large: at(640) ?? small)
    }

    /// Catalog IDs that the ISRC reads found, by library song ID. The
    /// play parameters have no catalog ID on macOS 27 (build 188), so `catalogID(_:)` also looks here.
    private static var foundCatalogIDs: [MusicItemID: String] = [:]

    /// Covers from the catalog for library songs with no usable cover of their own: by their
    /// catalog ID when the play parameters have one, else by ISRC, 100 per read. An ISRC can
    /// name the same recording on several releases, so the release with the song's own album
    /// title wins, and only that one gives the song a catalog ID (`catalogID(_:)`). A
    /// failed read leaves those songs without a cover; the list is never lost.
    private static func catalogCovers(_ songs: [Song]) async -> [MusicItemID: Cover] {
        var byID: [String: [Song]] = [:], byISRC: [String: [Song]] = [:]
        for song in songs where cover(song.artwork) == nil {
            if let id = catalogID(song) { byID[id, default: []].append(song) }
            else if let isrc = song.isrc, !isrc.isEmpty { byISRC[isrc, default: []].append(song) }
        }
        var covers: [MusicItemID: Cover] = [:]
        let ids = await catalogRead(Array(byID.keys)) {
            MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: $0.map { MusicItemID($0) })
        }
        for item in ids {
            for song in byID[item.id.rawValue] ?? [] where covers[song.id] == nil { covers[song.id] = cover(item.artwork) }
        }
        let byRecording = await catalogRead(Array(byISRC.keys)) {
            MusicCatalogResourceRequest<Song>(matching: \.isrc, memberOf: $0)
        }
        for (isrc, mine) in byISRC {
            let found = byRecording.filter { $0.isrc == isrc }
            guard let any = found.first else { continue }
            for song in mine {
                let same = found.first { $0.albumTitle?.lowercased() == song.albumTitle?.lowercased() }
                if let same, foundCatalogIDs[song.id] == nil { foundCatalogIDs[song.id] = same.id.rawValue }
                if covers[song.id] == nil { covers[song.id] = cover((same ?? any).artwork) }
            }
        }
        return covers
    }

    /// Catalog songs for `values`, 100 per read. A read that throws is skipped.
    private static func catalogRead(
        _ values: [String], _ request: ([String]) -> MusicCatalogResourceRequest<Song>
    ) async -> [Song] {
        var songs: [Song] = []
        for start in stride(from: 0, to: values.count, by: 100) {
            songs += (try? await request(Array(values[start..<min(start + 100, values.count)])).response().items) ?? []
        }
        return songs
    }

    /// A store `Track` from a MusicKit song. The cover is the song's own (`cover(_:)`), or else
    /// `cover`, found in the catalog. The album ID is made from its title and artist, because a
    /// song has no album ID without one more read per song.
    static func track(_ song: Song, cover catalog: Cover? = nil) -> ClasifyCore.Track {
        let art = Self.cover(song.artwork) ?? catalog
        let album = song.albumTitle.map {
            ClasifyCore.Album(id: AppleMusicID.albumPrefix + $0 + "\u{1F}" + song.artistName, name: $0, artist: song.artistName)
        }
        return ClasifyCore.Track(
            id: AppleMusicID.song(song.id), title: song.title, artist: song.artistName,
            duration: song.duration ?? 0, coverID: art?.small,
            album: album, disc: song.discNumber, number: song.trackNumber, largeCoverID: art?.large
        )
    }
}
