import Testing
@testable import ClasifyCore

/// CLA-179 (Jason 18:19 JST, 11-24): On This Mac reads the Music app library again, quietly,
/// when the main menu opens and the last read is older than `localStaleAfter`.
@Suite struct LocalRereadTests {
    static let song = Track(id: "local:track:1", title: "Song", artist: "Band", duration: 180)
    static let added = Track(id: "local:track:2", title: "New", artist: "Band", duration: 200)
    let library = Playlist.libraryID

    func rereads(_ fx: [Effect]) -> [Effect] {
        fx.filter { switch $0 { case .refreshTracks, .refreshPlaylists: true; default: false } }
    }

    /// On This Mac's main menu, its library read at time 100.
    func onThisMac() -> AppState {
        var s = LocalNoSongsTests().signedIn(albumArt: .all)
        send(&s, .artTracksRead(token: s.artTok, playlist: library, tracks: [Self.song]))
        #expect(s.top.screen == .main && s.readAt[library] == 100)
        return s
    }

    /// Opens Settings at `now`, then goes back to the main menu at `back`.
    func backToMain(_ s: inout AppState, at back: Double) -> [Effect] {
        s.stack.append(Frame(screen: .settings))
        return send(&s, .menu, now: back)
    }

    @Test func theMainMenuRereadsTheLibraryAfterAMinute() {
        var s = onThisMac()
        #expect(rereads(backToMain(&s, at: 159)).isEmpty)  // 59 s: not yet
        #expect(rereads(backToMain(&s, at: 160)) == [.refreshTracks(playlist: library)])
        // Quiet: the main menu stays as it is while it reads.
        #expect(s.stack == [Frame(screen: .main)] && !s.top.loading && s.refreshing == [library])
        #expect(rereads(backToMain(&s, at: 230)).isEmpty)  // one read at a time
        send(&s, .tracksRefreshed(playlist: library, tracks: [Self.song, Self.added]), now: 231)
        #expect(s.tracks(in: library) == [Self.song, Self.added] && s.readAt[library] == 231)
        #expect(rereads(backToMain(&s, at: 260)).isEmpty)  // read 29 s ago
    }

    @Test func everyListReadSoFarAndThePlaylistsReadAgain() {
        var s = onThisMac()
        s.library.append(Playlist(id: "local:playlist:9", name: "Mix", tracks: [Self.song]))
        s.loadedTracks.insert("local:playlist:9"); s.readAt["local:playlist:9"] = 100
        s.playlistsLoaded = true; s.readAt[""] = 100
        #expect(rereads(backToMain(&s, at: 200))
            == [.refreshTracks(playlist: library), .refreshTracks(playlist: "local:playlist:9"), .refreshPlaylists])
    }

    @Test func thePlayingSongDoesNotStop() {
        var s = onThisMac()
        s.current = TrackRef(playlist: library, track: Self.song.id); s.isPlaying = true
        let fx = backToMain(&s, at: 200)
        send(&s, .tracksRefreshed(playlist: library, tracks: [Self.added]), now: 201)  // the playing song left
        #expect(!fx.contains { switch $0 { case .load, .stop, .pause: true; default: false } })
        #expect(s.isPlaying && s.track(s.current!) == Self.song)  // Now Playing keeps its details
    }

    @Test func anEmptyRereadShowsNoSongsAndSongsLeaveIt() {
        var s = onThisMac()
        _ = backToMain(&s, at: 200)
        send(&s, .tracksRefreshed(playlist: library, tracks: []), now: 201)
        #expect(s.stack == [Frame(screen: .noSongs)])
        send(&s, .select, now: 202)  // Check again
        send(&s, .tracksRefreshed(playlist: library, tracks: [Self.song]), now: 203)
        #expect(s.stack == [Frame(screen: .main)])
    }

    @Test func spotifyAndAppleMusicDoNotChange() {
        for service in [MusicService.spotify, .appleMusic] {
            var s = mainMenu()
            s.service = service; s.words = service == .spotify ? .spotify : .appleMusic
            s.library.append(Playlist(id: library, name: "", tracks: [Self.song]))
            s.loadedTracks = [library, "focus"]; s.readAt = [library: 100, "focus": 100]
            s.playlistsLoaded = true; s.readAt[""] = 100
            #expect(rereads(backToMain(&s, at: 1000)).isEmpty, "\(service)")
        }
    }
}
