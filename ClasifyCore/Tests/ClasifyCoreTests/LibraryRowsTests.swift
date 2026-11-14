import Testing
@testable import ClasifyCore

/// Card BN: on a service whose words have `libraryRows` (Apple Music), the main menu has
/// Artists and Songs, and Playlists starts with the liked list. Spotify does not change.
@Suite struct LibraryRowsTests {
    static let ids = (a: "applemusic:artist:1", b: "applemusic:artist:2", c: "applemusic:artist:3")
    /// As the `Library` gives them: in its own order.
    static let artists = [
        Playlist(id: ids.a, name: "The Lowlights", tracks: []),
        Playlist(id: ids.b, name: "Low Orbit", tracks: []),
        Playlist(id: ids.c, name: "2Pac", tracks: []),
    ]

    func withRows() -> AppState {
        var s = mainMenu()
        send(&s, .libraryWords(.appleMusic))
        return s
    }

    @Test func appleMusicHasTheLibraryRowsAndSpotifyKeepsItsRows() {
        var s = mainMenu()
        let old: [Row] = [.coverFlow, .playlists, .albums, .likedSongs, .shuffleSongs, .settings]
        #expect(s.rows(for: s.top) == old && !LibraryWords.spotify.libraryRows)
        #expect(LibraryWords.appleMusic.libraryRows)
        s = withRows()
        #expect(s.rows(for: s.top) == [.coverFlow, .playlists, .artists, .albums, .songs, .shuffleSongs, .settings])
        s.library = [focusInfo]; s.playlistsLoaded = true
        #expect(s.rows(for: Frame(screen: .playlists)) == [.playlist(Playlist.likedSongsID), .playlist("focus")])
        #expect(s.listName(Playlist.likedSongsID) == "Favorite Songs" && s.playlistCount == 1)
    }

    @Test func artistsLoadOnceInNameOrder() {
        var s = withRows()
        #expect(send(&s, .wheel(2), .select) == [.fetchArtists(token: 1)])
        #expect(s.top.screen == .artists && s.top.loading && !s.isHalf(.artists))
        send(&s, .artistsLoaded(token: 9, artists: Self.artists))  // stale
        #expect(s.top.loading && s.artists.isEmpty)
        send(&s, .artistsLoaded(token: 1, artists: Self.artists))
        #expect(!s.top.loading && s.artistsLoaded)
        #expect(s.rows(for: s.top) == [.artist(Self.ids.c), .artist(Self.ids.b), .artist(Self.ids.a)])  // "The" left out
        send(&s, .menu)
        #expect(send(&s, .select, now: 1000) == [])  // read once a session: no read, no re-read
    }

    @Test func aFailedArtistsReadShowsTheErrorAndRetries() {
        var s = withRows()
        send(&s, .wheel(2), .select, .artistsLoaded(token: 1, artists: nil))
        #expect(s.top.error && !s.artistsLoaded)
        #expect(send(&s, .select) == [.fetchArtists(token: 2)])
    }

    @Test func anArtistOpensItsSongsAndPlaysThem() {
        var s = withRows()
        send(&s, .wheel(2), .select, .artistsLoaded(token: 1, artists: Self.artists))
        #expect(send(&s, .select) == [.fetchTracks(token: 2, playlist: Self.ids.c)])
        #expect(s.listName(Self.ids.c) == "2Pac")
        send(&s, .tracksLoaded(token: 2, playlist: Self.ids.c, tracks: focus.tracks))
        #expect(s.rows(for: s.top).count == 8 && !s.isHalf(s.top.screen))
        #expect(s.rows(for: Frame(screen: .playlists)) == [.playlist(Playlist.likedSongsID)] && s.playlistCount == 0)  // never a playlist
        let fx = send(&s, .select)
        #expect(fx.contains(.load(trackID: "f0", context: Self.ids.c, autoplay: true, generation: 1)))
    }

