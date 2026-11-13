import Testing
@testable import ClasifyCore

/// Signed in on the main menu with the Cover Flow row, and Liked Songs read: one song on each
/// album in `names`. The album IDs are "spotify:album:0", "spotify:album:1" and so on.
func withCoverFlow(_ names: [String]) -> AppState {
    var s = mainMenu()
    let tracks = names.enumerated().map { i, name in
        Track(id: "t\(i)", title: "t\(i)", artist: "a", duration: 100, album: Album(id: "spotify:album:\(i)", name: name))
    }
    s.library = [Playlist(id: Playlist.likedSongsID, name: "Liked Songs", tracks: tracks)]
    s.loadedTracks = [Playlist.likedSongsID]
    s.readAt[Playlist.likedSongsID] = 100
    return s
}

/// Ten albums, A to Z: "#" (a number), A, A, B, B, C, D, E, F, G.
let tenAlbums = ["Blue", "1989", "Aja", "Gold", "Abbey Road", "Clouds", "Born", "Dark Side", "Fame", "Eno"]

@Suite struct CoverFlowTests {
    /// The album in the middle of Cover Flow.
    func shown(_ s: AppState) -> String? {
        s.albums.indices.contains(s.top.sel) ? s.albums[s.top.sel].name : nil
    }

    @Test func theRowComesAfterNowPlayingAndOpensOnTheMiddleAlbumTheFirstTime() {
        var s = withCoverFlow(tenAlbums)
        #expect(s.rows(for: s.top) == [.coverFlow, .playlists, .albums, .likedSongs, .shuffleSongs, .settings])
        #expect(send(&s, .select, now: 150) == [])  // Liked Songs was read 50 s ago: no read
        #expect(s.top.screen == .coverFlow && !s.top.loading && !s.isHalf(.coverFlow))
        #expect(shown(s) == "Clouds")  // the middle of ten: index 5
        #expect(s.rows(for: s.top).count == 10)
        // While a song plays, Now Playing comes first.
        var playing = mainMenu()
        playing.current = TrackRef(playlist: Playlist.likedSongsID, track: "x")
        #expect(playing.rows(for: playing.top).prefix(2) == [.nowPlaying, .coverFlow])
    }

    @Test func theMainMenuOpensAndClosesLikeDoorsOnlyToCoverFlow() {
        var s = withCoverFlow(tenAlbums)
        send(&s, .select, now: 150)
        #expect(s.navMove == .doors && s.navForward)  // the menu opens like two doors
        send(&s, .select, now: 151)  // the song panel: the cover turns over
        #expect(s.navMove != .doors)
        send(&s, .menu, now: 152)
        #expect(s.navMove != .doors)  // back to Cover Flow from the panel
        send(&s, .menu, now: 153)
        #expect(s.navMove == .doors && !s.navForward)  // the doors close
        send(&s, .wheel(2), .select, now: 154)  // Albums: both half screens, only the list slides
        #expect(s.navMove != .doors)
        // With Album Art off, the main menu is a full screen: no whole move, so no doors.
        var off = withCoverFlow(tenAlbums)
        off.albumArt = .off
        send(&off, .select, now: 150)
        #expect(off.top.screen == .coverFlow && off.navMove != .doors)
    }

