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
        guard var batch = try? await playlist.with([.tracks]).tracks else { return nil }
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
    /// (`applemusic:album:`). An album plays its songs from "Favorite Songs" in the order that
    /// the Albums screen shows them (`Album.songs`). nil when the context can't be read.
    static func songs(for context: String) async -> [Song]? {
        let albumContext = context.hasPrefix(AppleMusicID.albumPrefix)
        let id = albumContext ? ClasifyCore.Playlist.likedSongsID : context
        guard let playlist = try? await Self.playlist(id), let songs = await Self.songs(of: playlist) else { return nil }
        guard albumContext else { return songs }
        let byID = Dictionary(songs.map { (AppleMusicID.song($0.id), $0) }, uniquingKeysWith: { first, _ in first })
        return ClasifyCore.Album.songs(context, in: songs.map { Self.track($0) }).compactMap { byID[$0.id] }
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
        let ids = Array(catalogIDs.keys)
        for start in stride(from: 0, to: ids.count, by: 100) {
            let batch = Array(ids[start..<min(start + 100, ids.count)])
            let request = MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: batch)
            guard let items = try? await request.response().items else { continue }
            for item in items {
                guard let art = item.artwork, isWeb(art) else { continue }
                for id in catalogIDs[item.id] ?? [] { covers[id] = art }  // each library copy of the song
            }
        }
        return covers
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