    @Test func songsOpensAllLibrarySongs() {
        var s = withRows()
        #expect(send(&s, .wheel(4), .select) == [.fetchTracks(token: 1, playlist: Playlist.songsID)])
        #expect(s.listName(Playlist.songsID) == "Songs" && Playlist.isHidden(Playlist.songsID))
        send(&s, .tracksLoaded(token: 1, playlist: Playlist.songsID, tracks: focus.tracks))
        #expect(s.rows(for: s.top).count == 8 && s.playlistCount == 0)
    }

    @Test func shuffleSongsShufflesAllLibrarySongs() {
        #expect(mainMenu().shuffleList == Playlist.likedSongsID)
        var s = withRows()
        #expect(s.shuffleList == Playlist.songsID)
        #expect(send(&s, .wheel(5), .select) == [.fetchTracks(token: 1, playlist: Playlist.songsID)])
        send(&s, .tracksLoaded(token: 1, playlist: Playlist.songsID, tracks: focus.tracks))
        #expect(s.current?.playlist == Playlist.songsID && s.shuffle && s.top.screen == .now)
        // Read once: a second Shuffle Songs plays at once.
        send(&s, .menu, .menu)
        #expect(send(&s, .select).contains { if case .load(_, Playlist.songsID, true, _) = $0 { true } else { false } })
    }

    @Test func aPlaylistRereadKeepsTheReadSongsAndArtistLists() {
        var s = withRows()
        send(&s, .wheel(4), .select, .tracksLoaded(token: 1, playlist: Playlist.songsID, tracks: focus.tracks), .menu)
        send(&s, .wheel(-2), .select, .artistsLoaded(token: 2, artists: Self.artists))
        send(&s, .select, .tracksLoaded(token: 3, playlist: Self.ids.c, tracks: focus.tracks))
        s.refreshing = [AppState.readKey(.playlists)]
        send(&s, .playlistsRefreshed([focusInfo]))
        #expect(s.isLoaded(.tracks(playlist: Playlist.songsID)) && s.isLoaded(.tracks(playlist: Self.ids.c)))
        #expect(s.tracks(in: Playlist.songsID).count == 8 && s.rows(for: s.top).count == 8)
        #expect(s.rows(for: Frame(screen: .playlists)) == [.playlist(Playlist.likedSongsID), .playlist("focus")] && s.playlistCount == 1)
    }

    @Test func aSignOutForgetsTheArtists() {
        var s = withRows()
        send(&s, .wheel(2), .select, .artistsLoaded(token: 1, artists: Self.artists))
        s.signedIn = true
        send(&s, .expire)
        #expect(s.artists.isEmpty && !s.artistsLoaded)
    }

    @Test func namesSortNumbersFirstThenAToZWithoutThe() {
        let names = ["The Lowlights", "Mara Kei", "Low Orbit", "2Pac", "the", "Arden Field"]
        #expect(names.sorted(by: Playlist.nameOrder) == ["2Pac", "Arden Field", "Low Orbit", "The Lowlights", "Mara Kei", "the"])
    }

    @Test func songsSortByTitleAndAnArtistByAlbumThenDiscAndTrack() {
        let a = Album(id: "applemusic:album:a", name: "The Beta"), b = Album(id: "applemusic:album:b", name: "Alpha")
        func t(_ id: String, _ title: String, _ album: Album, disc: Int? = nil, _ n: Int?) -> Track {
            Track(id: id, title: title, artist: "x", duration: 1, album: album, disc: disc, number: n)
        }
        let list = [t("1", "Zed", a, 2), t("2", "The Echo", a, 1), t("3", "9 Lives", b, nil), t("4", "Echo", b, 1), t("5", "Alpha", a, disc: 2, 1)]
        #expect(Track.titleOrder(list).map(\.id) == ["3", "5", "2", "4", "1"])  // equal titles keep their order
        #expect(Track.artistOrder(list).map(\.id) == ["4", "3", "2", "1", "5"])  // Alpha, then (The) Beta
    }
}
