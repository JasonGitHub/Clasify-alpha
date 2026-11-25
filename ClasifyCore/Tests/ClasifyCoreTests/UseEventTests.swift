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
        #expect(events(&s, .playlistsLoaded(token: 9, playlists: nil), now: 101).isEmpty)  // a stale read: not taken
        #expect(events(&s, .playlistsRefreshed([focusInfo]), now: 101.1).isEmpty)  // not asked for: not taken
        s.artReads[Playlist.likedSongsID] = 4  // the main menu's cover read (Codex on #350)
        #expect(events(&s, .artTracksRead(token: 3, playlist: Playlist.likedSongsID, tracks: []), now: 101.2).isEmpty)  // stale
        #expect(events(&s, .artTracksRead(token: 4, playlist: Playlist.likedSongsID, tracks: []), now: 101.25)
            == [.appSpeed(startMs: 850, libraryMs: 1250, loaded: true, songs: 0)])
        s.refreshing.insert(AppState.readKey(.playlists))
        #expect(events(&s, .playlistsRefreshed([focusInfo]), now: 102).isEmpty && s.speedSent)
        var artists = mainMenu()  // Apple Music: the Artists read counts too (Codex on #350)
        _ = events(&artists, .libraryWords(.appleMusic), .wheel(2), .select, now: 100)
        artists.launchedAt = 100
        #expect(events(&artists, .artistsLoaded(token: 9, artists: LibraryRowsTests.artists), now: 100.5).isEmpty)  // stale
        #expect(events(&artists, .artistsLoaded(token: 1, artists: LibraryRowsTests.artists), now: 100.5)
            == [.appSpeed(startMs: nil, libraryMs: 500, loaded: true)])
        var setup = AppState()  // a launch in setup sends none
        _ = events(&setup, .launch)
        #expect(setup.launchedAt == nil)
        var failed = mainMenu()  // a failed first read that the app took counts too (Jason 23:57 JST)
        _ = events(&failed, .wheel(1), .select, now: 100)
        failed.launchedAt = 100
        #expect(events(&failed, .playlistsLoaded(token: 1, playlists: nil), now: 100.75)
            == [.useError(.listNotLoaded, offline: false, service: .spotify), .appSpeed(startMs: nil, libraryMs: 750, loaded: false)])
        #expect(failed.speedSent)
        #expect(BetaEvent.appSpeed(startMs: nil, libraryMs: 5, loaded: false).properties == ["library_ms": .number(5), "loaded": .flag(false)])
    }

    /// CLA-186: `app_speed` has the library's size as read so far, from memory only.
    @Test func appSpeedHasTheCountsThatAreRead() {
        var s = afterSetup()
        _ = events(&s, .launch, now: 100)
        _ = events(&s, .select, .authDone(token: s.authAttempt, ok: true), .select)
        s.artReads[Playlist.likedSongsID] = 4  // Spotify: the main menu's cover read of the liked songs
        #expect(events(&s, .artTracksRead(token: 4, playlist: Playlist.likedSongsID, tracks: liked.tracks), now: 101)
            == [.appSpeed(startMs: nil, libraryMs: 1000, loaded: true, songs: 2)])  // the playlists are not read
        var lists = mainMenu()  // Playlists first: the playlists, no songs
        lists.launchedAt = 100
        _ = events(&lists, .wheel(1), .select)
        #expect(events(&lists, .playlistsLoaded(token: 1, playlists: [focusInfo]), now: 100.5)
            == [.appSpeed(startMs: nil, libraryMs: 500, loaded: true, playlists: 1)])
        var apple = mainMenu()  // Apple Music: the library's songs; the hidden lists do not count
        _ = events(&apple, .libraryWords(.appleMusic))
        apple.library = [focusInfo, Playlist(id: Playlist.likedSongsID, name: "", tracks: [])]; apple.playlistsLoaded = true
        apple.launchedAt = 100
        apple.artReads[Playlist.libraryID] = 7
        #expect(events(&apple, .artTracksRead(token: 7, playlist: Playlist.libraryID, tracks: focus.tracks), now: 100.5)
            == [.appSpeed(startMs: nil, libraryMs: 500, loaded: true, playlists: 1, songs: 8)])
        var failed = mainMenu()  // a failed read: no counts
        failed.library = [focusInfo]; failed.playlistsLoaded = true
        failed.launchedAt = 100
        failed.artReads[Playlist.likedSongsID] = 4
        #expect(events(&failed, .artTracksRead(token: 4, playlist: Playlist.likedSongsID, tracks: nil), now: 100.5)
            == [.appSpeed(startMs: nil, libraryMs: 500, loaded: false)])
        #expect(BetaEvent.appSpeed(startMs: 1, libraryMs: 5, loaded: true, playlists: 3, songs: 40).properties
            == ["start_ms": .number(1), "library_ms": .number(5), "loaded": .flag(true), "playlists": .number(3), "songs": .number(40)])
    }

    @Test func aServiceChangeAfterSetupSendsServiceSwitch() {
        var s = playing()
        for _ in 0..<8 where s.top.screen != .main { _ = events(&s, .menu) }
        s.top.sel = s.rows(for: s.top).firstIndex(of: .settings) ?? -1
        _ = events(&s, .select, .select)  // Settings, then the Service row flips
        #expect(events(&s, .menu).contains(.serviceSwitch(from: .spotify, to: .appleMusic)))
        #expect(BetaEvent.serviceSwitch(from: .spotify, to: .appleMusic).properties == ["from": .text("spotify"), "to": .text("apple_music")])
    }

    @Test func aServiceSwitchEndsTheOldServicesLossWithNoControlBack() {
        var s = playing()
        _ = events(&s, .controlLost(.spotifyQuit))
        for _ in 0..<8 where s.top.screen != .main { _ = events(&s, .menu) }
        s.top.sel = s.rows(for: s.top).firstIndex(of: .settings) ?? -1
        _ = events(&s, .select, .select, .menu)  // the Service row flips to Apple Music
        #expect(s.controlLostAt == nil && events(&s, .controlBack).isEmpty)
        #expect(events(&s, .controlLost(.appleMusicError)) == [.controlLost(.appleMusicError, service: .appleMusic)])
    }
}
