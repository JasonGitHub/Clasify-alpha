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
    /// Apple Music's own words, such as "Favorite Songs" for the list of favorited songs.
    let words = LibraryWords.appleMusic
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
        let tracks = await read(playlist)
        if let tracks { onProgress?(playlist, tracks.count, tracks.count, Set(tracks.compactMap(\.album)).count) }
        return tracks
    }

    /// One list's read, shared while it runs and kept after it ends. A failed read leaves.
    private func read(_ id: String) async -> [ClasifyCore.Track]? {
        let read = trackReads[id] ?? Task { await Self.readTracks(id) }
        trackReads[id] = read
        let tracks = await read.value
        if tracks == nil { trackReads[id] = nil }
        return tracks
    }

    func rereadPlaylists() async -> [ClasifyCore.Playlist]? {
        listRead = nil
        await AppleMusicArt.shared.forget()
        return await playlists()
    }

    func reread(_ playlist: String) async -> [ClasifyCore.Track]? {
        trackReads[playlist] = nil
        await AppleMusicArt.shared.forget()
        if ClasifyCore.Album.isID(playlist) { AppleMusicReads.forgetAlbums(playlist) }
        return await tracks(of: playlist)
    }

    func track(_ id: String) async -> ClasifyCore.Track? {
        guard let song = await AppleMusicReads.song(id) else { return nil }
        return await AppleMusicReads.tracks([song]).first
    }

    func prefetch() async {
        async let list = playlists()
        async let liked = tracks(of: ClasifyCore.Playlist.likedSongsID)
        _ = await (list, liked)
    }

    /// The macOS prompt (card BM, change 258). macOS asks only once: after that, the answer
    /// comes back at once.
    func logIn() async -> LoginResult {
        await Self.result(MusicAuthorization.request())
    }

    /// The macOS access prompt can't be closed from here.
    func cancelLogIn() async {}

    /// A switch to Apple Music that macOS never asked about shows the prompt now (change 256).
    func restoreSession() async -> LoginResult {
        let status = MusicAuthorization.currentStatus
        return await Self.result(status == .notDetermined ? MusicAuthorization.request() : status)
    }

    /// No access: Access is off (258). No subscription: Not subscribed (259). A subscription
    /// check that fails lets the user in, so that a short network problem does not lock them
    /// out: the reads and plays then say what is wrong, and Settings stays reachable.
    private static func result(_ status: MusicAuthorization.Status) async -> LoginResult {
        guard status == .authorized else { return .denied }
        guard let subscription = try? await MusicSubscription.current else { return .ok }
        return subscription.canPlayCatalogContent ? .ok : .notPremium
    }

    /// Only the user can take MusicKit access away, in System Settings. This forgets the reads.
    func logOut() {
        listRead = nil
        trackReads = [:]
        AppleMusicReads.forgetAlbums()
        Task { await AppleMusicArt.shared.forget() }
    }

    // MARK: - Reads

    /// The library playlists, without their songs. "Favorite Songs" shows as its own row.
    private static func readPlaylists() async -> [ClasifyCore.Playlist]? {
        guard let items = try? await MusicLibraryRequest<MusicKit.Playlist>().response().items else { return nil }
        return items.filter { $0.name != AppleMusicReads.favoritesName }.map {
            ClasifyCore.Playlist(id: AppleMusicID.playlist($0.id), name: $0.name, tracks: [])
        }
    }

    /// The songs of one playlist, of "Favorite Songs" for `Playlist.likedSongsID`, or of an
    /// album (`applemusic:album:`). Music videos are left out, as the player leaves them out.
    private static func readTracks(_ id: String) async -> [ClasifyCore.Track]? {
        if ClasifyCore.Album.isID(id) {
            guard let read = await AppleMusicReads.album(id) else { return nil }
            // Every song carries the Albums screen's album, so that `Album.songs` and the
            // reducer find it, even a song whose own title or artist differs.
            return await AppleMusicReads.tracks(read.songs).map { track in
                var track = track
                track.album = read.album ?? track.album
                return track
            }
        }
        do {
            guard let playlist = try await AppleMusicReads.playlist(id) else {
                return id == ClasifyCore.Playlist.likedSongsID ? [] : nil  // no "Favorite Songs" yet: empty
            }
            guard let songs = await AppleMusicReads.songs(of: playlist) else { return nil }
            if id == ClasifyCore.Playlist.likedSongsID { AppleMusicAlbumProbe.runOnce(songs) }  // TEMP (CLA-103)
            return await AppleMusicReads.tracks(songs)
        } catch {
            return nil
        }
    }
}
