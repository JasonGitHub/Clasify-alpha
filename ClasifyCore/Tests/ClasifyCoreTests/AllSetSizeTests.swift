import Testing
@testable import ClasifyCore

/// CLA-197 (Jason 21:36 JST 11-26): `all_set` says the active service's library size, from the
/// prefetch count (CLA-194). It waits for the count when the setup ends first, and goes out once.
@Suite struct AllSetSizeTests {
    func events(_ s: inout AppState, _ actions: Action..., now: Double = 130) -> [BetaEvent] {
        let e = Dependencies(now: { now }, random: { _ in 0 })
        return actions.flatMap { reduce(&s, $0, e) }.compactMap { (fx: Effect) -> BetaEvent? in
            if case .track(let event) = fx { return event }
            return nil
        }
    }

    /// The first setup up to "Getting your music" on `service`, launched at 100.
    func gettingMusic(_ service: MusicService) -> AppState {
        var s = activatedMac()
        _ = events(&s, .spotifyAppFound(true), .launch, now: 100)
        _ = events(&s, .restored(token: 1, ok: false), .select, .select, now: 110)  // Pick Your Music
        let row = s.rows(for: s.top).firstIndex(of: .pickService(service)) ?? 0
        _ = events(&s, .wheel(row), .select, now: 120)
        if s.top.screen == .login { _ = events(&s, .select, now: 120) }  // Spotify: the browser login
        _ = events(&s, .authDone(token: s.top.token, ok: true), now: 121)
        _ = events(&s, .tick, now: 125)
        _ = events(&s, .playlistsRefreshed([focusInfo]), now: 126)
        return s
    }

    /// The first read that ends the setup.
    func endSetup(_ s: inout AppState, now: Double = 130) -> [BetaEvent] {
        events(&s, .tracksLoaded(token: s.top.token, playlist: s.albumsList, tracks: liked.tracks), now: now)
    }

    var count: LibraryCount { LibraryCount(playlists: [focusInfo, focusInfo, focusInfo], songs: tracks("c", 5, 10)) }

    @Test func allSetSaysTheCountOfEachService() {
        for service in MusicService.allCases {
            var s = gettingMusic(service)
            #expect(s.service == service && s.top.screen == .yourMusic, "\(service)")
            _ = events(&s, .libraryCounted(count))
            let sent = endSetup(&s)
            #expect(s.setupDone, "\(service)")
            #expect(sent == [.setupStep(.allSet, seconds: 30, service: service, playlists: 3, songs: 5)], "\(service)")
            #expect(sent.first?.properties == ["step": .text("all_set"), "service": .text(service.eventName), "seconds": .number(30),
                                               "playlists": .number(3), "songs": .number(5)])
        }
    }

    @Test func allSetWaitsForTheCountThenGoesOutOnce() {
        var s = gettingMusic(.spotify)
        #expect(endSetup(&s).isEmpty && s.setupDone && s.heldAllSet != nil)
        #expect(events(&s, .tick, now: 140).isEmpty)
        // The time is the setup's end, not the count's.
        #expect(events(&s, .libraryCounted(count), now: 150) == [.setupStep(.allSet, seconds: 30, service: .spotify, playlists: 3, songs: 5)])
        #expect(s.heldAllSet == nil)
        #expect(events(&s, .libraryCounted(count)).isEmpty)
        #expect(!events(&s, .willQuit(openSeconds: 60)).contains { $0.name == "setup_step" })
    }

    @Test func aQuitBeforeTheCountSendsAllSetWithWhatMemoryHas() {
        var s = gettingMusic(.spotify)
        _ = endSetup(&s)
        let sent = events(&s, .willQuit(openSeconds: 60))
        #expect(sent.contains(.setupStep(.allSet, seconds: 30, service: .spotify, playlists: 1, songs: 2)))
        #expect(s.heldAllSet == nil)
        #expect(events(&s, .libraryCounted(count)).isEmpty)  // never twice
    }

    @Test func aServiceChangeBeforeTheCountSendsAllSetWithoutTheOtherServicesCount() {
        var s = gettingMusic(.spotify)
        _ = endSetup(&s)
        _ = events(&s, .tick, now: 140)  // the main menu
        for _ in 0..<8 where s.top.screen != .main { _ = events(&s, .menu) }
        s.top.sel = s.rows(for: s.top).firstIndex(of: .settings) ?? -1
        _ = events(&s, .select, .select)
        let sent = events(&s, .menu)  // the Service row flips to Apple Music
        #expect(s.service == .appleMusic)
        #expect(sent.contains(.setupStep(.allSet, seconds: 30, service: .spotify, playlists: 1, songs: 2)) && s.heldAllSet == nil)
        #expect(events(&s, .libraryCounted(count)).isEmpty)
    }
}
