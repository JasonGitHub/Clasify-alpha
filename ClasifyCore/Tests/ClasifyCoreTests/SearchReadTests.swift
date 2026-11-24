import Testing
@testable import ClasifyCore

/// CLA-183, card CS: while Search is open, the lists it finds songs in are read quietly, one at
/// a time, through the read paths that exist already.
@Suite struct SearchReadTests {
    static let drive = Playlist(id: "drive", name: "Drive", tracks: tracks("d", 3, 20))
    static let driveInfo = Playlist(id: "drive", name: "Drive", tracks: [], trackCount: 3)

    /// Spotify's main menu with Search on, its cover read of Liked Songs (token 1) done, and
    /// the playlist list read (Focus and Drive, no songs).
    func spotify() -> AppState {
        var s = mainMenu()
        s.searchOn = true
        send(&s, .artTracksRead(token: 1, playlist: Playlist.likedSongsID, tracks: liked.tracks))
        s.library += [focusInfo, Self.driveInfo]; s.playlistsLoaded = true
        return s
    }

    @discardableResult
    func openSearch(_ s: inout AppState) -> [Effect] {
        for _ in 0..<8 where s.top.screen != .main { send(&s, .menu) }
        s.top.sel = s.rows(for: s.top).firstIndex(of: .search)!
        return send(&s, .select)
    }

    @Test func listsAreReadOneAtATimeInOrder() {
        var s = mainMenu()
        s.searchOn = true
        // The main menu's cover read of Liked Songs runs: Search waits for it.
        #expect(openSearch(&s).isEmpty)
        // Then the playlist list, then each playlist in row order. Spotify has no artist read.
        #expect(send(&s, .artTracksRead(token: 1, playlist: Playlist.likedSongsID, tracks: liked.tracks)) == [.refreshPlaylists])
        #expect(send(&s, .playlistsRefreshed([focusInfo, Self.driveInfo])) == [.readArtTracks(token: 2, playlist: "focus")])
        #expect(send(&s, .tick).isEmpty)  // one at a time
        #expect(send(&s, .artTracksRead(token: 2, playlist: "focus", tracks: focus.tracks)) == [.readArtTracks(token: 3, playlist: "drive")])
        #expect(send(&s, .artTracksRead(token: 3, playlist: "drive", tracks: Self.drive.tracks)).isEmpty)
        #expect(s.loadedTracks == [Playlist.likedSongsID, "focus", "drive"])
        // The results follow: a song of Drive is found.
        send(&s, .searchType("d"), .searchType("1"), now: 101)  // a second later: the index is made again
        #expect(s.searchResults.map(\.id) == ["d1"])
        #expect(s.top.screen == .search && !s.top.loading)  // no spinner
    }

    @Test func aFailedReadIsSkippedUntilSearchOpensAgain() {
        var s = spotify()
        #expect(openSearch(&s) == [.readArtTracks(token: 2, playlist: "focus")])
        #expect(send(&s, .artTracksRead(token: 2, playlist: "focus", tracks: nil)) == [.readArtTracks(token: 3, playlist: "drive")])
        #expect(send(&s, .artTracksRead(token: 3, playlist: "drive", tracks: Self.drive.tracks)).isEmpty)
        #expect(send(&s, .tick).isEmpty)  // not tried again
        send(&s, .menu)
        #expect(s.top.screen == .main)
        #expect(openSearch(&s) == [.readArtTracks(token: 4, playlist: "focus")])
    }

    @Test func leavingSearchStartsNoNewReadAndTheReadInFlightLands() {
        var s = spotify()
        openSearch(&s)
        send(&s, .menu)
        #expect(send(&s, .artTracksRead(token: 2, playlist: "focus", tracks: focus.tracks)).isEmpty)
        #expect(s.loadedTracks.contains("focus") && !s.loadedTracks.contains("drive"))
    }

    @Test func aListThatAnOpenReadsGetsNoSecondRead() {
        var s = spotify()
        s.stack.append(Frame(screen: .search))
        s.stack.append(Frame(screen: .tracks(playlist: "focus"), loading: true, token: 9))  // opened from Search
        #expect(send(&s, .tick).isEmpty)
        // The open's answer: Search goes on with the next list.
        #expect(send(&s, .tracksLoaded(token: 9, playlist: "focus", tracks: focus.tracks)) == [.readArtTracks(token: 2, playlist: "drive")])
    }

    /// A sign-out drops the old account's answer; Search on the next login reads its library.
    @Test func aSignOutDropsTheOldAnswer() {
        var s = spotify()
        openSearch(&s)  // Focus, token 2
        send(&s, .expire)
        #expect(s.top.screen == .login && !s.signedIn)
        send(&s, .artTracksRead(token: 2, playlist: "focus", tracks: focus.tracks))
        #expect(s.library.isEmpty && s.loadedTracks.isEmpty)
    }

