import Testing
@testable import ClasifyCore

// CLA-173: Play on a playlist or album row, or on Cover Flow's covers, starts that list on Now
// Playing, like the iPod. Now Playing opens over the row's own screen, so MENU goes back to the
// same row or middle album. Every other row and screen keeps its Play.

/// On Playlists with Focus highlighted. Focus is not read yet. Token 1 read the playlist list.
private func onPlaylists() -> AppState {
    var s = mainMenu()
    send(&s, .wheel(1), .select, .playlistsLoaded(token: 1, playlists: [focusInfo, chillInfo]))
    return s
}
private let chill = Playlist(id: "chill", name: "Chill", tracks: tracks("c", 3, 30))
private let chillInfo = Playlist(id: "chill", name: "Chill", tracks: [], trackCount: 3)
/// One song on the album, as its read gives it.
private func coverSongs(_ s: AppState, _ album: String) -> [Track] {
    [Track(id: "m1", title: "m1", artist: "a", duration: 100, album: s.album(album), disc: nil, number: 1)]
}
private let firstLoad: [Effect] = [.setShuffle(false), .setRepeat(.off), .load(trackID: "f0", context: "focus", autoplay: true, generation: 1)]

@Suite struct PlayListTests {
    @Test func aPlaylistThatWasReadStartsAtOnceFromItsFirstSong() {
        var s = onPlaylists()
        send(&s, .select, .tracksLoaded(token: 2, playlist: "focus", tracks: focus.tracks), .menu)  // Focus read, back on Playlists
        #expect(s.top.screen == .playlists && s.rows(for: s.top)[s.top.sel] == .playlist("focus"))
        #expect(send(&s, .play) == firstLoad)
        #expect(s.top.screen == .now && s.isPlaying && s.current == TrackRef(playlist: "focus", track: "f0"))
        // Now Playing opens over Playlists: no song list under it.
        #expect(s.stack.map(\.screen) == [.main, .playlists, .now])
        #expect(s.stack[0].sel == 2)  // the main menu row moved down under the new Now Playing row
        // MENU goes back to Playlists, on the same row.
        send(&s, .menu)
        #expect(s.top.screen == .playlists && s.rows(for: s.top)[s.top.sel] == .playlist("focus"))
    }

    @Test func anOldCopyReadsAgainBehindNowPlaying() {
        var s = onPlaylists()
        send(&s, .select, .tracksLoaded(token: 2, playlist: "focus", tracks: focus.tracks), .menu)
        let later = Dependencies(now: { 100 + staleAfter }, random: { _ in 0 })
        #expect(reduce(&s, .play, later).filter(\.isNotTrack) == [.refreshTracks(playlist: "focus")] + firstLoad)
        #expect(s.top.screen == .now && s.refreshing.contains("focus"))
    }

    @Test func aPlaylistNotReadYetLoadsWithItsListLookThenStarts() {
        var s = onPlaylists()
        #expect(send(&s, .play) == [.fetchTracks(token: 2, playlist: "focus")])
        #expect(s.top.screen == .tracks(playlist: "focus") && s.top.loading && s.startToken == 2 && s.current == nil)
        // A second Play while it loads changes nothing: the start still waits.
        #expect(send(&s, .play) == [] && s.startToken == 2 && s.stack.count == 3)
        #expect(send(&s, .tracksLoaded(token: 2, playlist: "focus", tracks: focus.tracks)) == firstLoad)
        #expect(s.top.screen == .now && s.current == TrackRef(playlist: "focus", track: "f0") && s.startToken == nil)
        // Now Playing took the loading list's place: MENU goes back to the Focus row.
        #expect(s.stack.map(\.screen) == [.main, .playlists, .now])
        send(&s, .menu)
        #expect(s.top.screen == .playlists && s.rows(for: s.top)[s.top.sel] == .playlist("focus"))

        // A failed read starts nothing. Its retry keeps the start.
        s = onPlaylists()
        send(&s, .play, .tracksLoaded(token: 2, playlist: "focus", tracks: nil))
        #expect(s.top.error && s.current == nil && s.startToken == 2)
        #expect(send(&s, .select) == [.fetchTracks(token: 3, playlist: "focus")] && s.startToken == 3)
        send(&s, .tracksLoaded(token: 3, playlist: "focus", tracks: focus.tracks))
        #expect(s.top.screen == .now && s.current?.track == "f0" && s.stack.map(\.screen) == [.main, .playlists, .now])
    }

