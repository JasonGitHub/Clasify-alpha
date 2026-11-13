import ClasifyCore
import Foundation
// MusicKit's request and item types are not Sendable in the macOS 15 SDK. This file uses them
// only on the main actor.
@preconcurrency import MusicKit

/// The user's Apple Music library, read with MusicKit (CLA-103). Read-only: it never calls a
/// MusicKit API that changes the library. Reads stay in memory for the session; nothing goes
/// to disk. MusicKit has no sign-in of its own: "log in" asks macOS for MusicKit access.
@MainActor
final class AppleMusicLibrary: Library {
    /// Apple Music's own name for the list of favorited songs.
    let likedSongsName = "Favorite Songs"
    var onProgress: (@MainActor (_ playlist: String, _ done: Int, _ total: Int, _ albums: Int) -> Void)?

    /// The reads of this session, done or running. A failed read leaves.
    private var listRead: Task<[ClasifyCore.Playlist]?, Never>?
    private var trackReads: [String: Task<[ClasifyCore.Track]?, Never>] = [:]

    func playlists() async -> [ClasifyCore.Playlist]? {
        let read = listRead ?? Task { await Self.readPlaylists() }
        listRead = read
        let list = await read.value
        if list == nil { listRead = nil }
        return list
    }

    func tracks(of playlist: String) async -> [ClasifyCore.Track]? {
        let read = trackReads[playlist] ?? Task { await Self.readTracks(playlist) }
        trackReads[playlist] = read
        let tracks = await read.value
        if tracks == nil { trackReads[playlist] = nil }
        if let tracks { onProgress?(playlist, tracks.count, tracks.count, Set(tracks.compactMap(\.album)).count) }
        return tracks
    }

    func rereadPlaylists() async -> [ClasifyCore.Playlist]? {
        listRead = nil
        return await playlists()
    }

    func reread(_ playlist: String) async -> [ClasifyCore.Track]? {
        trackReads[playlist] = nil
        return await tracks(of: playlist)
    }

    func track(_ id: String) async -> ClasifyCore.Track? {
        guard let itemID = AppleMusicID.itemID(id, prefix: AppleMusicID.songPrefix) else { return nil }
        var request = MusicLibraryRequest<Song>()
        request.filter(matching: \.id, equalTo: itemID)
        if let song = try? await request.response().items.first { return Self.makeTrack(song) }
        let catalog = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: itemID)
        return (try? await catalog.response().items.first).map(Self.makeTrack)
    }

    func prefetch() async {
        async let list = playlists()
        async let liked = tracks(of: ClasifyCore.Playlist.likedSongsID)
        _ = await (list, liked)
    }

    func logIn() async -> LoginResult {
        await MusicAuthorization.request() == .authorized ? .ok : .failed
    }

    /// The macOS access prompt can't be closed from here.
    func cancelLogIn() async {}

    func restoreSession() async -> LoginResult {
        MusicAuthorization.currentStatus == .authorized ? .ok : .failed
    }

    /// Only the user can take MusicKit access away, in System Settings. This forgets the reads.
    func logOut() {
        listRead = nil
        trackReads = [:]
    }

    // MARK: - Reads

    /// The library playlists, without their songs. "Favorite Songs" shows as its own row.
    private static func readPlaylists() async -> [ClasifyCore.Playlist]? {
        guard let items = try? await MusicLibraryRequest<MusicKit.Playlist>().response().items else { return nil }
        return items.filter { $0.name != favoritesName }.map {
            ClasifyCore.Playlist(id: AppleMusicID.playlist($0.id), name: $0.name, tracks: [])
        }
    }

    /// The songs of one playlist, or of "Favorite Songs" for `Playlist.likedSongsID`. Music
    /// videos are left out, as the player leaves them out.
    private static func readTracks(_ id: String) async -> [ClasifyCore.Track]? {
        let playlist: MusicKit.Playlist?
        if id == ClasifyCore.Playlist.likedSongsID {
            // Not checked on a Mac: Apple Music keeps favorited songs in a library playlist
            // with this name. With no such playlist, the list is empty.
            guard let items = try? await MusicLibraryRequest<MusicKit.Playlist>().response().items else { return nil }
            guard let favorites = items.first(where: { $0.name == favoritesName }) else { return [] }
            playlist = favorites
        } else {
            guard let itemID = AppleMusicID.itemID(id, prefix: AppleMusicID.playlistPrefix) else { return nil }
            var request = MusicLibraryRequest<MusicKit.Playlist>()
            request.filter(matching: \.id, equalTo: itemID)
            playlist = try? await request.response().items.first
        }
        guard let playlist, let tracks = try? await playlist.with([.tracks]).tracks else { return nil }
        return tracks.compactMap { entry -> ClasifyCore.Track? in
            if case .song(let song) = entry { makeTrack(song) } else { nil }
        }
    }

    private static let favoritesName = "Favorite Songs"

    /// A store `Track` from a MusicKit song. The cover is the Artwork URL (PR 3 lets
    /// `ArtworkLoader` read it). The album ID is made from its title and artist, because a
    /// song has no album ID without one more read per song.
    private static func makeTrack(_ song: Song) -> ClasifyCore.Track {
        let album = song.albumTitle.map {
            ClasifyCore.Album(id: AppleMusicID.albumPrefix + $0 + "\u{1F}" + song.artistName, name: $0, artist: song.artistName)
        }
        return ClasifyCore.Track(
            id: AppleMusicID.song(song.id), title: song.title, artist: song.artistName,
            duration: song.duration ?? 0,
            coverID: song.artwork?.url(width: 300, height: 300)?.absoluteString,
            album: album, disc: song.discNumber, number: song.trackNumber,
            largeCoverID: song.artwork?.url(width: 640, height: 640)?.absoluteString
        )
    }
}
