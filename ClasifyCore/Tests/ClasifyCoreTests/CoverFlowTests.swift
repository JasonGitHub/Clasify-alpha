import Testing
@testable import ClasifyCore

/// Signed in on the main menu with the Cover Flow row, and Liked Songs read: one song on each
/// album in `names`. The album IDs are "spotify:album:0", "spotify:album:1" and so on.
func withCoverFlow(_ names: [String]) -> AppState {
    var s = mainMenu()
    s.coverFlowRow = true
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
        // Off, the row is not there (until the Cover Flow screen is drawn).
        var off = mainMenu()
        #expect(!off.rows(for: off.top).contains(.coverFlow))
        off.current = TrackRef(playlist: Playlist.likedSongsID, track: "x")
        off.coverFlowRow = true
        #expect(off.rows(for: off.top).prefix(2) == [.nowPlaying, .coverFlow])
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

    @Test func itReadsLikedSongsFirst() {
        var s = mainMenu()
        s.coverFlowRow = true
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
        send(&s, .select, now: 150)
        #expect(shown(s) == "Clouds")
        // Four quick steps move one album each. The fourth shows the letter.
        for (i, t) in [200.0, 200.1, 200.2].enumerated() {
            send(&s, .wheel(-1), now: t)
            #expect(s.coverFlowLetter == nil, "step \(i)")
        }
        send(&s, .wheel(-1), now: 200.3)
        #expect(shown(s) == "Abbey Road" && s.coverFlowLetter == "A")
        // Then each step jumps to the first album of the next or previous letter.
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
        for t in [200.0, 200.1, 200.2, 200.3] { send(&s, .wheel(1), now: t) }
        #expect(s.letterUntil > 0)
        send(&s, .menu, now: 200.4)
        #expect(s.top.screen == .main && s.letterUntil == 0 && s.coverFlowSteps.isEmpty)
    }

    @Test func centerOpensTheAlbumsSongs() {
        var s = withCoverFlow(tenAlbums)
        send(&s, .select, now: 150)
        send(&s, .select, now: 151)
        #expect(s.top.screen == .tracks(playlist: "spotify:album:5"))  // Clouds
        #expect(s.rows(for: s.top) == [.track("t5")])
    }

    @Test func withNoAlbumsNothingMoves() {
        var s = withCoverFlow([])
        send(&s, .select, now: 150)
        #expect(s.top.screen == .coverFlow && s.rows(for: s.top).isEmpty)
        #expect(send(&s, .wheel(1), .next, .select, now: 151) == [])
        #expect(s.top.screen == .coverFlow && s.top.sel == 0)
    }
}