    @Test func aLateAnswerNeverStartsAnotherList() {
        // MENU while Focus loads: its late answer starts nothing.
        var s = onPlaylists()
        send(&s, .play, .menu, .tracksLoaded(token: 2, playlist: "focus", tracks: focus.tracks))
        #expect(s.top.screen == .playlists && s.current == nil)
        // Then Play on Chill: only Chill's own answer starts, with Chill.
        s = onPlaylists()
        send(&s, .play, .menu, .wheel(1))
        #expect(send(&s, .play) == [.fetchTracks(token: 3, playlist: "chill")] && s.startToken == 3)
        send(&s, .tracksLoaded(token: 2, playlist: "focus", tracks: focus.tracks))
        #expect(s.current == nil && s.top.loading)
        send(&s, .tracksLoaded(token: 3, playlist: "chill", tracks: chill.tracks))
        #expect(s.top.screen == .now && s.current == TrackRef(playlist: "chill", track: "c0"))
        send(&s, .menu)
        #expect(s.top.screen == .playlists && s.rows(for: s.top)[s.top.sel] == .playlist("chill"))
    }

    @Test func shuffleSongsAndAListStartDoNotMixTheNewerWins() {
        // Shuffle Songs waits for Liked Songs, MENU, then Play on Focus: Focus starts, Liked Songs does not.
        var s = onPlaylists()
        send(&s, .menu, .wheel(3), .select)  // Shuffle Songs: Liked Songs loads with token 2
        #expect(s.shuffleToken == 2)
        send(&s, .menu, .wheel(-3), .select, .play)  // back to Playlists, Play on Focus: token 3
        #expect(s.startToken == 3 && s.shuffleToken == nil)
        send(&s, .tracksLoaded(token: 2, playlist: Playlist.likedSongsID, tracks: liked.tracks))
        #expect(s.current == nil)
        send(&s, .tracksLoaded(token: 3, playlist: "focus", tracks: focus.tracks))
        #expect(s.current == TrackRef(playlist: "focus", track: "f0") && !s.shuffle)

        // A Focus start waits, MENU, then Shuffle Songs: Liked Songs shuffles, Focus does not start.
        s = onPlaylists()
        send(&s, .play, .menu, .menu, .wheel(3), .select)
        #expect(s.shuffleToken == 3 && s.startToken == nil)
        send(&s, .tracksLoaded(token: 2, playlist: "focus", tracks: focus.tracks))
        #expect(s.current == nil)
        send(&s, .tracksLoaded(token: 3, playlist: Playlist.likedSongsID, tracks: liked.tracks))
        #expect(s.current?.playlist == Playlist.likedSongsID && s.shuffle)
    }

    @Test func withShuffleOnItStartsAsAPickInThatListDoes() {
        var s = onPlaylists()
        send(&s, .select, .tracksLoaded(token: 2, playlist: "focus", tracks: focus.tracks), .toggleShuffle, .menu)
        var picked = s
        let e = Dependencies(now: { 100 }, random: { _ in 3 })
        let started = reduce(&s, .play, e).filter(\.isNotTrack)
        #expect(started.first == .setShuffle(true) && started.last == .load(trackID: "f3", context: "focus", autoplay: true, generation: s.playGen))
        #expect(s.shuffle && s.current == TrackRef(playlist: "focus", track: "f3"))
        // The same as picking that song in Focus with Shuffle on.
        _ = reduce(&picked, .select, e)
        _ = reduce(&picked, .wheel(3), e)
        #expect(reduce(&picked, .select, e).filter(\.isNotTrack) == started)
    }

    @Test func anAlbumRowStartsTheWholeAlbum() {
        var s = withLikedAlbums()
        send(&s, .wheel(2), .select)  // Albums: 1989 first
        let album = "spotify:album:1"
        #expect(s.top.screen == .albums && s.rows(for: s.top)[s.top.sel] == .album(album))
        #expect(send(&s, .play) == [.fetchTracks(token: s.top.token, playlist: album)])
        #expect(s.top.screen == .tracks(playlist: album) && s.top.loading && s.startToken == s.top.token)
        let songs = (1...3).map { (n: Int) in Track(id: "s\(n)", title: "s\(n)", artist: "a", duration: 200, album: s.album(album), disc: nil, number: n) }
        send(&s, .tracksLoaded(token: s.top.token, playlist: album, tracks: songs))
        #expect(s.top.screen == .now && s.current == TrackRef(playlist: album, track: "s1"))
        send(&s, .menu)
        #expect(s.top.screen == .albums && s.rows(for: s.top)[s.top.sel] == .album(album))
        // Read before: it starts at once over Albums.
        s.current = nil; s.isPlaying = false
        send(&s, .play)
        #expect(s.top.screen == .now && s.stack.suffix(2).map(\.screen) == [.albums, .now])
    }

