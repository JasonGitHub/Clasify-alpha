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
        #expect(s.searchResults.map(\.name).prefix(3) == ["The Lowlights", "Low Orbit", "Sodium Glow"])
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
        s.top.sel = 1  // Low Orbit, an artist: the white chevron
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

    /// The field and the strip stay in place: the field's border at y 57 and 78, the strip's box
    /// at y 239. Five 34 point rows once pushed them out of the screen (Jason, build 458).
    func expectFieldAndStripInPlace(_ shot: Snapshot, _ name: String) {
        let x = Self.screenLeft + 200
        #expect((55...59).contains { !shot.isLight(x, $0) }, "\(name): the field's top border")
        #expect(shot.isLight(x, 68), "\(name): the white field")
        #expect((76...80).contains { !shot.isLight(x, $0) }, "\(name): the field's bottom border")
        #expect(shot.isBlue(Self.screenLeft + 140, 239), "\(name): the strip's box")
    }

    @Test func manyResultsKeepTheFieldAndTheStrip() throws {
        var s = onSearch("song")
        #expect(s.searchResults.count > 5)
        let shot = try render(s, "search-many")
        expectFieldAndStripInPlace(shot, "many")
        for row in 0..<4 { #expect(!shot.isBlue(Self.screenLeft + 200, Self.searchRowCenter(row)), "row \(row)") }
        // Scrolled to the end, with the last row selected at the bottom of the 4 that show.
        s.searchPicked = true
        s.top.sel = s.searchResults.count - 1
        s.top.off = s.top.sel - (searchRows - 1)
        let end = try render(s, "search-many-scrolled")
        expectFieldAndStripInPlace(end, "scrolled")
        #expect(end.isBlue(Self.screenLeft + 200, Self.searchRowCenter(3)))
        #expect(!end.isBlue(Self.screenLeft + 200, Self.searchRowCenter(2)))
    }
}
