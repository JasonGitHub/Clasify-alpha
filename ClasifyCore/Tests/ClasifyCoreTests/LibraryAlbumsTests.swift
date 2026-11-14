import Testing
@testable import ClasifyCore

/// On Apple Music, Albums and Cover Flow group the whole library (`Playlist.libraryID`), as on
/// an iPod. On Spotify they group Liked Songs. The reducer only follows `words.albumsList`.
@Suite struct LibraryAlbumsTests {
    static let album = Album(id: "applemusic:album:a", name: "A", artist: "x")
    /// The library: three songs of album A (one favorited) and one song with no album.
    static let songs: [Track] = [
        Track(id: "a2", title: "a2", artist: "x", duration: 100, album: album, number: 2),
        Track(id: "a1", title: "a1", artist: "x", duration: 100, album: album, number: 1),
        Track(id: "a3", title: "a3", artist: "x", duration: 100, album: album, number: 3),
        Track(id: "lone", title: "lone", artist: "x", duration: 100),
    ]
    static let favorites = [songs[1]]

    /// Signed in on the main menu, with the Apple Music words.
    func appleMenu() -> AppState {
        var s = mainMenu()
        send(&s, .libraryWords(.appleMusic))
        return s
    }

    @Test func eachServiceNamesItsAlbumsList() {
        #expect(LibraryWords.spotify.albumsList == Playlist.likedSongsID)
        #expect(LibraryWords.appleMusic.albumsList == Playlist.libraryID)
        var s = mainMenu()
        #expect(s.albumsList == Playlist.likedSongsID && s.readKey(.albums) == Playlist.likedSongsID)
        send(&s, .libraryWords(.appleMusic))
        #expect(s.albumsList == Playlist.libraryID)
        for screen in [Screen.albums, .coverFlow, .yourMusic] { #expect(s.readKey(screen) == Playlist.libraryID) }
        #expect(s.readKey(.tracks(playlist: "p")) == "p" && s.readKey(.playlists) == "")
        #expect(AppState.readKey(.albums) == Playlist.likedSongsID)  // the static default stays Spotify's
    }

    @Test func albumsOnAppleMusicReadTheWholeLibrary() {
        var s = appleMenu()
        #expect(send(&s, .wheel(2), .select) == [.fetchTracks(token: 1, playlist: Playlist.libraryID)])
        send(&s, .tracksLoaded(token: 1, playlist: Playlist.libraryID, tracks: Self.songs))
        #expect(!s.top.loading && s.rows(for: s.top) == [.album(Self.album.id)])
        #expect(s.albumCovers.isEmpty && s.album(Self.album.id)?.name == "A")
        // Before the album's own read, it shows all its library songs, not only the favorited one.
        #expect(s.tracks(in: Self.album.id).map(\.id) == ["a1", "a2", "a3"])
        // Favorite Songs stays its own list.
        send(&s, .menu)
        #expect(send(&s, .wheel(1), .select) == [.fetchTracks(token: 2, playlist: Playlist.likedSongsID)])
        send(&s, .tracksLoaded(token: 2, playlist: Playlist.likedSongsID, tracks: Self.favorites))
        #expect(s.rows(for: s.top) == [.track("a1")])
        #expect(s.isLoaded(.albums) && s.tracks(in: Playlist.libraryID).count == 4)
    }

    @Test func aSongOfALibraryAlbumPlaysInTheAlbumNotTheLibrary() {
        var s = appleMenu()
        send(&s, .wheel(2), .select, .tracksLoaded(token: 1, playlist: Playlist.libraryID, tracks: Self.songs))
        #expect(send(&s, .select) == [.fetchTracks(token: 2, playlist: Self.album.id)])
        send(&s, .tracksLoaded(token: 2, playlist: Self.album.id, tracks: [Self.songs[1], Self.songs[0], Self.songs[2]]))
        let fx = send(&s, .select)
        #expect(fx.contains(.load(trackID: "a1", context: Self.album.id, autoplay: true, generation: 1)))
        #expect(s.current == TrackRef(playlist: Self.album.id, track: "a1"))
    }

    @Test func theLibraryIsNeverAPlaylistRowOrCount() {
        var s = appleMenu()
        send(&s, .wheel(2), .select, .tracksLoaded(token: 1, playlist: Playlist.libraryID, tracks: Self.songs), .menu)
        #expect(Playlist.isHidden(Playlist.libraryID) && Playlist.isHidden(Playlist.likedSongsID))
        #expect(Playlist.isHidden(Self.album.id) && !Playlist.isHidden("focus"))
        send(&s, .wheel(-1), .select, .playlistsLoaded(token: 2, playlists: [focusInfo]))
        #expect(s.rows(for: s.top) == [.playlist("focus")])
        #expect(s.playlistCount == 1 && s.firstReadNames == ["Focus"])
        // The playlist list keeps the library read, so Albums opens without a read again.
        #expect(s.isLoaded(.albums) && s.tracks(in: Playlist.libraryID).count == 4)
        send(&s, .menu)
        #expect(send(&s, .wheel(1), .select, now: 150) == [])  // Albums
    }

    @Test func aStaleAlbumsScreenRereadsTheLibrary() {
        var s = appleMenu()
        send(&s, .wheel(2), .select, .tracksLoaded(token: 1, playlist: Playlist.libraryID, tracks: Self.songs), .menu)
        #expect(send(&s, .select, now: 1000) == [.refreshTracks(playlist: Playlist.libraryID)])
        send(&s, .tracksRefreshed(playlist: Playlist.libraryID, tracks: Array(Self.songs.prefix(2))))
        #expect(s.tracks(in: Self.album.id).map(\.id) == ["a1", "a2"] && s.rows(for: s.top) == [.album(Self.album.id)])
    }
}
