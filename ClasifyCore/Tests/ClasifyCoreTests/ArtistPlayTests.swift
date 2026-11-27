import Testing
@testable import ClasifyCore

/// CLA-199: Play on a selected row of the Artists list starts that artist, from the first song
/// its screen shows, as Play on a playlist row does (CLA-173). Select still opens its songs.
@Suite struct ArtistPlayTests {
    static let (low, mara) = (SpotifyArtistsTests.low, SpotifyArtistsTests.mara)
    static let liked = SpotifyArtistsTests.liked
    /// Low Orbit's Popular songs, as the Spotify `Library` gives them with `artists.popular` on.
    static let popular = [
        Track(id: "spotify:track:hit", title: "Hit", artist: "Low Orbit", duration: 180),
        Track(id: "spotify:track:4", title: "Orbit", artist: "Low Orbit", duration: 200),
    ]

    /// Spotify's Artists list, with Low Orbit (the first in name order) selected. Token 1 read it.
    func onSpotifyArtists() -> AppState {
        var s = mainMenu()
        send(&s, .wheel(2), .select, .artistsLoaded(token: 1, artists: SpotifyArtists.list(Self.liked)))
        #expect(s.top.screen == .artists && s.rows(for: s.top)[s.top.sel] == .artist(Self.low))
        return s
    }

    /// What a press on the first song of the artist's screen gives, from the same state.
    func firstSongPress(_ s: AppState, _ id: String, _ songs: [Track]) -> [Effect] {
        var picked = s
        send(&picked, .select, .tracksLoaded(token: picked.tok + 1, playlist: id, tracks: songs))
        return send(&picked, .select).filter(\.isNotTrack)
    }

    @Test func spotifyStartsThePopularSongsAsAPressOnTheFirstOne() {
        var s = onSpotifyArtists()
        let press = firstSongPress(s, Self.low, Self.popular)
        #expect(send(&s, .play) == [.fetchTracks(token: 2, playlist: Self.low)])
        #expect(s.top.screen == .tracks(playlist: Self.low) && s.top.loading && s.startToken == 2)
        let fx = send(&s, .tracksLoaded(token: 2, playlist: Self.low, tracks: Self.popular)).filter(\.isNotTrack)
        #expect(fx.contains(.load(trackID: "spotify:track:hit", context: Self.low, autoplay: true, generation: 1)))
        #expect(fx == press)  // the same artist context path as the first song's row
        #expect(s.top.screen == .now && s.current == TrackRef(playlist: Self.low, track: "spotify:track:hit"))
        // MENU goes back to Artists, on the same row.
        #expect(s.stack.map(\.screen) == [.main, .artists, .now])
        send(&s, .menu)
        #expect(s.top.screen == .artists && s.rows(for: s.top)[s.top.sel] == .artist(Self.low))
    }

    @Test func spotifyWithPopularOffStartsTheLikedSongs() {
        // With `artists.popular` off, the Library gives the artist's liked songs: the first of them starts.
        var s = onSpotifyArtists()
        let songs = SpotifyArtists.songs(of: Self.low, in: Self.liked)
        let press = firstSongPress(s, Self.low, songs)
        send(&s, .play)
        let fx = send(&s, .tracksLoaded(token: 2, playlist: Self.low, tracks: songs)).filter(\.isNotTrack)
        #expect(fx == press && s.current == TrackRef(playlist: Self.low, track: "spotify:track:1"))
    }

    @Test func anArtistThatWasReadStartsAtOnceOverArtists() {
        var s = onSpotifyArtists()
        send(&s, .select, .tracksLoaded(token: 2, playlist: Self.low, tracks: Self.popular), .menu)
        #expect(send(&s, .play).filter(\.isNotTrack).contains(.load(trackID: "spotify:track:hit", context: Self.low, autoplay: true, generation: 1)))
        #expect(s.top.screen == .now && s.stack.map(\.screen) == [.main, .artists, .now])
        // A second Play on Now Playing pauses, as for a playlist.
        #expect(send(&s, .play) == [.pause])
    }