    /// A service switch drops the old service's answer, and Search on the new service reads
    /// the new library, with its artists.
    @Test func aServiceSwitchDropsTheOldAnswer() {
        var s = spotify()
        openSearch(&s)  // Focus, token 2
        send(&s, .menu)
        s.top.sel = s.rows(for: s.top).firstIndex(of: .settings)!
        send(&s, .select, .select, .menu)  // Service: Apple Music
        #expect(s.service == .appleMusic)
        send(&s, .restored(token: s.authAttempt, ok: true))
        send(&s, .artTracksRead(token: 2, playlist: "focus", tracks: focus.tracks))
        #expect(!s.loadedTracks.contains("focus") && !s.library.contains { $0.id == "focus" })
        s.searchOn = true
        s.artReads = [:]  // the main menu's cover read, not part of this test
        let fx = openSearch(&s)
        #expect(fx == [.readArtTracks(token: s.artTok, playlist: s.albumsList)] && s.albumsList != "focus")
    }

    /// Apple Music and On This Mac have an artist list: Search reads it once, after the albums
    /// list and the playlist list. Spotify has none (S1).
    @Test func appleMusicAndOnThisMacReadTheArtists() {
        for service in [MusicService.appleMusic, .local] {
            var s = mainMenu()
            s.searchOn = true; s.service = service; s.words = service == .local ? .local : .appleMusic
            s.artReads = [:]
            s.library = [Playlist(id: Playlist.libraryID, name: "", tracks: tracks("a", 2, 10))]
            s.loadedTracks = [Playlist.libraryID]; s.playlistsLoaded = true
            #expect(openSearch(&s) == [.refreshArtists], "\(service)")
            let artist = Playlist(id: "applemusic:artist:1", name: "Vera Lune", tracks: [])
            #expect(send(&s, .artistsRefreshed([artist])).isEmpty, "\(service)")
            #expect(s.artistsLoaded && s.artists == [artist], "\(service)")
            send(&s, .searchType("v"), .searchType("e"), .searchType("r"), now: 101)
            #expect(s.searchResults.map(\.kind) == [.artist], "\(service)")
        }
    }

    /// Offline, nothing is read; back online, the reads go on.
    @Test func offlineReadsNothing() {
        var s = spotify()
        s.offline = true
        #expect(openSearch(&s).isEmpty)
        s.offline = false
        #expect(send(&s, .tick) == [.readArtTracks(token: 2, playlist: "focus")])
    }

    /// CTO on #457: while reads arrive, the index is made again at most once a second. A key
    /// in between asks the last index; the app sends `.tick` when the wait is over.
    @Test func theIndexIsMadeAgainAtMostOnceASecond() {
        var s = spotify()
        openSearch(&s)  // at 100: the index is made; Focus is read
        send(&s, .searchType("f"), .searchType("0"), now: 100.2)
        #expect(s.searchResults.isEmpty)
        send(&s, .artTracksRead(token: 2, playlist: "focus", tracks: focus.tracks), now: 100.4)
        #expect(s.searchResults.isEmpty && !s.searchIndexDue(at: 100.9) && s.searchIndexDue(at: 101))
        send(&s, .searchDelete, .searchType("0"), now: 100.6)  // the last index still answers
        #expect(s.searchResults.isEmpty)
        send(&s, .tick, now: 101)
        #expect(s.searchResults.map(\.id) == ["f0"] && !s.searchIndexDue(at: 200))
        // Drive lands at 101.5: the next make waits until 102.
        send(&s, .artTracksRead(token: 3, playlist: "drive", tracks: Self.drive.tracks), now: 101.5)
        #expect(!s.searchIndexDue(at: 101.9) && s.searchIndexDue(at: 102))
        // Leaving Search: no tick is due.
        send(&s, .menu, now: 101.6)
        #expect(!s.searchIndexDue(at: 300))
    }

    /// Late results move nothing under the person: the selected row stays on its song when
    /// rows come in above it.
    @Test func theSelectionStaysOnItsResultWhenRowsComeInAbove() {
        var s = spotify()
        s.library[s.library.firstIndex { $0.id == "focus" }!] = focus; s.loadedTracks.insert("focus")
        openSearch(&s)  // Drive is read
        send(&s, .searchType("0"), .wheel(1))
        #expect(s.searchResults.map(\.id) == ["f0", "l0"] && s.searchPicked && s.top.sel == 0)
        send(&s, .artTracksRead(token: 2, playlist: "drive", tracks: Self.drive.tracks), now: 101)
        #expect(s.searchResults.map(\.id) == ["d0", "f0", "l0"])  // "d0" sorts first
        #expect(s.searchPicked && s.top.sel == 1)
    }
}
