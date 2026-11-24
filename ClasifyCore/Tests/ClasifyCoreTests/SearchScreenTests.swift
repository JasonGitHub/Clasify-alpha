import Testing
@testable import ClasifyCore

/// CLA-183, card CS: the Search screen behind `search.on`: its main menu row, and the wheel,
/// Center, Play and MENU on it. Typing comes with the keys.
@Suite struct SearchScreenTests {
    let fan = Playlist(id: "spotify:artist:fan", name: "Fan Club", tracks: [])

    /// The main menu with Search on and Liked Songs and Focus read.
    func ready() -> AppState {
        var s = mainMenu()
        s.searchOn = true
        s.library = library; s.loadedTracks = [Playlist.likedSongsID, "focus"]
        return s
    }

    /// Search open, with `query` typed and its results.
    func onSearch(_ query: String = "f") -> AppState {
        var s = ready()
        s.top.sel = s.rows(for: s.top).firstIndex(of: .search)!
        send(&s, .select)
        s.searchQuery = query  // as the keys will type it
        s.searchResults = Search.results(query, in: s)
        return s
    }

    var loads: (Effect) -> Bool { { if case .load = $0 { true } else { false } } }

    @Test func theSwitchAddsSearchAfterShuffleSongs() {
        var s = mainMenu()
        #expect(!s.rows(for: s.top).contains(.search))
        s.searchOn = true
        #expect(s.rows(for: s.top) == [.coverFlow, .playlists, .albums, .likedSongs, .shuffleSongs, .search, .settings])
        s.words = .appleMusic
        #expect(s.rows(for: s.top) == [.coverFlow, .playlists, .artists, .albums, .songs, .shuffleSongs, .search, .settings])
        // Read only, like `local.on`.
        let store = FakeSettings()
        #expect(!Settings(from: store).searchOn)
        store.values["search.on"] = "1"
        let settings = Settings(from: store)
        #expect(settings.searchOn)
        let saved = FakeSettings()
        settings.save(to: saved)
        #expect(saved.values["search.on"] == nil)
        var t = AppState()
        t.settings = settings
        #expect(t.searchOn)
    }

    @Test func searchOpensEmptyWithNoRowSelected() {
        var s = ready()
        s.searchQuery = "old"
        s.top.sel = s.rows(for: s.top).firstIndex(of: .search)!
        #expect(send(&s, .select).isEmpty)
        #expect(s.top == Frame(screen: .search) && s.searchQuery == "" && s.searchResults.isEmpty && !s.searchPicked)
        // Nothing to select: the wheel, Center and Play do nothing.
        #expect(send(&s, .wheel(1), .select, .play).isEmpty)
        #expect(s.top == Frame(screen: .search) && !s.searchPicked && s.current == nil)
    }

    @Test func theFirstTurnOrReturnSelectsTheFirstRow() {
        var s = onSearch()
        #expect(s.rows(for: s.top).first == .playlist("focus") && s.rows(for: s.top)[1] == .foundSong("f0", list: "focus"))
        #expect(!s.searchPicked && s.top.sel == 0)
        send(&s, .wheel(1))
        #expect(s.searchPicked && s.top.sel == 0)
        send(&s, .wheel(1))
        #expect(s.top.sel == 1)
        // Return: the first press selects, the next opens.
        var r = onSearch()
        #expect(send(&r, .select).isEmpty && r.searchPicked && r.top.screen == .search)
        send(&r, .select)
        #expect(r.top.screen == .tracks(playlist: "focus") && r.stack.map(\.screen) == [.main, .search, .tracks(playlist: "focus")])
    }

    @Test func centerOnASongPlaysItInItsList() {
        var s = onSearch()
        send(&s, .wheel(1), .wheel(1))
        #expect(send(&s, .select).contains(.load(trackID: "f0", context: "focus", autoplay: true, generation: 1)))
        #expect(s.current == TrackRef(playlist: "focus", track: "f0") && s.top.screen == .now)
        // MENU goes back to Search, with its query and results.
        send(&s, .menu)
        #expect(s.top.screen == .search && s.searchQuery == "f" && s.searchPicked && s.top.sel == 1)
        // Offline: the toast, and nothing plays.
        var o = onSearch()
        o.offline = true
        send(&o, .wheel(1), .wheel(1))
        #expect(!send(&o, .select).contains(where: loads) && o.toast == "You’re offline right now" && o.current == nil)
    }

    @Test func playStartsTheSelectedResult() {
        // None selected: nothing.
        var s = onSearch()
        #expect(send(&s, .play).isEmpty && s.current == nil && s.top.screen == .search)
        // A playlist: from its first song.
        send(&s, .wheel(1))
        #expect(send(&s, .play).contains(.load(trackID: "f0", context: "focus", autoplay: true, generation: 1)))
        // A song: that song.
        var t = onSearch()
        send(&t, .wheel(1), .wheel(2))
        #expect(send(&t, .play).contains(.load(trackID: "f1", context: "focus", autoplay: true, generation: 1)))
        // An artist not read yet: its list opens and plays when it is read.
        var a = ready()
        a.artists = [fan]
        a.top.sel = a.rows(for: a.top).firstIndex(of: .search)!
        send(&a, .select)
        a.searchQuery = "fan"; a.searchResults = Search.results("fan", in: a)
        #expect(a.rows(for: a.top) == [.artist(fan.id)])
        send(&a, .wheel(1), .play)
        #expect(a.top.screen == .tracks(playlist: fan.id) && a.top.loading && a.startList == fan.id)
    }

