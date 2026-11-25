import Testing
@testable import ClasifyCore

/// CLA-190: `use_error` `list_not_loaded` says the kind of list and the engine's error number.
@Suite struct ListNotLoadedTests {
    func events(_ s: inout AppState, _ actions: Action...) -> [BetaEvent] {
        let e = Dependencies(now: { 100 }, random: { _ in 0 })
        return actions.flatMap { reduce(&s, $0, e) }.compactMap { (fx: Effect) -> BetaEvent? in
            if case .track(let event) = fx { return event }
            return nil
        }
    }

    /// Playlists opens and reads with token 1.
    func openPlaylists() -> AppState {
        var s = mainMenu()
        _ = events(&s, .wheel(1), .select)
        return s
    }

    @Test func aFailedReadSaysTheListAndTheErrorNumber() {
        var s = openPlaylists()
        let sent = events(&s, .readFailed(token: 1, status: 7), .playlistsLoaded(token: 1, playlists: nil))
        #expect(sent == [.useError(.listNotLoaded, offline: false, service: .spotify, list: "playlists", status: 7)])
        #expect(sent.first?.properties == ["kind": .text("list_not_loaded"), "offline": .flag(false), "service": .text("spotify"),
                                           "list": .text("playlists"), "status": .number(7)])
    }

    @Test func anUnknownNumberOrAStaleReadLeavesTheNumberOut() {
        var s = openPlaylists()
        #expect(events(&s, .readFailed(token: 1, status: nil), .playlistsLoaded(token: 1, playlists: nil))
            == [.useError(.listNotLoaded, offline: false, service: .spotify, list: "playlists")])
        s = openPlaylists()
        _ = events(&s, .readFailed(token: 9, status: 7))  // an older read
        #expect(s.top.failStatus == nil)
        #expect(events(&s, .playlistsLoaded(token: 1, playlists: nil)).first?.properties["status"] == nil)
    }

    /// Codex on #481: a retry whose read worked, shown as failed only because the Mac went
    /// offline, does not say the number of the attempt before.
    @Test func aRetryThatReadsDoesNotKeepTheOldNumber() {
        var s = openPlaylists()
        _ = events(&s, .readFailed(token: 1, status: 7), .playlistsLoaded(token: 1, playlists: nil))
        _ = events(&s, .select)  // retry
        #expect(s.top.loading && s.top.failStatus == nil)  // cleared where the retry starts
        _ = events(&s, .offline(true))
        let sent = events(&s, .playlistsLoaded(token: s.top.token, playlists: [focusInfo]))
        #expect(s.top.error && s.top.failStatus == nil)
        #expect(!sent.contains { $0.properties["status"] != nil })
    }

    @Test func otherUseErrorsHaveNeitherField() {
        let p = BetaEvent.useError(.songNotPlayed, offline: false, service: .spotify).properties
        #expect(p["list"] == nil && p["status"] == nil)
    }

    @Test func theKindOfListIsNeverItsNameOrID() {
        let kinds: [(Screen, String?)] = [
            (.playlists, "playlists"), (.artists, "artists"), (.albums, "liked"), (.coverFlow, "liked"), (.yourMusic, "liked"),
            (.tracks(playlist: Playlist.likedSongsID), "liked"), (.tracks(playlist: Playlist.songsID), "songs"),
            (.tracks(playlist: Playlist.libraryID), "songs"), (.tracks(playlist: "spotify:album:abc"), "album"),
            (.albumPanel(album: "spotify:album:abc"), "album"), (.tracks(playlist: "spotify:artist:abc"), "artist"),
            (.tracks(playlist: "spotify:playlist:My secret list"), "playlist"), (.main, nil), (.settings, nil),
        ]
        let s = AppState()
        for (screen, kind) in kinds { #expect(s.listKind(screen) == kind, "\(screen)") }
    }

    /// Codex on #481: on Apple Music, Albums and Cover Flow read the library's songs, not liked songs.
    @Test func appleMusicAlbumsReadTheLibrarysSongs() {
        var s = AppState()
        s.words = .appleMusic
        for screen: Screen in [.albums, .coverFlow] { #expect(s.listKind(screen) == "songs", "\(screen)") }
    }

    /// The store asks the library for the number of a read that came back empty-handed.
    @MainActor @Test func theStoreSendsTheLibrarysNumberBeforeTheFailedResult() async {
        let lib = FakeLibrary()
        lib.failing = 42
        let store = Store(player: FakePlayer(), library: lib, state: mainMenu(), env: Dependencies(now: { 100 }, random: { _ in 0 }))
        var sent: [BetaEvent] = []
        store.onBetaEvent = { sent.append($0) }
        store.send(.wheel(1))
        store.send(.select)
        while store.state.top.loading { await Task.yield() }
        #expect(sent.contains(.useError(.listNotLoaded, offline: false, service: .spotify, list: "playlists", status: 42)))
    }
}
