// MusicKit's request and item types are not Sendable in the macOS 15 SDK. This file uses them
// only on the main actor.
import ClasifyCore
import Foundation
@preconcurrency import MusicKit

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
        else { return foundCatalogIDs[song.id] }  // else from an ISRC read, if one matched its album
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
        if let albumID { albums[albumID] = nil } else { albums = [:]; apiLibrary = nil }
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
        AppleMusicCoverProbe.runOnce(songs)  // TEMP (CLA-103): delete with AppleMusicCoverProbe.swift
        // Own cover first, then the catalog reads, then the API library list (macOS 27).
        var covers = await catalogCovers(songs)
        let missing = songs.filter { cover($0.artwork) == nil && covers[$0.id] == nil }
        let more = await libraryAPICovers(missing)
        covers.merge(more) { first, _ in first }
        return songs.map { track($0, cover: covers[$0.id]) }
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

    /// Catalog IDs that the ISRC reads and the API library list found, by library song ID. The
    /// play parameters have no catalog ID on macOS 27 (build 188), so `catalogID(_:)` also looks here.
    static var foundCatalogIDs: [MusicItemID: String] = [:]

    /// Covers from the catalog for library songs with no usable cover of their own: by their
    /// catalog ID when the play parameters have one, else by ISRC, 100 per read. An ISRC can
    /// name the same recording on several releases, so the release with the song's own album
    /// title wins, and only that one gives a catalog ID for the whole-album read (#215). A
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