    @Test func itOpensWhereYouLeftItAndOnThePlayingAlbum() {
        var s = withCoverFlow(tenAlbums)
        send(&s, .select, now: 150)
        send(&s, .wheel(1), now: 151)
        #expect(shown(s) == "Dark Side")
        send(&s, .menu, .select, now: 152)
        #expect(shown(s) == "Dark Side")  // where it was left
        // A playing song: its album, which wins over where it was left.
        send(&s, .menu, now: 153)
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "t2")  // Aja
        send(&s, .wheel(1), .select, now: 154)  // Now Playing is the first row now
        #expect(s.top.screen == .coverFlow && shown(s) == "Aja")
    }

    @Test func aRereadThatRemovesTheShownAlbumOpensOnTheAlbumShownAfterIt() {
        var s = withCoverFlow(tenAlbums)
        send(&s, .select, now: 150)
        #expect(shown(s) == "Clouds")
        s.refreshing = [Playlist.likedSongsID]
        let left = s.library[0].tracks.filter { $0.id != "t5" }  // Clouds leaves
        send(&s, .tracksRefreshed(playlist: Playlist.likedSongsID, tracks: left), now: 151)
        #expect(shown(s) == "Dark Side")  // the same place
        send(&s, .menu, .select, now: 152)
        #expect(shown(s) == "Dark Side")  // not the middle album, Born
    }

    @Test func itReadsLikedSongsFirst() {
        var s = mainMenu()
        #expect(send(&s, .select) == [.fetchTracks(token: 1, playlist: Playlist.likedSongsID)])
        #expect(s.top.screen == .coverFlow && s.top.loading)
        send(&s, .wheel(1))  // nothing to move while it loads
        #expect(s.top.sel == 0)
        send(&s, .tracksLoaded(token: 1, playlist: Playlist.likedSongsID, tracks: likedAlbums))
        #expect(!s.top.loading && shown(s) == "MTV Unplugged In New York")  // the middle of four: index 2
    }

    @Test func theWheelAndTheButtonsMoveOneAlbum() {
        var s = withCoverFlow(tenAlbums)
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "t3")  // Gold, the last album
        send(&s, .wheel(1), .select, now: 150)
        #expect(shown(s) == "Gold")
        // ⏮ and ⏭ move the albums, not the song.
        #expect(send(&s, .prev, now: 151) == [] && shown(s) == "Fame")
        #expect(send(&s, .next, now: 152) == [] && shown(s) == "Gold")
        // At the end, a step moves nothing, so the wheel is silent.
        let before = s
        send(&s, .wheel(1), now: 153)
        #expect(shown(s) == "Gold" && !wheelMoved(from: before, to: s))
        let back = s
        send(&s, .wheel(-1), now: 154)
        #expect(shown(s) == "Fame" && wheelMoved(from: back, to: s))
        // Slow steps never show the letter: four steps, 0.3 s apart.
        for (i, t) in [160.0, 160.3, 160.6, 160.9].enumerated() {
            send(&s, .wheel(-1), now: t)
            #expect(s.coverFlowLetter == nil, "step \(i)")
        }
        #expect(shown(s) == "Born")  // four albums back from Fame
    }

    @Test func aFastSpinShowsTheLetterAndJumpsByLetter() {
        var s = withCoverFlow(tenAlbums)
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "t3")  // Gold, the last album
        send(&s, .wheel(1), .select, now: 150)
        #expect(shown(s) == "Gold")
        // Six quick steps within 0.4 s move one album each. The sixth shows the letter.
        for (i, t) in [200.0, 200.05, 200.1, 200.15, 200.2].enumerated() {
            send(&s, .wheel(-1), now: t)
            #expect(s.coverFlowLetter == nil, "step \(i)")
        }
        send(&s, .wheel(-1), now: 200.25)
        #expect(shown(s) == "Blue" && s.coverFlowLetter == "B")
        // Then each step jumps to the first album of the next or previous letter.
        send(&s, .wheel(-1), now: 200.3)
        #expect(shown(s) == "Abbey Road" && s.coverFlowLetter == "A")
        send(&s, .wheel(-1), now: 200.4)
        #expect(shown(s) == "1989" && s.coverFlowLetter == "#")
        send(&s, .wheel(-1), now: 200.5)
        #expect(shown(s) == "1989")  // the first letter: it stays
        send(&s, .wheel(1), now: 200.6)
        #expect(shown(s) == "Abbey Road")
        send(&s, .wheel(1), now: 200.7)
        #expect(shown(s) == "Blue" && s.coverFlowLetter == "B")
        // About 1 s after the last step, the letter hides, and the wheel moves one album again.
        send(&s, .tick, now: 201.6)
        #expect(s.coverFlowLetter == "B")
        send(&s, .tick, now: 201.8)
        #expect(s.coverFlowLetter == nil && s.letterUntil == 0)
        send(&s, .wheel(1), now: 203)
        #expect(shown(s) == "Born")
    }

    /// Change 95: five quick steps, or six steps over more than 0.4 s, do not show the letter.
    @Test func fiveQuickStepsOrSixSlowerOnesShowNoLetter() {
        var s = withCoverFlow(tenAlbums)
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "t3")  // Gold, the last album
        send(&s, .wheel(1), .select, now: 150)
        for t in [200.0, 200.05, 200.1, 200.15, 200.2] { send(&s, .wheel(-1), now: t) }
        #expect(shown(s) == "Born" && s.coverFlowLetter == nil && s.letterUntil == 0)
        // Six steps 0.1 s apart take 0.5 s.
        for t in [210.0, 210.1, 210.2, 210.3, 210.4, 210.5] { send(&s, .wheel(1), now: t) }
        #expect(shown(s) == "Gold" && s.coverFlowLetter == nil && s.letterUntil == 0)
        // Six steps within 0.35 s show it.
        for t in [220.0, 220.07, 220.14, 220.21, 220.28, 220.35] { send(&s, .wheel(-1), now: t) }
        #expect(s.letterUntil > 0)
    }

    @Test func onTheLastLetterAJumpStays() {
        let albums = withCoverFlow(tenAlbums).albums
        let gold = albums.firstIndex { $0.name == "Gold" }!
        #expect(AppState.letterJump(from: gold, by: 1, in: albums) == gold)
        #expect(AppState.letterJump(from: gold, by: -1, in: albums) == gold - 1)  // Fame
        let aja = albums.firstIndex { $0.name == "Aja" }!
        #expect(AppState.letterJump(from: aja, by: 1, in: albums) == aja + 1)  // Blue
        #expect(AppState.letterJump(from: aja, by: -1, in: albums) == 0)  // 1989
        #expect(Album.letter("éclair") == "E" && Album.letter("#1s") == "#" && Album.letter("1989") == "#")
        #expect(Album.letter("abba") == "A")
    }

    @Test func menuHidesTheLetter() {
        var s = withCoverFlow(tenAlbums)
        send(&s, .select, now: 150)
        for t in [200.0, 200.05, 200.1, 200.15, 200.2, 200.25] { send(&s, .wheel(1), now: t) }
        #expect(s.letterUntil > 0)
        send(&s, .menu, now: 200.4)
        #expect(s.top.screen == .main && s.letterUntil == 0 && s.coverFlowSteps.isEmpty)
        // Center during the letter opens the album; MENU comes back with no letter.
        send(&s, .select, now: 201)
        for t in [202.0, 202.05, 202.1, 202.15, 202.2, 202.25] { send(&s, .wheel(1), now: t) }
        send(&s, .select, now: 202.4)
        #expect(s.letterUntil == 0 && s.coverFlowSteps.isEmpty)
        send(&s, .menu, now: 202.5)
        #expect(s.top.screen == .coverFlow && s.coverFlowLetter == nil)
    }

    @Test func signingOutForgetsTheShownAlbum() {
        var s = withCoverFlow(tenAlbums)
        send(&s, .select, now: 150)
        #expect(s.coverFlowAlbum != nil)
        send(&s, .menu, .wheel(5), .select, .wheel(8), .select, .wheel(1), .select, now: 151)  // Settings, Log out, Log out
        #expect(s.top.screen == .login && s.coverFlowAlbum == nil && s.letterUntil == 0)
    }

    /// Cover Flow with three songs on Clouds (index 5), and the album already read.
    func withPanel() -> AppState {
        var s = withCoverFlow(tenAlbums)
        let clouds = Album(id: "spotify:album:5", name: "Clouds")
        s.library[0].tracks += [
            Track(id: "c2", title: "c2", artist: "a", duration: 100, album: clouds),
            Track(id: "c3", title: "c3", artist: "a", duration: 100, album: clouds),
        ]
        s.library.append(Playlist(id: "spotify:album:5", name: "", tracks: s.tracks(in: "spotify:album:5")))
        s.loadedTracks.insert("spotify:album:5")
        s.readAt["spotify:album:5"] = 150
        send(&s, .select, now: 150)
        return s
    }

    /// CLA-46: the panel shows all songs of the album. The first open reads them while the
    /// cover turns over; a failed read shows the error, and center tries again.
    @Test func theFirstOpenOfThePanelReadsTheWholeAlbum() {
        var s = withCoverFlow(tenAlbums)
        send(&s, .select, now: 150)  // Cover Flow, on Clouds
        #expect(send(&s, .select, now: 151) == [.fetchTracks(token: 1, playlist: "spotify:album:5")])
        #expect(s.top.screen == .albumPanel(album: "spotify:album:5") && s.top.loading && s.navMove == .flip)
        #expect(s.coverFlowFrame?.sel == 5)
        send(&s, .tracksLoaded(token: 1, playlist: "spotify:album:5", tracks: nil), now: 152)
        #expect(s.top.error && !s.top.loading)
        #expect(send(&s, .select, now: 153) == [.fetchTracks(token: 2, playlist: "spotify:album:5")])
        let clouds = Album(id: "spotify:album:5", name: "Clouds")
        let all = ["t5", "x1", "x2"].map { Track(id: $0, title: $0, artist: "a", duration: 100, album: clouds) }
        send(&s, .tracksLoaded(token: 2, playlist: "spotify:album:5", tracks: all), now: 154)
        #expect(!s.top.loading && !s.top.error && s.rows(for: s.top) == [.track("t5"), .track("x1"), .track("x2")])
        // Cover Flow still shows only the albums of Liked Songs.
        #expect(s.albums.count == 10)
        // Back and in again: no read.
        send(&s, .menu, now: 155)
        #expect(send(&s, .select, now: 156) == [] && !s.top.loading)
    }

    @Test func centerTurnsTheCoverIntoTheSongPanel() {
        var s = withPanel()
        send(&s, .select, now: 151)
        #expect(s.top.screen == .albumPanel(album: "spotify:album:5"))  // Clouds
        #expect(s.navMove == .flip && s.navForward && !s.top.loading)
        #expect(s.rows(for: s.top) == [.track("t5"), .track("c2"), .track("c3")])
        #expect(s.shownRows == panelRows && !s.showsBar && s.top.screen.songList == "spotify:album:5")
        send(&s, .wheel(2), now: 152)
        #expect(s.top.sel == 2)
        send(&s, .menu, now: 153)  // the panel turns back into the cover
        #expect(s.top.screen == .coverFlow && s.navMove == .flip && !s.navForward)
        #expect(s.albums[s.top.sel].name == "Clouds")
    }

    /// Card AK, change 112: with Now Playing Bar on and a song loaded, the panel shows the bar
    /// inside its bottom edge, so one song row less fits. The covers view shows no bar.
    @Test func theSongPanelShowsTheBarInside() {
        var s = withPanel()
        s.nowPlayingBar = true
        send(&s, .select, now: 151)
        #expect(!s.showsPanelBar && s.shownRows == panelRows)  // nothing loaded yet
        send(&s, .select, .menu, now: 152)  // play the first song, then back to the panel
        #expect(s.top.screen == .albumPanel(album: "spotify:album:5") && s.showsPanelBar && !s.showsBar)
        #expect(s.shownRows == panelRows - 1)
        send(&s, .menu, now: 153)
        #expect(s.top.screen == .coverFlow && !s.showsBar)
    }

    @Test func aSongInThePanelPlaysInTheAlbumAndFliesToNowPlaying() {
        var s = withPanel()
        send(&s, .select, .wheel(1), now: 151)
        let load: [Effect] = [.setShuffle(false), .setRepeat(.off),
                              .load(trackID: "c2", context: "spotify:album:5", autoplay: true, generation: 1)]
        #expect(send(&s, .select, now: 152) == load)
        #expect(s.current == TrackRef(playlist: "spotify:album:5", track: "c2"))
        #expect(s.top.screen == .now && s.navMove == .fly && s.navForward)
        send(&s, .menu, now: 153)  // back to the panel: the cover flies back
        #expect(s.top.screen == .albumPanel(album: "spotify:album:5") && s.navMove == .fly && !s.navForward)
        send(&s, .menu, now: 154)
        #expect(s.top.screen == .coverFlow && s.navMove == .flip)
    }

    @Test func theCoverFlowFrameKeepsTheMiddleAlbumWhileThePanelShows() {
        var s = withPanel()
        #expect(s.coverFlowFrame?.sel == 5)
        send(&s, .select, .wheel(2), now: 151)
        #expect(s.top.sel == 2 && s.coverFlowFrame?.sel == 5)  // the song, and still Clouds
        send(&s, .select, now: 152)
        #expect(s.top.screen == .now && s.coverFlowFrame == nil)
        #expect(mainMenu().coverFlowFrame == nil)
    }

    @Test func withAlbumArtOffOrOfflineASongPushesNowPlayingInstead() {
        var off = withPanel()
        off.albumArt = .off
        send(&off, .select, .select, now: 151)  // the panel, then its first song
        #expect(off.top.screen == .now && off.navMove == .push && !off.nowOverPanel)
        send(&off, .menu, now: 152)
        #expect(off.navMove == .push)

        var s = withPanel()
        send(&s, .select, .select, now: 151)
        #expect(s.navMove == .fly && s.nowOverPanel)
        s.offline = true  // the connection drops on Now Playing
        #expect(!s.nowOverPanel)
        send(&s, .menu, now: 152)
        #expect(s.top.screen == .albumPanel(album: "spotify:album:5") && s.navMove == .push)
    }

    @Test func aFailedLoadThatBringsBackAnotherAlbumStopsTheFlight() {
        var s = withPanel()
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "t0")  // another song plays
        send(&s, .select, .select, now: 151)  // a song of Clouds
        #expect(s.navMove == .fly && s.nowOverPanel)
        let generation = s.playGen
        send(&s, .loadFailed("Can’t play", generation: generation), now: 152)
        #expect(s.top.screen == .now && s.current?.track == "t0" && !s.nowOverPanel)
        send(&s, .menu, now: 153)  // the panel's cover must not fly back over another song
        #expect(s.top.screen == .albumPanel(album: "spotify:album:5") && s.navMove == .push)
    }

    @Test func eachScreenChangeHasItsMove() {
        let panel = Screen.albumPanel(album: "spotify:album:5")
        #expect(AppState.move(between: .main, and: .coverFlow, whole: true) == .doors)
        #expect(AppState.move(between: .coverFlow, and: .main, whole: true) == .doors)
        #expect(AppState.move(between: .main, and: .coverFlow, whole: false) == .push)  // Album Art off
        #expect(AppState.move(between: .coverFlow, and: panel, whole: false) == .flip)
        #expect(AppState.move(between: panel, and: .coverFlow, whole: false) == .flip)
        #expect(AppState.move(between: panel, and: .now, whole: false) == .fly)
        #expect(AppState.move(between: .now, and: panel, whole: false) == .fly)
        #expect(AppState.move(between: panel, and: .now, whole: false, fly: false) == .push)
        #expect(AppState.move(between: .tracks(playlist: "x"), and: .now, whole: false) == .push)
        #expect(AppState.move(between: .main, and: .playlists, whole: false) == .push)
    }

    @Test func eachAlbumTakesTheCoverOfItsFirstSongWithOne() {
        var s = withCoverFlow(["Aja", "Blue"])
        let aja = Album(id: "spotify:album:0", name: "Aja")
        s.library[0].tracks[0].coverID = nil
        s.library[0].tracks += [
            Track(id: "t2", title: "t2", artist: "a", duration: 100, coverID: "c2", album: aja),
            Track(id: "t3", title: "t3", artist: "a", duration: 100, coverID: "c3", album: aja),
        ]
        s.library[0].tracks[1].coverID = "c1"
        #expect(s.albumCovers == ["spotify:album:0": "c2", "spotify:album:1": "c1"])
    }

    @Test func withNoAlbumsNothingMoves() {
        var s = withCoverFlow([])
        send(&s, .select, now: 150)
        #expect(s.top.screen == .coverFlow && s.rows(for: s.top).isEmpty)
        #expect(send(&s, .wheel(1), .next, .select, now: 151) == [])
        #expect(s.top.screen == .coverFlow && s.top.sel == 0)
    }
}