    @Test func selectStillOpensTheArtistsSongs() {
        var s = onSpotifyArtists()
        #expect(send(&s, .select) == [.fetchTracks(token: 2, playlist: Self.low)] && s.startToken == nil)
        send(&s, .tracksLoaded(token: 2, playlist: Self.low, tracks: Self.popular))
        #expect(s.top.screen == .tracks(playlist: Self.low) && s.current == nil)
    }

    @Test func aWaitingStartStaysAndALateAnswerStartsNothing() {
        var s = onSpotifyArtists()
        send(&s, .play)
        #expect(send(&s, .play) == [] && s.startToken == 2)  // a second Play while it reads changes nothing
        send(&s, .menu, .tracksLoaded(token: 2, playlist: Self.low, tracks: Self.popular))
        #expect(s.top.screen == .artists && s.current == nil)
    }

    @Test func offlineItShowsTheToastAndOpensNothing() {
        var s = onSpotifyArtists()
        send(&s, .offline(true))
        #expect(send(&s, .play) == [] && s.toast == "You’re offline right now")
        #expect(s.top.screen == .artists && s.startToken == nil && s.current == nil)
    }

    @Test func anEmptyArtistPlaysNothingAndShowsItsList() {
        var s = onSpotifyArtists()
        send(&s, .play, .tracksLoaded(token: 2, playlist: Self.low, tracks: []))
        #expect(s.top.screen == .tracks(playlist: Self.low) && s.current == nil && s.startToken == nil)
        send(&s, .menu)  // read before: the same
        #expect(send(&s, .play) == [] && s.top.screen == .tracks(playlist: Self.low) && s.current == nil)
    }

    @Test func appleMusicStartsTheArtistsSongs() {
        var s = LibraryRowsTests().withRows()
        send(&s, .wheel(2), .select, .artistsLoaded(token: 1, artists: LibraryRowsTests.artists))
        let id = LibraryRowsTests.ids.c  // 2Pac, the first in name order
        #expect(s.rows(for: s.top)[s.top.sel] == .artist(id))
        let press = firstSongPress(s, id, focus.tracks)
        #expect(send(&s, .play) == [.fetchTracks(token: 2, playlist: id)])
        #expect(send(&s, .tracksLoaded(token: 2, playlist: id, tracks: focus.tracks)).filter(\.isNotTrack) == press)
        #expect(s.top.screen == .now && s.current == TrackRef(playlist: id, track: "f0"))
    }

    @Test func onThisMacStartsTheArtistsSongs() {
        var s = LocalRereadTests().onThisMac()
        let band = Playlist(id: LocalID.artist("Band"), name: "Band", tracks: [])
        let row = s.rows(for: s.top).firstIndex(of: .artists) ?? -1
        send(&s, .wheel(row - s.top.sel), .select)
        send(&s, .artistsLoaded(token: s.top.token, artists: [band]))
        #expect(s.top.screen == .artists && s.rows(for: s.top)[s.top.sel] == .artist(band.id))
        let song = LocalRereadTests.song
        let press = firstSongPress(s, band.id, [song])
        let token = s.tok + 1
        #expect(send(&s, .play) == [.fetchTracks(token: token, playlist: band.id)])
        #expect(send(&s, .tracksLoaded(token: token, playlist: band.id, tracks: [song])).filter(\.isNotTrack) == press)
        #expect(s.top.screen == .now && s.current == TrackRef(playlist: band.id, track: song.id))
    }

    @Test func searchAndPlaylistRowsDoNotChange() {
        // Search: an artist result still starts that artist; a song result still plays that song.
        var s = mainMenu()
        s.artists = SpotifyArtists.list(Self.liked); s.artistsLoaded = true
        s.stack.append(Frame(screen: .search))
        for key in "low" { send(&s, .searchType(key)) }
        send(&s, .wheel(1))
        #expect(s.searchPicked && s.rows(for: s.top)[s.top.sel] == .artist(Self.low))
        #expect(send(&s, .play) == [.fetchTracks(token: s.top.token, playlist: Self.low)] && s.startToken == s.top.token)
        // Playlists: Play on a playlist row starts it, as before.
        s = mainMenu()
        send(&s, .wheel(1), .select, .playlistsLoaded(token: 1, playlists: [focusInfo]))
        #expect(send(&s, .play) == [.fetchTracks(token: 2, playlist: "focus")] && s.startToken == 2)
    }
}
