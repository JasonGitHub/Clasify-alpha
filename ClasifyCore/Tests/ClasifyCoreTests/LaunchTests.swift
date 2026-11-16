import Testing
@testable import ClasifyCore

/// CLA-120 (Jason, 11:57 JST 11-16: "upon cold open, the main menu is pushed in?"): after
/// setup, a launch opens on the main menu at once, with no slide. The stored login is checked
/// behind it, and its failures show the same screens as before.
@Suite struct LaunchTests {
    @Test func aLaunchAfterSetupOpensOnTheMainMenu() {
        var s = afterSetup()
        #expect(send(&s, .spotifyAppFound(true), .launch) == [.restoreSession(token: 1)])  // no cover read before the login
        #expect(s.stack == [Frame(screen: .main)] && s.restoring && !s.signedIn && s.navSeq == 0)
        #expect(send(&s, .restored(token: 1, ok: true)) == [.prefetch, .readArtTracks(token: 1, playlist: Playlist.likedSongsID)])
        #expect(s.stack == [Frame(screen: .main)] && s.signedIn && s.navSeq == 0)  // nothing slides in
    }

    @Test func aFailedRestoreShowsTheLoginScreen() {
        var s = afterSetup()
        send(&s, .launch, .wheel(1), .select)  // Playlists opens, waiting
        #expect(send(&s, .restored(token: 1, ok: false)).isEmpty)
        #expect(s.stack == [Frame(screen: .login)] && !s.signedIn && s.rows(for: s.top) == [.logIn])
    }

    /// A list opened before the login is back waits in its loading state. Its read starts with
    /// the login, and its result lands.
    @Test func aListOpenedWhileRestoringReadsWhenTheLoginIsBack() {
        var s = afterSetup()
        #expect(send(&s, .launch, .wheel(1), .select) == [.restoreSession(token: 1)])
        #expect(s.top.screen == .playlists && s.top.loading)
        let fx = send(&s, .restored(token: 1, ok: true))
        #expect(fx.first == .prefetch && fx.contains(.fetchPlaylists(token: s.top.token)))
        send(&s, .playlistsLoaded(token: s.top.token, playlists: [focusInfo]))
        #expect(s.top.screen == .playlists && !s.top.loading && s.rows(for: s.top) == [.playlist("focus")])
    }

    @Test func aStoredFreeLoginShowsThePremiumScreen() {
        var s = afterSetup()
        send(&s, .launch, .notPremium(token: 1))
        #expect(s.stack == [Frame(screen: .premium)] && !s.restoring)
    }

    @Test func appleMusicWithAccessOffShowsItsScreen() {
        var s = afterSetup()
        s.service = .appleMusic
        send(&s, .launch, .accessDenied(token: 1))
        #expect(s.stack == [Frame(screen: .accessOff)] && !s.restoring)
    }

    /// With the Spotify app missing, the login screen stays at launch, and the restore goes on
    /// to the Spotify App screen, as before.
    @Test func aMissingSpotifyAppKeepsTheLoginScreen() {
        var s = afterSetup()
        send(&s, .spotifyAppFound(false), .launch)
        #expect(s.stack == [Frame(screen: .login)] && s.restoring)
        send(&s, .restored(token: 1, ok: true))
        #expect(s.stack == [Frame(screen: .spotifyApp)])
    }

    /// Settings > Log out works before the stored login is back. Its late result is stale then
    /// (Codex on #254).
    @Test func aLogOutWhileRestoringDropsTheLateRestore() {
        var s = afterSetup()
        send(&s, .spotifyAppFound(true), .launch, .wheel(5), .select, .wheel(8), .select, .wheel(1), .select)
        #expect(s.stack == [Frame(screen: .login)] && !s.restoring)
        #expect(send(&s, .restored(token: 1, ok: true)).isEmpty)
        #expect(s.stack == [Frame(screen: .login)] && !s.signedIn)
        send(&s, .notPremium(token: 1))  // nor a late Premium result
        #expect(s.stack == [Frame(screen: .login)])
    }

    /// Settings > Service before the stored login is back: the switch starts its own restore, so
    /// the old service's late result is stale (CTO on #254).
    @Test func aServiceSwitchWhileRestoringDropsTheOldRestore() {
        var s = afterSetup()
        send(&s, .spotifyAppFound(true), .launch)
        s.top.sel = s.rows(for: s.top).firstIndex(of: .settings) ?? -1
        send(&s, .select, .select)  // Settings, then the Service row: Apple Music
        #expect(send(&s, .menu) == [.setService(.appleMusic), .restoreSession(token: 2)])
        #expect(s.service == .appleMusic && s.top.screen == .login && s.restoring && s.authAttempt == 2)
        // The old Spotify restore answers late: dropped, for each of its results.
        #expect(send(&s, .restored(token: 1, ok: true), .notPremium(token: 1), .accessDenied(token: 1)).isEmpty)
        #expect(s.top.screen == .login && !s.signedIn && s.restoring)
        send(&s, .restored(token: 2, ok: true))
        #expect(s.stack.map(\.screen) == [.main] && s.signedIn && s.service == .appleMusic)
    }

    /// The first launch ever still opens on Hello.
    @Test func theFirstLaunchStillOpensOnHello() {
        var s = AppState()
        send(&s, .launch)
        #expect(s.stack == [Frame(screen: .hello)])
    }
}
