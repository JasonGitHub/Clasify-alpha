import Testing
@testable import ClasifyCore

/// CLA-97, A2c: `use_error`, `app_speed` and `service_switch`.
@Suite struct UseEventTests {
    func events(_ s: inout AppState, _ actions: Action..., now: Double = 100) -> [BetaEvent] {
        let e = Dependencies(now: { now }, random: { _ in 0 })
        return actions.flatMap { reduce(&s, $0, e) }.compactMap { (fx: Effect) -> BetaEvent? in
            if case .track(let event) = fx { return event }
            return nil
        }
    }

    @Test func aLoginAfterSetupThatFailsSendsUseError() {
        var s = afterSetup()
        _ = events(&s, .select)
        #expect(events(&s, .authDone(token: s.authAttempt, ok: false)) == [.useError(.loginFailed, offline: false, service: .spotify)])
        var setup = AppState()  // in setup it is a setup error, not a use error
        _ = events(&setup, .spotifyAppFound(true), .launch, .restored(token: 1, ok: false), .select, .select, .select, .select)
        #expect(!events(&setup, .authDone(token: 2, ok: false)).contains { if case .useError = $0 { true } else { false } })
    }

    @Test func aListThatDoesNotLoadAndASongThatDoesNotPlaySendUseError() {
        var s = mainMenu()
        _ = events(&s, .wheel(1), .select)
        #expect(events(&s, .playlistsLoaded(token: 1, playlists: nil)) == [.useError(.listNotLoaded, offline: false, service: .spotify)])
        #expect(events(&s, .wheel(1)).isEmpty)  // the same error: once
        var p = playing(2)
        _ = events(&p, .position(40, generation: 1), .menu, .wheel(3), .select)
        #expect(events(&p, .loadFailed("Old", generation: 1)).isEmpty)  // an earlier load
        #expect(events(&p, .loadFailed("That didn’t play", generation: 2)) == [.useError(.songNotPlayed, offline: false, service: .spotify)])
        #expect(BetaEvent.useError(.listNotLoaded, offline: true, service: .appleMusic).properties
            == ["kind": .text("list_not_loaded"), "offline": .flag(true), "service": .text("apple_music")])
    }

    @Test func theFirstLibraryReadOfALaunchSendsAppSpeedOnce() {
        var s = afterSetup()
        _ = events(&s, .appStarted(ms: 850), now: 99)
        _ = events(&s, .launch, now: 100)
        #expect(s.launchedAt == 100 && s.startMs == 850)
        #expect(events(&s, .playlistsLoaded(token: 9, playlists: nil), now: 101).isEmpty)  // a failed read
        #expect(events(&s, .playlistsRefreshed([focusInfo]), now: 101.1).isEmpty)  // not asked for: not taken
        s.artReads[Playlist.likedSongsID] = 4  // the main menu's cover read (Codex on #350)
        #expect(events(&s, .artTracksRead(token: 3, playlist: Playlist.likedSongsID, tracks: []), now: 101.2).isEmpty)  // stale
        #expect(events(&s, .artTracksRead(token: 4, playlist: Playlist.likedSongsID, tracks: []), now: 101.25)
            == [.appSpeed(startMs: 850, libraryMs: 1250)])
        s.refreshing.insert(AppState.readKey(.playlists))
        #expect(events(&s, .playlistsRefreshed([focusInfo]), now: 102).isEmpty && s.speedSent)
        var setup = AppState()  // a launch in setup sends none
        _ = events(&setup, .launch)
        #expect(setup.launchedAt == nil)
        #expect(BetaEvent.appSpeed(startMs: nil, libraryMs: 5).properties == ["library_ms": .number(5)])
    }

    @Test func aServiceChangeAfterSetupSendsServiceSwitch() {
        var s = playing()
        for _ in 0..<8 where s.top.screen != .main { _ = events(&s, .menu) }
        s.top.sel = s.rows(for: s.top).firstIndex(of: .settings) ?? -1
        _ = events(&s, .select, .select)  // Settings, then the Service row flips
        #expect(events(&s, .menu).contains(.serviceSwitch(from: .spotify, to: .appleMusic)))
        #expect(BetaEvent.serviceSwitch(from: .spotify, to: .appleMusic).properties == ["from": .text("spotify"), "to": .text("apple_music")])
    }
}
