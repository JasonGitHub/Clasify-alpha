import ClasifyCore
import Foundation
import iTunesLibrary

/// Local music (CLA-179): the songs and playlists of the Music app library, read with Apple's
/// iTunesLibrary framework, as `AppleMusicArt` reads its covers. Read-only: it never changes the
/// library. One read a session, kept in memory; nothing goes to disk. There is no login: an
/// empty library is empty lists, not a failed login. The lists come from `LocalCatalog`.
/// It is also the `LocalSource` of `LocalPlayer`. Not wired into the app yet.
@MainActor
final class LocalLibrary: Library, LocalSource {
    /// "On This Mac" (card CR).
    let words = LibraryWords.local
    var onProgress: (@MainActor (_ playlist: String, _ done: Int, _ total: Int, _ albums: Int) -> Void)?

    /// The library read of this session, done or running. A failed read leaves.
    private var read: Task<LocalCatalog?, Never>?

    /// The library, read once off the main actor, and shared while the read runs.
    private func catalog() async -> LocalCatalog? {
        let task = read ?? Task.detached(priority: .userInitiated) { LocalMusicRead.catalog() }
        read = task
        let catalog = await task.value
        if catalog == nil { read = nil }
        return catalog
    }

    func playlists() async -> [ClasifyCore.Playlist]? { await catalog()?.playlists }

    func tracks(of playlist: String) async -> [ClasifyCore.Track]? {
        guard let tracks = await catalog()?.tracks(of: playlist) else { return nil }
        onProgress?(playlist, tracks.count, tracks.count, Set(tracks.compactMap(\.album)).count)
        return tracks
    }

    func rereadPlaylists() async -> [ClasifyCore.Playlist]? {
        await forget()
        return await playlists()
    }

    func reread(_ playlist: String) async -> [ClasifyCore.Track]? {
        await forget()
        return await tracks(of: playlist)
    }

    func artists() async -> [ClasifyCore.Playlist]? { await catalog()?.artists }

    func track(_ id: String) async -> ClasifyCore.Track? { await catalog()?.track(id) }

    func prefetch() async { _ = await catalog() }

    /// `LocalSource`: the song files that `LocalPlayer` plays, from the same read.
    func items(context: String?, track: String) async -> [LocalItem]? {
        await catalog()?.items(context: context, track: track)
    }

    /// No account: the library is there or it is empty. `page` is for Spotify.
    func logIn(page: String?) async -> LoginResult { .ok }

    func cancelLogIn() async {}

    func restoreSession() async -> LoginResult { .ok }

    /// Forgets the read.
    func logOut() { read = nil }

    /// A new read next time, and new covers: `AppleMusicArt` opens the library again too.
    private func forget() async {
        read = nil
        await AppleMusicArt.shared.forget()
    }
}

/// One read of the Music app library. `ITLibrary` and its items stay inside `catalog()`, which
/// runs off the main actor; only plain values (`LocalCatalog`) leave it.
enum LocalMusicRead {
    /// nil when the library can't be opened.
    nonisolated static func catalog() -> LocalCatalog? {
        guard let library = try? ITLibrary(apiVersion: "1.0") else { return nil }
        let items = library.allMediaItems.map(item)
        let lists = library.allPlaylists.filter(isUserList).map {
            LocalList(persistentID: $0.persistentID.uint64Value, name: $0.name, items: $0.items.map { $0.persistentID.uint64Value })
        }
        return LocalCatalog(songs: items, lists: lists)
    }

    /// A playlist that the person made: not the whole library, not one of the Music app's own
    /// lists (Music, Movies, Purchased and so on), not a folder, and shown in the Music app.
    nonisolated static func isUserList(_ list: ITLibPlaylist) -> Bool {
        !list.isPrimary && list.distinguishedKind == .kindNone && list.kind != .folder && list.isVisible
    }

    /// The plain values of one library item. It has a file URL only when it can play: a song
    /// (not a video), not protected (Apple Music downloads, old FairPlay files), and a file on
    /// this Mac (not in the cloud only).
    nonisolated static func item(_ item: ITLibMediaItem) -> LocalSong {
        let album = item.album
        let playable = item.mediaKind == .kindSong && !item.isVideo && !item.isDRMProtected
            && item.locationType == .file
        return LocalSong(
            persistentID: item.persistentID.uint64Value, title: item.title, artist: item.artist?.name ?? "",
            album: album.title ?? "", albumID: album.persistentID.uint64Value, albumArtist: album.albumArtist,
            disc: album.discNumber > 0 ? album.discNumber : nil, number: item.trackNumber > 0 ? item.trackNumber : nil,
            duration: Double(item.totalTime) / 1000, hasCover: item.hasArtworkAvailable, url: playable ? item.location : nil)
    }
}
