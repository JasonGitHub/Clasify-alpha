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

    /// Signed in on the main menu, with the Apple Music words. Its main menu (card BN): Cover
    /// Flow, Playlists, Artists, Albums (row 3), Songs, Shuffle Songs, Settings.
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
        #expect(send(&s, .wheel(3), .select) == [.fetchTracks(token: 1, playlist: Playlist.libraryID)])
        send(&s, .tracksLoaded(token: 1, playlist: Playlist.libraryID, tracks: Self.songs))
        #expect(!s.top.loading && s.rows(for: s.top) == [.album(Self.album.id)])
        #expect(s.albumCovers.isEmpty && s.album(Self.album.id)?.name == "A")
        // Before the album's own read, it shows all its library songs, not only the favorited one.
        #expect(s.tracks(in: Self.album.id).map(\.id) == ["a1", "a2", "a3"])
        // Favorite Songs stays its own list: the first row of Playlists.
        send(&s, .menu, .wheel(-2), .select, .playlistsLoaded(token: 2, playlists: [focusInfo]))
        #expect(send(&s, .select) == [.fetchTracks(token: 3, playlist: Playlist.likedSongsID)])
        send(&s, .tracksLoaded(token: 3, playlist: Playlist.likedSongsID, tracks: Self.favorites))
        #expect(s.rows(for: s.top) == [.track("a1")])
        #expect(s.isLoaded(.albums) && s.tracks(in: Playlist.libraryID).count == 4)
    }

    @Test func aSongOfALibraryAlbumPlaysInTheAlbumNotTheLibrary() {
        var s = appleMenu()
        send(&s, .wheel(3), .select, .tracksLoaded(token: 1, playlist: Playlist.libraryID, tracks: Self.songs))
        #expect(send(&s, .select) == [.fetchTracks(token: 2, playlist: Self.album.id)])
        send(&s, .tracksLoaded(token: 2, playlist: Self.album.id, tracks: [Self.songs[1], Self.songs[0], Self.songs[2]]))
        let fx = send(&s, .select)
        #expect(fx.contains(.load(trackID: "a1", context: Self.album.id, autoplay: true, generation: 1)))
        #expect(s.current == TrackRef(playlist: Self.album.id, track: "a1"))
    }

    @Test func theLibraryIsNeverAPlaylistRowOrCount() {
        var s = appleMenu()
        send(&s, .wheel(3), .select, .tracksLoaded(token: 1, playlist: Playlist.libraryID, tracks: Self.songs), .menu)
        #expect(Playlist.isHidden(Playlist.libraryID) && Playlist.isHidden(Playlist.likedSongsID))
        #expect(Playlist.isHidden(Self.album.id) && !Playlist.isHidden("focus"))
        send(&s, .wheel(-2), .select, .playlistsLoaded(token: 2, playlists: [focusInfo]))
        #expect(s.rows(for: s.top) == [.playlist(Playlist.likedSongsID), .playlist("focus")])
        #expect(s.playlistCount == 1 && s.firstReadNames == ["Focus"])
        // The playlist list keeps the library read, so Albums opens without a read again.
        #expect(s.isLoaded(.albums) && s.tracks(in: Playlist.libraryID).count == 4)
        send(&s, .menu)
        #expect(send(&s, .wheel(2), .select, now: 150) == [])  // Albums
    }

    @Test func afterSetupOnAppleMusicTheMainMenuHasCoversAndShuffleSongsReadsAllSongsFirst() {
        var s = appleMenu()
        // Setup read only the library: Favorite Songs is not read yet.
        let covered = Self.songs.map { var t = $0; t.coverID = "c-\($0.id)"; return t }
        s.library = [Playlist(id: Playlist.libraryID, name: "", tracks: covered)]
        s.loadedTracks = [Playlist.libraryID]
        s.readAt[Playlist.libraryID] = 100
        s.artRow = .likedSongs; s.refreshArt()
        #expect(s.mainArt.count == 4 && Set(s.mainArt.map(\.id)) == ["a1", "a2", "a3", "lone"])
        // Shuffle Songs reads all library songs (Songs), then plays from them (change 278).
        let fx = send(&s, .wheel(5), .select)
        #expect(s.top.screen == .tracks(playlist: Playlist.songsID) && s.top.loading)
        #expect(fx.contains(.fetchTracks(token: s.top.token, playlist: Playlist.songsID)))
        send(&s, .tracksLoaded(token: s.top.token, playlist: Playlist.songsID, tracks: Self.favorites))
        #expect(s.current == TrackRef(playlist: Playlist.songsID, track: "a1") && s.shuffle && s.top.screen == .now)
    }

    @Test func aRelaunchOnAppleMusicKeepsTheLibraryThatTheMainMenuReadsForCovers() {
        var s = appleMenu()
        s.artReads = [:]
        send(&s, .wheel(3), now: 101)  // Albums
        let fx = send(&s, .tick, now: 102)  // the covers move to the row: read the albums list
        guard let token = s.artReads[Playlist.libraryID] else { Issue.record("no library read: \(fx)"); return }
        #expect(fx.contains(.readArtTracks(token: token, playlist: Playlist.libraryID)))
        let covered = Self.songs.map { var t = $0; t.coverID = "c-\($0.id)"; return t }
        send(&s, .artTracksRead(token: token, playlist: Playlist.libraryID, tracks: covered), now: 103)
        #expect(s.isLoaded(.albums) && s.tracks(in: Playlist.libraryID).count == 4 && !s.mainArt.isEmpty)
        #expect(s.rows(for: Frame(screen: .playlists)) == [.playlist(Playlist.likedSongsID)] && s.playlistCount == 0)
    }

    @Test func aLibraryRereadUpdatesTheReadAlbumsSoTheScreenMatchesTheQueue() {
        var s = appleMenu()
        send(&s, .wheel(3), .select, .tracksLoaded(token: 1, playlist: Playlist.libraryID, tracks: Self.songs))
        send(&s, .select, .tracksLoaded(token: 2, playlist: Self.album.id, tracks: [Self.songs[1], Self.songs[0], Self.songs[2]]))
        send(&s, .wheel(1), .select)  // a2 plays in the album
        #expect(s.current == TrackRef(playlist: Self.album.id, track: "a2"))
        send(&s, .menu)  // back to the album
        s.refreshing = [Playlist.libraryID]
        send(&s, .tracksRefreshed(playlist: Playlist.libraryID, tracks: [Self.songs[2], Self.songs[1], Self.songs[3]]))
        #expect(s.tracks(in: Self.album.id).map(\.id) == ["a1", "a3"] && s.rows(for: s.top) == [.track("a1"), .track("a3")])
        #expect(s.extraTracks.map(\.id) == ["a2"])  // Now Playing keeps the song that left
        #expect(s.isLoaded(.tracks(playlist: Self.album.id)))  // no read again: it is up to date
    }

    @Test func aCompilationStaysOneAlbumWithItsAlbumArtist() {
        var s = appleMenu()
        let mix = Album(id: "applemusic:album:123", name: "Mix", artist: "Various Artists")
        let songs = [
            Track(id: "m2", title: "m2", artist: "B", duration: 100, album: mix, number: 2),
            Track(id: "m1", title: "m1", artist: "A", duration: 100, album: mix, number: 1),
        ]
        send(&s, .wheel(3), .select, .tracksLoaded(token: 1, playlist: Playlist.libraryID, tracks: songs))
        #expect(s.rows(for: s.top) == [.album(mix.id)] && s.albums.map(\.artist) == ["Various Artists"])
        #expect(s.tracks(in: mix.id).map(\.id) == ["m1", "m2"])
        #expect(s.rows(for: Frame(screen: .playlists)) == [.playlist(Playlist.likedSongsID)] && s.playlistCount == 0)
    }

    @Test func aStaleAlbumsScreenRereadsTheLibrary() {
        var s = appleMenu()
        send(&s, .wheel(3), .select, .tracksLoaded(token: 1, playlist: Playlist.libraryID, tracks: Self.songs), .menu)
        #expect(send(&s, .select, now: 1000) == [.refreshTracks(playlist: Playlist.libraryID)])
        send(&s, .tracksRefreshed(playlist: Playlist.libraryID, tracks: Array(Self.songs.prefix(2))))
        #expect(s.tracks(in: Self.album.id).map(\.id) == ["a1", "a2"] && s.rows(for: s.top) == [.album(Self.album.id)])
    }
}
