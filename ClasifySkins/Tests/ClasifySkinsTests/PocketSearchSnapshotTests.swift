import ClasifyCore
import Testing

@testable import ClasifySkins

/// CLA-183, card CS: snapshots of the Search screen. Points: the field from y 57 to 79, the 34
/// point result rows from y 83, and the letter strip's blue box from x 169 to 197 and y 227 to
/// 252, with a white A in its middle.
extension PocketSnapshotTests {
    static func searchRowCenter(_ index: Int) -> Int { 83 + 17 + 34 * index }

    /// Search over the main menu, with `query` typed and its results.
    func onSearch(_ query: String) -> AppState {
        var s = sampleState()
        s.searchOn = true
        s.artists = [Playlist(id: "spotify:artist:low", name: "The Lowlights", tracks: []),
                     Playlist(id: "spotify:artist:orbit", name: "Low Orbit", tracks: [])]
        s.library[1].tracks[0] = Track(id: "spotify:track:glow", title: "Sodium Glow", artist: "Hana & the Static", duration: 200)
        s.loadedTracks = [Playlist.likedSongsID, "spotify:playlist:a"]
        s.stack = [Frame(screen: .main), Frame(screen: .search)]
        s.searchQuery = query
        s.searchIndex = Search.Index(s)
        s.searchResults = s.searchIndex?.results(query) ?? []
        return s
    }

    @Test func searchMainMenuRow() throws {
        var s = sampleState()
        s.searchOn = true
        s.albumArt = .off
        s.top.sel = try #require(s.rows(for: s.top).firstIndex(of: .search))
        let shot = try render(s, "search-menu-row")
        #expect(shot.isBlue(Self.screenLeft + 200, Self.rowCenter(s.top.sel)))
        #expect(Labels.row(.search, on: .main, in: s).label == "Search")
    }

    @Test func searchEmpty() throws {
        let s = onSearch("")
        let shot = try render(s, "search-empty")
        #expect(shot.isLight(Self.screenLeft + 200, 68))  // the white field
        #expect(shot.isBlue(Self.screenLeft + 140, 239))  // the strip's box, left of its white A
        #expect(!shot.isBlue(Self.screenLeft + 150, Self.searchRowCenter(0)))
        #expect(Labels.searchEmpty == Labels.SearchWords(title: "Type to search", line: "Find songs, albums, artists and playlists."))
    }

    @Test func searchTypedNoneSelected() throws {
        let s = onSearch("lo")
        // #460: rows sort like the library lists, where "The" does not count ("low orbit" < "lowlights")
        #expect(s.searchResults.map(\.name).prefix(3) == ["Low Orbit", "The Lowlights", "Sodium Glow"])
        #expect(!s.searchPicked)
        let shot = try render(s, "search-typed")
        for row in 0..<3 { #expect(!shot.isBlue(Self.screenLeft + 200, Self.searchRowCenter(row)), "row \(row)") }
    }

    @Test func searchSelectedSongAndList() throws {
        var s = onSearch("lo")
        s.searchPicked = true
        s.top.sel = 2  // Sodium Glow, a song: no chevron
        let song = try render(s, "search-selected-song")
        #expect(song.isBlue(Self.screenLeft + 200, Self.searchRowCenter(2)))
        #expect(!song.isLight(Self.screenLeft + 289, Self.searchRowCenter(2)))
        s.top.sel = 1  // The Lowlights, an artist: the white chevron
        let list = try render(s, "search-selected-artist")
        #expect(list.isBlue(Self.screenLeft + 200, Self.searchRowCenter(1)))
        var white = false
        for x in Self.screenLeft + 280..<Self.screenLeft + 292 where list.isLight(x, Self.searchRowCenter(1)) { white = true }
        #expect(white)
    }

    @Test func searchNoMatches() throws {
        let s = onSearch("zzq")
        #expect(s.searchResults.isEmpty)
        _ = try render(s, "search-no-match")
        #expect(Labels.searchNoMatch == Labels.SearchWords(title: "Hmm, no luck", line: "We searched your library."))
    }
}