    @Test func menuLeavesSearchAndClearsIt() {
        var s = onSearch()
        send(&s, .wheel(1), .menu)
        #expect(s.top.screen == .main && s.searchQuery == "" && s.searchResults.isEmpty && !s.searchPicked)
    }

    @Test func theResultsFollowTheLibraryData() {
        var s = onSearch("gold")
        #expect(s.searchResults.isEmpty)
        let gold = Track(id: "g1", title: "Gold", artist: "x", duration: 30)
        s.refreshing.insert("focus")
        send(&s, .tracksRefreshed(playlist: "focus", tracks: focus.tracks + [gold]))
        #expect(s.rows(for: s.top) == [.foundSong("g1", list: "focus")])
    }

    @Test func aLibraryChangeUnderNowPlayingShowsOnTheWayBack() {
        var s = onSearch()
        send(&s, .wheel(1), .wheel(8), .select)  // f7, the last row
        #expect(s.top.screen == .now && s.current == TrackRef(playlist: "focus", track: "f7"))
        s.refreshing.insert("focus")
        send(&s, .tracksRefreshed(playlist: "focus", tracks: Array(focus.tracks.prefix(3))))
        send(&s, .menu)
        #expect(s.top.screen == .search && s.searchQuery == "f")
        #expect(s.rows(for: s.top) == [.playlist("focus")] + ["f0", "f1", "f2"].map { .foundSong($0, list: "focus") })
        #expect(s.top.sel == 3 && s.searchPicked)
    }

    @Test func aShorterListNeverLeavesTheSelectionPastTheEnd() {
        var s = onSearch()
        send(&s, .wheel(1), .wheel(8))
        #expect(s.top.sel == 8 && s.rows(for: s.top).count == 9)
        s.refreshing.insert("focus")
        send(&s, .tracksRefreshed(playlist: "focus", tracks: Array(focus.tracks.prefix(2))))
        #expect(s.rows(for: s.top).count == 3 && s.top.sel == 2 && s.top.off <= 2 && s.searchPicked)
        // No results left: nothing is selected, and every input stays safe.
        var e = onSearch("f1")
        send(&e, .wheel(1))
        #expect(e.searchPicked && e.rows(for: e.top) == [.foundSong("f1", list: "focus")])
        e.refreshing.insert("focus")
        send(&e, .tracksRefreshed(playlist: "focus", tracks: []))
        #expect(e.searchResults.isEmpty && !e.searchPicked && e.top.sel == 0 && e.top.off == 0)
        #expect(send(&e, .wheel(1), .select, .play).isEmpty && e.top.screen == .search)
    }

    @Test func eachKindOfResultHasItsRow() {
        func row(_ kind: Search.Kind, list: String? = nil) -> Row {
            Row(Search.Result(kind: kind, id: "x", name: "X", detail: "", list: list))
        }
        #expect(row(.artist) == .artist("x") && row(.album) == .album("x") && row(.playlist) == .playlist("x"))
        #expect(row(.song, list: "focus") == .foundSong("x", list: "focus"))
        #expect(row(.song) == .foundSong("x", list: Playlist.libraryID))
    }

    // PR B: typing.

    @Test func typingFindsAndDeleteRemoves() {
        var s = ready()
        s.top.sel = s.rows(for: s.top).firstIndex(of: .search)!
        send(&s, .select, .searchType("F"), .searchType("1"))
        #expect(s.searchQuery == "F1" && s.rows(for: s.top) == [.foundSong("f1", list: "focus")] && !s.searchPicked)
        send(&s, .searchDelete)
        #expect(s.searchQuery == "F" && s.rows(for: s.top).count == 9)
        send(&s, .searchDelete, .searchDelete)  // one more than the query: nothing happens
        #expect(s.searchQuery == "" && s.searchResults.isEmpty)
    }

    @Test func typingClearsTheSelection() {
        var s = onSearch()
        send(&s, .wheel(1), .wheel(3))
        #expect(s.searchPicked && s.top.sel == 3)
        send(&s, .searchType("0"))
        #expect(s.searchQuery == "f0" && !s.searchPicked && s.top.sel == 0 && s.top.off == 0)
        send(&s, .wheel(1), .searchDelete)
        #expect(s.searchQuery == "f" && !s.searchPicked && s.top.sel == 0)
    }

    @Test func onlyLettersNumbersAndSpacesTypeUpToForty() {
        var s = onSearch("")
        for c in ["é", "ñ", "ü", "7", " ", "日"] as [Character] { send(&s, .searchType(c)) }
        #expect(s.searchQuery == "éñü7 日")
        for c in ["\r", "\t", "-", "\u{7F}", "\u{F700}"] as [Character] { send(&s, .searchType(c)) }
        #expect(s.searchQuery == "éñü7 日")
        for _ in 0..<50 { send(&s, .searchType("a")) }
        #expect(s.searchQuery.count == Search.maxQuery)
    }

    @Test func typingOffSearchDoesNothing() {
        var s = ready()
        send(&s, .searchType("a"), .searchDelete)
        #expect(s.searchQuery == "" && s.top.screen == .main)
        var t = onSearch()
        send(&t, .wheel(1), .wheel(1), .select)  // Now Playing over Search
        send(&t, .searchType("x"), .searchDelete)
        #expect(t.searchQuery == "f" && t.top.screen == .now)
    }
}

