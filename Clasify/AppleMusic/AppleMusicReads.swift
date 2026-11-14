// MusicKit's request and item types are not Sendable in the macOS 15 SDK. This file uses them
// only on the main actor.
import ClasifyCore
import Foundation
@preconcurrency import MusicKit
import os

/// TEMP (Apple Music covers, build 183): counts only, never a title or an ID.
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
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json["catalogId"] as? String
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

    /// All songs of an album, in its order, with every batch read. nil when a read fails.
    static func songs(of album: MusicKit.Album) async -> [Song]? {
        await songs(in: try? await album.with([.tracks]).tracks)
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
    /// (`applemusic:album:`, all its songs: `album(_:)`). nil when the context can't be read.
    static func songs(for context: String) async -> [Song]? {
        guard context.hasPrefix(AppleMusicID.albumPrefix) else {
            guard let playlist = try? await Self.playlist(context) else { return nil }
            return await Self.songs(of: playlist)
        }
        return await album(context)?.songs
    }

    /// All songs of the album that the Albums screen names `albumID` (its title and the song
    /// artist), in disc and track order, as Spotify shows a whole album (CLA-46). The album is
    /// found through one of its songs in "Favorite Songs". Its library album holds only the
    /// songs in the library, so the catalog album is read too, and the longer list is used
    /// (the library one if the same). When neither can be read, the album's songs from
    /// "Favorite Songs" stay. `album` is the Albums screen's own album, for the tracks to carry.
    /// nil when "Favorite Songs" can't be read. Not checked on a Mac: that MusicKit gives a
    /// library song's albums, and the whole catalog album.
    static func album(_ albumID: String) async -> (songs: [Song], album: ClasifyCore.Album?)? {
        if let read = albums[albumID] { return read }
        let read = await readAlbum(albumID)
        if let read { albums[albumID] = read }
        return read
    }

    /// The album reads of this session, so that the library's list and the player's queue are
    /// the same songs with the same IDs. `forgetAlbums` clears them.
    private static var albums: [String: (songs: [Song], album: ClasifyCore.Album?)] = [:]

    /// Forgets one album read (nil: all), so that the next read asks MusicKit again.
    static func forgetAlbums(_ albumID: String? = nil) {
        if let albumID { albums[albumID] = nil } else { albums = [:] }
    }

    private static func readAlbum(_ albumID: String) async -> (songs: [Song], album: ClasifyCore.Album?)? {
        let list: MusicKit.Playlist?
        do { list = try await playlist(ClasifyCore.Playlist.likedSongsID) } catch { return nil }
        guard let list else { return ([], nil) }  // no "Favorite Songs" yet: no albums
        guard let favorites = await songs(of: list) else { return nil }
        let byID = Dictionary(favorites.map { (AppleMusicID.song($0.id), $0) }, uniquingKeysWith: { first, _ in first })
        let own = ClasifyCore.Album.songs(albumID, in: favorites.map { track($0) })
        guard let first = own.first, let pick = byID[first.id] else { return ([], nil) }
        let library = await librarySongs(ofAlbumOf: pick) ?? []
        let catalog = await catalogSongs(ofAlbumOf: pick) ?? []
        let whole = catalog.count > library.count ? catalog : library
        guard whole.count > own.count else { return (own.compactMap { byID[$0.id] }, first.album) }
        // A song of "Favorite Songs" stays its library copy, with the ID that the store knows
        // from there, also inside a catalog album.
        let mine = Dictionary(favorites.compactMap { song in catalogID(song).map { ($0, song) } }, uniquingKeysWith: { first, _ in first })
        return (inOrder(whole).map { mine[$0.id.rawValue] ?? $0 }, first.album)
    }

    /// The songs of a song's library album.
    private static func librarySongs(ofAlbumOf song: Song) async -> [Song]? {
        guard let album = try? await song.with([.albums]).albums?.first else { return nil }
        return await songs(of: album)
    }

    /// The songs of a library song's album in the catalog. nil for a song not in the catalog.
    private static func catalogSongs(ofAlbumOf song: Song) async -> [Song]? {
        guard let id = catalogID(song) else { return nil }
        var request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(id))
        request.properties = [.albums]
        guard let album = try? await request.response().items.first?.albums?.first else { return nil }
        return await songs(of: album)
    }

    /// Songs in disc and track order, as `Album.songs` sorts them. Songs with no number keep
    /// their order, after the numbered ones of their disc.
    private static func inOrder(_ songs: [Song]) -> [Song] {
        let order = { (e: (offset: Int, element: Song)) in (e.element.discNumber ?? 1, e.element.trackNumber ?? Int.max, e.offset) }
        return songs.enumerated().sorted { order($0) < order($1) }.map(\.element)
    }

    /// Store `Track`s from MusicKit songs, with covers that `ArtworkLoader` can load.
    static func tracks(_ songs: [Song]) async -> [ClasifyCore.Track] {
        let covers = await catalogCovers(songs)
        return songs.map { track($0, cover: covers[$0.id]) }
    }

    /// The catalog songs' Artwork for library songs whose own Artwork URL is not https. A
    /// library song's Artwork gives a `musicKit://` URL (build 177: no covers; not checked on a
    /// Mac), which only MusicKit's own view can draw, and `CoverURL` rightly refuses it. The
    /// same song from the catalog gives an https URL on `*.mzstatic.com`. One read for each 100
    /// songs, not one per album. A failed read leaves those songs without a cover.
    private static func catalogCovers(_ songs: [Song]) async -> [MusicItemID: Artwork] {
        var catalogIDs: [MusicItemID: [MusicItemID]] = [:]  // catalog ID to its library songs' IDs
        for song in songs where !isWeb(song.artwork) {
            if let id = catalogID(song) { catalogIDs[MusicItemID(id), default: []].append(song.id) }
        }
        var covers: [MusicItemID: Artwork] = [:]
        var batches = 0, returned = 0, otherID = 0, errors: [String] = []
        let ids = Array(catalogIDs.keys)
        for start in stride(from: 0, to: ids.count, by: 100) {
            let batch = Array(ids[start..<min(start + 100, ids.count)])
            let request = MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: batch)
            batches += 1
            let items: MusicItemCollection<Song>
            do { items = try await request.response().items } catch {
                errors.append("\(type(of: error)) \((error as NSError).code)")  // TEMP: type and code only
                continue
            }
            returned += items.count
            for item in items {
                if catalogIDs[item.id] == nil { otherID += 1 }  // TEMP: came back under an ID not asked
                guard let art = item.artwork, isWeb(art) else { continue }
                for id in catalogIDs[item.id] ?? [] { covers[id] = art }  // each library copy of the song
            }
        }
        logCovers(
            songs, catalogIDs: catalogIDs.count, batches: batches, returned: returned, otherID: otherID,
            errors: errors, found: covers.count)
        return covers
    }

    /// TEMP (build 183, no Apple Music cover shows): where the covers get lost, as counts. No
    /// title and no ID; for addresses only one scheme.
    private static func logCovers(
        _ songs: [Song], catalogIDs: Int, batches: Int, returned: Int, otherID: Int, errors: [String], found: Int
    ) {
        var passes = 0, otherHost = 0, notHTTPS = 0, none = 0, scheme = "none"
        for song in songs {
            guard let url = song.artwork?.url(width: 300, height: 300) else { none += 1; continue }
            if CoverURL.url(for: url.absoluteString) != nil { passes += 1 }
            else if url.scheme?.lowercased() == "https" { otherHost += 1 }
            else { notHTTPS += 1; if scheme == "none" { scheme = url.scheme ?? "empty" } }
        }
        let threw = errors.isEmpty ? "no" : errors.joined(separator: ", ")
        timing.notice("""
            apple covers (TEMP): songs \(songs.count, privacy: .public), own passes \(passes, privacy: .public), \
            own https other host \(otherHost, privacy: .public), own not https \(notHTTPS, privacy: .public) \
            (scheme \(scheme, privacy: .public)), no artwork \(none, privacy: .public), \
            catalog ids \(catalogIDs, privacy: .public), batches \(batches, privacy: .public), \
            returned \(returned, privacy: .public), other id \(otherID, privacy: .public), \
            threw \(threw, privacy: .public), found \(found, privacy: .public)
            """)
    }

    private static func isWeb(_ art: Artwork?) -> Bool {
        art?.url(width: 300, height: 300)?.scheme?.lowercased() == "https"
    }

    /// A store `Track` from a MusicKit song. The cover is the song's own Artwork URL, or else
    /// `cover`, the catalog's Artwork for it. The album ID is made from its title and artist,
    /// because a song has no album ID without one more read per song.
    static func track(_ song: Song, cover: Artwork? = nil) -> ClasifyCore.Track {
        let art = isWeb(song.artwork) ? song.artwork : cover ?? song.artwork
        let album = song.albumTitle.map {
            ClasifyCore.Album(id: AppleMusicID.albumPrefix + $0 + "\u{1F}" + song.artistName, name: $0, artist: song.artistName)
        }
        return ClasifyCore.Track(
            id: AppleMusicID.song(song.id), title: song.title, artist: song.artistName,
            duration: song.duration ?? 0,
            coverID: art?.url(width: 300, height: 300)?.absoluteString,
            album: album, disc: song.discNumber, number: song.trackNumber,
            largeCoverID: art?.url(width: 640, height: 640)?.absoluteString
        )
    }
}