    @Test func coverFlowStartsTheMiddleAlbumAndMenuComesBackToIt() {
        var s = withCoverFlow(tenAlbums)
        send(&s, .select)
        let middle = s.top.sel
        let album = s.albums[middle].id
        let depth = s.stack.count
        // Not read yet: the covers stay, with the album in the middle, while it reads. No panel opens.
        let token = s.tok + 1
        #expect(send(&s, .play) == [.fetchTracks(token: token, playlist: album)])
        #expect(s.top.screen == .coverFlow && s.top.sel == middle && s.stack.count == depth)
        #expect(s.startOnCovers && s.startToken == token && s.current == nil)
        #expect(send(&s, .play) == [] && s.startToken == token)  // a second Play: it still waits
        send(&s, .tracksLoaded(token: token, playlist: album, tracks: coverSongs(s, album)))
        #expect(s.top.screen == .now && s.current == TrackRef(playlist: album, track: "m1"))
        #expect(s.startToken == nil && !s.startOnCovers)
        // A plain slide over the covers, no cover flight: there is no song panel under Now Playing.
        #expect(s.stack.suffix(2).map(\.screen) == [.coverFlow, .now] && s.navMove == .push && !s.nowOverPanel)
        // MENU goes back to the covers, with the same album in the middle.
        send(&s, .menu)
        #expect(s.top.screen == .coverFlow && s.top.sel == middle && s.navMove == .push)

        // Read before: it starts at once over the covers.
        s.current = nil; s.isPlaying = false
        send(&s, .play)
        #expect(s.top.screen == .now && s.current == TrackRef(playlist: album, track: "m1") && s.navMove == .push)
        #expect(s.stack.suffix(2).map(\.screen) == [.coverFlow, .now])
        send(&s, .menu)
        #expect(s.top.screen == .coverFlow && s.top.sel == middle)
    }

    @Test func aWaitOnTheCoversEndsOnInputAFailedReadOrAnEmptyAlbum() {
        // Another input cancels the start: its late answer starts nothing.
        var s = withCoverFlow(tenAlbums)
        send(&s, .select)
        var album = s.albums[s.top.sel].id
        send(&s, .play)
        var token = s.startToken ?? -1
        send(&s, .wheel(1))
        #expect(s.startToken == nil && !s.startOnCovers)
        send(&s, .tracksLoaded(token: token, playlist: album, tracks: coverSongs(s, album)))
        #expect(s.top.screen == .coverFlow && s.current == nil)

        // A failed read: a toast, and the covers stay with the album in the middle.
        s = withCoverFlow(tenAlbums)
        send(&s, .select)
        let middle = s.top.sel
        album = s.albums[middle].id
        send(&s, .play)
        token = s.startToken ?? -1
        send(&s, .tracksLoaded(token: token, playlist: album, tracks: nil))
        let message = "Can’t reach \(s.words.service)"
        #expect(s.toast == message || s.heldToast == message)
        #expect(s.top.screen == .coverFlow && s.top.sel == middle && s.current == nil && s.startToken == nil && !s.startOnCovers)

        // An empty album: nothing starts, and the covers stay. Read before: the same.
        s = withCoverFlow(tenAlbums)
        send(&s, .select)
        album = s.albums[s.top.sel].id
        send(&s, .play)
        send(&s, .tracksLoaded(token: s.startToken ?? -1, playlist: album, tracks: []))
        #expect(s.top.screen == .coverFlow && s.current == nil)
        #expect(send(&s, .play) == [] && s.top.screen == .coverFlow && s.current == nil)
    }

    @Test func onAnOpenSongListPlayStaysAsBefore() {
        // Cover Flow's song panel is open: Play is today's Play, not a start of the album.
        var s = withCoverFlow(tenAlbums)
        send(&s, .select)
        let album = s.albums[s.top.sel].id
        send(&s, .select)
        send(&s, .tracksLoaded(token: s.top.token, playlist: album, tracks: []))
        #expect(s.top.screen == .albumPanel(album: album))
        send(&s, .play)
        #expect(s.current?.playlist == Playlist.likedSongsID)  // nothing loaded: Shuffle Songs, as today

        // A song list with a song playing: Play pauses.
        s = playing()
        send(&s, .menu)
        #expect(s.top.screen == .tracks(playlist: "focus") && send(&s, .play) == [.pause])
        // Now Playing: Play pauses.
        s = playing()
        #expect(send(&s, .play) == [.pause] && s.top.screen == .now)
        // Another row, such as Settings, while a song plays: Play pauses.
        s = playing()
        send(&s, .menu, .menu, .menu, .wheel(99))
        #expect(s.rows(for: s.top)[s.top.sel] == .settings && send(&s, .play) == [.pause])
    }

    @Test func offlineItShowsTheToastAndOpensNothing() {
        var s = onPlaylists()
        send(&s, .offline(true))
        #expect(send(&s, .play) == [] && s.toast == "You’re offline right now")
        #expect(s.top.screen == .playlists && s.startToken == nil && s.current == nil)
    }

    @Test func anEmptyListPlaysNothingAndShowsTheList() {
        let empty = Playlist(id: "empty", name: "Empty", tracks: [], trackCount: 0)
        var s = mainMenu()
        send(&s, .wheel(1), .select, .playlistsLoaded(token: 1, playlists: [empty]))
        send(&s, .play, .tracksLoaded(token: 2, playlist: "empty", tracks: []))
        #expect(s.top.screen == .tracks(playlist: "empty") && s.current == nil && s.startToken == nil)
        // Read before: the same.
        send(&s, .menu)
        #expect(send(&s, .play) == [] && s.top.screen == .tracks(playlist: "empty") && s.current == nil)
    }
}
