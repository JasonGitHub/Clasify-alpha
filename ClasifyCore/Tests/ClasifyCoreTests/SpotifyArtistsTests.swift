import Testing
@testable import ClasifyCore

/// CLA-195: Spotify's Artists row, made from Liked Songs. A song plays in the context of the
/// artist whose row was opened, from that song.
@Suite struct SpotifyArtistsTests {
    static let (mara, low, duo) = ("spotify:artist:mara", "spotify:artist:low", "spotify:artist:duo")
    static func song(_ id: String, _ title: String, album: String, _ artists: [ArtistRef], number: Int) -> Track {
        Track(id: "spotify:track:\(id)", title: title, artist: artists.map(\.name).joined(separator: ", "),
              duration: 200, album: Album(id: "spotify:album:\(album)", name: album), number: number, artists: artists)
    }
    static let maraRef = ArtistRef(id: mara, name: "Mara, Kei")  // a comma in a name stays one artist
    static let lowRef = ArtistRef(id: low, name: "Low Orbit")
    /// A song by Mara with Low Orbit, then two by Mara, then one by Low Orbit, as Liked Songs gives them.
    static let liked = [
        song("1", "Together", album: "Beta", [maraRef, lowRef], number: 2),
        song("2", "Second", album: "Alpha", [maraRef], number: 2),
        song("3", "First", album: "Alpha", [maraRef], number: 1),
        song("4", "Orbit", album: "Gamma", [lowRef], number: 1),
        song("5", "No ID", album: "Gamma", [ArtistRef(id: "", name: "Ghost")], number: 2),
    ]

    @Test func theMainMenuHasArtistsAfterPlaylists() {
        let s = mainMenu()
        #expect(s.rows(for: s.top) == [.coverFlow, .playlists, .artists, .albums, .likedSongs, .shuffleSongs, .settings])
        #expect(!s.words.libraryRows && s.shuffleList == Playlist.likedSongsID)  // no Songs row, Shuffle Songs as before
    }

    @Test func eachArtistShowsOnceAndASongShowsUnderEachOfItsArtists() {
        let list = SpotifyArtists.list(Self.liked)
        #expect(list == [Playlist(id: Self.mara, name: "Mara, Kei", tracks: []), Playlist(id: Self.low, name: "Low Orbit", tracks: [])])
        #expect(SpotifyArtists.songs(of: Self.mara, in: Self.liked).map(\.title) == ["First", "Second", "Together"])  // album, then number
        #expect(SpotifyArtists.songs(of: Self.low, in: Self.liked).map(\.title) == ["Together", "Orbit"])
        #expect(SpotifyArtists.songs(of: Self.duo, in: Self.liked).isEmpty)
    }

    /// Opens Artists, then Low Orbit (the first in name order), with its songs read.
    func lowOrbit() -> AppState {
        var s = mainMenu()
        #expect(send(&s, .wheel(2), .select) == [.fetchArtists(token: 1)])
        send(&s, .artistsLoaded(token: 1, artists: SpotifyArtists.list(Self.liked)))
        #expect(s.rows(for: s.top) == [.artist(Self.low), .artist(Self.mara)])
        #expect(send(&s, .select) == [.fetchTracks(token: 2, playlist: Self.low)])
        #expect(s.listName(Self.low) == "Low Orbit")
        send(&s, .tracksLoaded(token: 2, playlist: Self.low, tracks: SpotifyArtists.songs(of: Self.low, in: Self.liked)))
        return s
    }

    @Test func aSongWithTwoArtistsPlaysInTheOpenedArtistsContext() {
        var s = lowOrbit()
        #expect(s.rows(for: s.top) == [.track("spotify:track:1"), .track("spotify:track:4")])
        let fx = send(&s, .select)
        // "Together" is Mara's first, but the row came from Low Orbit: its context, from this song.
        #expect(fx.contains(.load(trackID: "spotify:track:1", context: Self.low, autoplay: true, generation: 1)))
        #expect(s.current == TrackRef(playlist: Self.low, track: "spotify:track:1") && s.top.screen == .now)
        #expect(ResumePlan.canLoad(Self.low))  // Play after a quit loads it again
    }

    @Test func whenSpotifyPlaysAnotherSongTheAppShowsThatSong() {
        var s = lowOrbit()
        send(&s, .select, .position(0, generation: 1))
        // Spotify starts the artist's Popular songs at another song, one that is not liked.
        let fx = send(&s, .trackChanged("spotify:track:pop", playing: true, generation: 1))
        #expect(s.current == TrackRef(playlist: Self.low, track: "spotify:track:pop") && s.isPlaying)
        #expect(fx == [.readTrack("spotify:track:pop")])  // its title and artist are read
        let pop = Track(id: "spotify:track:pop", title: "Hit", artist: "Low Orbit", duration: 180)
        send(&s, .trackRead("spotify:track:pop", pop))
        #expect(s.track(s.current!)?.title == "Hit")
        send(&s, .trackChanged("spotify:track:4", playing: true, generation: 1))  // then a liked one
        #expect(s.track(s.current!)?.title == "Orbit")
    }

    @Test func whenSpotifyPlaysNothingTheLoadFailsWithItsMessage() {
        var s = lowOrbit()
        send(&s, .select)
        #expect(send(&s, .loadFailed("That didn’t play. Try again", generation: 1)) == [])
        #expect(s.current == nil && !s.isPlaying && s.toast == "That didn’t play. Try again")
        #expect(s.top.screen == .tracks(playlist: Self.low))  // back to the artist's songs, no empty Now Playing
    }

    @Test func searchReadsTheSpotifyArtistsToo() {
        var s = mainMenu()
        s.searchOn = true
        s.library = [Playlist(id: Playlist.likedSongsID, name: "Liked Songs", tracks: Self.liked)]
        s.loadedTracks = [Playlist.likedSongsID]; s.playlistsLoaded = true
        s.artReads = [:]  // the main menu's cover read, not part of this test
        #expect(send(&s, .wheel(6), .select) == [.refreshArtists])
        #expect(s.top.screen == .search)
        send(&s, .artistsRefreshed(SpotifyArtists.list(Self.liked)))
        #expect(s.artistsLoaded && s.artists.map(\.id) == [Self.low, Self.mara])
    }
}

/// CLA-195: the bridge's two artist texts, joined with U+001F, become the song's artists.
@Test func theBridgeArtistTextsBecomeArtistRefs() {
    let refs = ArtistRef.list(uris: "spotify:artist:a\u{1F}\u{1F}spotify:artist:c", names: "Mara, Kei\u{1F}No ID\u{1F}Low")
    #expect(refs == [ArtistRef(id: "spotify:artist:a", name: "Mara, Kei"), ArtistRef(id: "spotify:artist:c", name: "Low")])
    #expect(ArtistRef.list(uris: nil, names: nil).isEmpty && ArtistRef.list(uris: "", names: "").isEmpty)
}
