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
        if let found = foundCatalogIDs[song.id] { return found }  // from an ISRC read
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
        let catalog = await catalogCovers(songs)
        return songs.map { track($0, cover: catalog[$0.id]) }
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
            let filled = aat.replacingOccurrences(of: "{w}", with: "\(size)").replacingOccurrences(of: "{h}", with: "\(size)")
                .replacingOccurrences(of: "{c}", with: "bb").replacingOccurrences(of: "{f}", with: "jpg")
            return CoverURL.url(for: filled)?.absoluteString
        }
        guard let small = at(300) else { return nil }
        return Cover(small: small, large: at(640) ?? small)
    }

    /// Catalog IDs that the ISRC reads found, by library song ID. The play parameters have no
    /// catalog ID on macOS 27 (build 188), so `catalogID(_:)` also looks here.
    private static var foundCatalogIDs: [MusicItemID: String] = [:]

    /// Covers from the catalog for library songs with no usable cover of their own, found by
    /// ISRC, 100 per read. A failed read leaves those songs without a cover; the list is never
    /// lost. The catalog IDs found also serve the whole-album read (#215).
    private static func catalogCovers(_ songs: [Song]) async -> [MusicItemID: Cover] {
        var byISRC: [String: [MusicItemID]] = [:]
        for song in songs where cover(song.artwork) == nil {
            if let isrc = song.isrc, !isrc.isEmpty { byISRC[isrc, default: []].append(song.id) }
        }
        var covers: [MusicItemID: Cover] = [:]
        var stats = CoverStats()
        let isrcs = Array(byISRC.keys)
        for start in stride(from: 0, to: isrcs.count, by: 100) {
            let batch = Array(isrcs[start..<min(start + 100, isrcs.count)])
            let request = MusicCatalogResourceRequest<Song>(matching: \.isrc, memberOf: batch)
            stats.batches += 1
            let items: MusicItemCollection<Song>
            do { items = try await request.response().items } catch {
                stats.errors.append("\(type(of: error)) \((error as NSError).code)")  // TEMP: type and code only
                continue
            }
            stats.returned += items.count
            for item in items {
                guard let isrc = item.isrc, let mine = byISRC[isrc] else { continue }
                stats.matched += 1
                for id in mine {
                    foundCatalogIDs[id] = foundCatalogIDs[id] ?? item.id.rawValue
                    if covers[id] == nil, let found = cover(item.artwork) { covers[id] = found }
                }
            }
        }
        stats.isrcs = isrcs.count
        stats.found = covers.count
        logCovers(songs, stats)
        return covers
    }

    /// TEMP (builds 183 and 188, no Apple Music cover shows): counts of what the cover reads
    /// saw. No title, no ID, no query value: query key NAMES only.
    private struct CoverStats {
        var isrcs = 0, batches = 0, returned = 0, matched = 0, found = 0, errors: [String] = []
    }

    private static func logCovers(_ songs: [Song], _ stats: CoverStats) {
        var own = 0, aat = 0, aatPasses = 0, fat = 0, withISRC = 0, cloudIDs = 0, keys = Set<String>()
        var aatShape = "none", fatScheme = "none"  // the first failing aat, and the first fat: no path, no ID
        for song in songs {
            if song.isrc?.isEmpty == false { withISRC += 1 }
            if song.id.rawValue.hasPrefix("i.") { cloudIDs += 1 }  // the shape of a cloud library ID
            guard let url = song.artwork?.url(width: 300, height: 300) else { continue }
            if CoverURL.url(for: url.absoluteString) != nil { own += 1; continue }
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            for item in items { keys.insert(item.name) }
            if let value = items.first(where: { $0.name == "aat" })?.value {
                aat += 1
                if cover(song.artwork) != nil { aatPasses += 1 }
                else if aatShape == "none" {
                    let parts = URLComponents(string: value)
                    aatShape = "scheme \(parts?.scheme ?? "none") host \(parts?.host ?? "none") "
                        + "{w} \(value.contains("{w}") ? "yes" : "no") / \(value.hasPrefix("/") ? "yes" : "no") length \(value.count)"
                }
            }
            if let value = items.first(where: { $0.name == "fat" })?.value {
                fat += 1
                if fatScheme == "none" { fatScheme = URLComponents(string: value)?.scheme ?? "no scheme" }
            }
        }
        let names = keys.subtracting(["aat", "fat"]).sorted().joined(separator: " ")
        let threw = stats.errors.isEmpty ? "no" : stats.errors.joined(separator: ", ")
        timing.notice("""
            apple covers (TEMP): songs \(songs.count, privacy: .public), own passes \(own, privacy: .public), \
            aat \(aat, privacy: .public), aat passes \(aatPasses, privacy: .public), \
            first failing aat [\(aatShape, privacy: .public)], fat \(fat, privacy: .public) \
            (scheme \(fatScheme, privacy: .public)), \
            other keys [\(names, privacy: .public)], isrc \(withISRC, privacy: .public), \
            i. ids \(cloudIDs, privacy: .public), isrc asked \(stats.isrcs, privacy: .public), \
            batches \(stats.batches, privacy: .public), returned \(stats.returned, privacy: .public), \
            matched \(stats.matched, privacy: .public), threw \(threw, privacy: .public), \
            catalog found \(stats.found, privacy: .public)
            """)
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
