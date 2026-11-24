import Foundation
import Testing
@testable import ClasifyCore

/// Card CR, part (b): a local song whose file is missing shows gray, a press shows a toast, and
/// play skips it. A library where every file is missing shows "Your music is on a drive".
@Suite struct LocalMissingTests {
    /// Focus with its first two songs missing.
    static let songs: [Track] = tracks("f", 4, 30).enumerated().map { i, t in
        var t = t; t.missing = i < 2; return t
    }

    func onFocus(_ songs: [Track] = Self.songs) -> AppState {
        var s = mainMenu()
        send(&s, .wheel(1), .select, .playlistsLoaded(token: 1, playlists: [focusInfo]),
             .select, .tracksLoaded(token: 2, playlist: "focus", tracks: songs))
        #expect(s.top.screen == .tracks(playlist: "focus"))
        return s
    }

    @Test func theCatalogKeepsAMissingSongAndPlaySkipsIt() {
        var gone = LocalCatalogTests.item(2, "Gone", number: 2); gone.missing = true
        let catalog = LocalCatalog(
            songs: [LocalCatalogTests.item(1, "A", number: 1), gone, LocalCatalogTests.item(3, "C", number: 3)],
            lists: [LocalList(persistentID: 9, name: "Mix", items: [2, 3])])
        #expect(catalog.library.map(\.missing) == [false, true, false])
        #expect(catalog.track(LocalID.track(2))?.missing == true)
        #expect(catalog.tracks(of: LocalID.playlist(9))?.count == 2)  // a list of a missing song stays
        #expect(catalog.items(context: Playlist.libraryID, track: LocalID.track(1))?.map(\.id)
            == [LocalID.track(1), LocalID.track(3)])
    }

    @Test func aGrayRowShowsTheToastAndPlaysNothing() {
        var s = onFocus()
        #expect(!send(&s, .select).contains { if case .load = $0 { true } else { false } })
        #expect(s.toast == "Can’t find this song’s file" && s.current == nil && s.top.screen == .tracks(playlist: "focus"))
        send(&s, .wheel(2))
        #expect(send(&s, .select).contains(.load(trackID: "f2", context: "focus", autoplay: true, generation: 1)))
    }

    @Test func aListStartsOnItsFirstSongThatCanPlay() {
        var s = onFocus()
        send(&s, .menu)  // back on Playlists, on Focus
        #expect(send(&s, .play).contains(.load(trackID: "f2", context: "focus", autoplay: true, generation: 1)))
        // Every song missing: Play opens the list, with its gray rows, and plays nothing.
        var all = onFocus(Self.songs.map { var t = $0; t.missing = true; return t })
        send(&all, .menu)
        #expect(!send(&all, .play).contains { if case .load = $0 { true } else { false } })
        #expect(all.top.screen == .tracks(playlist: "focus") && all.current == nil)
    }

    @Test func shuffleNeverStartsOnAMissingSong() {
        var s = onFocus()
        send(&s, .menu)
        s.shuffle = true  // the test's random pick is 0: the first song that can play
        #expect(send(&s, .play).contains(.load(trackID: "f2", context: "focus", autoplay: true, generation: 1)))
    }

    @Test func everyFileMissingShowsOnADrive() {
        var s = LocalNoSongsTests().signedIn(albumArt: .all)
        let gone = Track(id: "local:track:1", title: "Song", artist: "Band", duration: 180, missing: true)
        send(&s, .artTracksRead(token: s.artTok, playlist: Playlist.libraryID, tracks: [gone]))
        #expect(s.localEmpty && s.localOnDrive && s.stack == [Frame(screen: .noSongs)])
        #expect(s.rows(for: s.top) == [.checkLibrary, .pickYourMusic])
        // The drive is back: Check again finds the files, and the main menu shows.
        send(&s, .select)
        var back = gone; back.missing = false
        send(&s, .tracksRefreshed(playlist: Playlist.libraryID, tracks: [back]))
        #expect(!s.localEmpty && !s.localOnDrive && s.stack == [Frame(screen: .main)])
        // An empty library is "No songs yet", not on a drive.
        var empty = LocalNoSongsTests().signedIn(albumArt: .all)
        send(&empty, .artTracksRead(token: empty.artTok, playlist: Playlist.libraryID, tracks: []))
        #expect(empty.localEmpty && !empty.localOnDrive)
    }
}
