import Testing
@testable import ClasifyCore

/// The first launch setup (Round 13, CLA-50): Hello, the color pick, the login, the Spotify app
/// (only when it is missing) and the first library read, then the main menu.
@Suite struct SetupTests {
    /// The first launch, on the color pick, after the restore found no stored login.
    func onColor() -> AppState {
        var s = AppState()
        send(&s, .launch, .restored(token: 1, ok: false), .select)
        return s
    }

    @Test func aFirstLaunchShowsHelloThenTheColorPick() {
        var s = AppState()
        #expect(send(&s, .launch) == [.restoreSession(token: 1)])
        #expect(s.stack == [Frame(screen: .hello)] && s.restoring && s.navSeq == 0)  // the first screen does not slide in
        #expect(send(&s, .wheel(1), .menu, .restored(token: 1, ok: false)).isEmpty)
        #expect(s.stack == [Frame(screen: .hello)])  // a turn and MENU do nothing on Hello
        send(&s, .select)  // a press begins setup
        #expect(s.stack == [Frame(screen: .color)] && s.navForward)
        #expect(s.rows(for: s.top) == [.color(.silver), .color(.black)] && s.top.sel == 0)
        send(&s, .menu)  // MENU does nothing on the color pick
        #expect(s.top.screen == .color)
    }

    @Test func theColorPickSavesTheColorAndMenuOnTheLoginGoesBack() {
        var s = onColor()
        send(&s, .wheel(1), .select)
        #expect(s.deviceColor == .black && s.top.screen == .login && s.rows(for: s.top) == [.logIn])
        send(&s, .menu)  // back to the color pick, with Black selected
        #expect(s.top.screen == .color && s.top.sel == 1 && !s.navForward)
        send(&s, .reset, .launch, .restored(token: 2, ok: false), .select)  // a reset keeps the settings
        #expect(s.top.screen == .color && s.top.sel == 1)  // the pick starts on the color that is set
    }

    @Test func aLoginInSetupReadsTheLibraryThenOpensTheMainMenu() {
        var s = onColor()
        #expect(send(&s, .select, .select) == [.logIn(token: 2)])
        let fx = send(&s, .authDone(token: 2, ok: true))
        #expect(fx == [.prefetch, .fetchTracks(token: 1, playlist: Playlist.likedSongsID)])
        #expect(s.stack == [Frame(screen: .yourMusic, loading: true, token: 1)] && s.signedIn && s.navForward)
        #expect(s.toast == "" && !s.setupDone)
        send(&s, .tracksLoaded(token: 1, playlist: Playlist.likedSongsID, tracks: liked.tracks))
        #expect(s.stack == [Frame(screen: .main)] && s.setupDone && s.loadedTracks == [Playlist.likedSongsID])
    }

    @Test func aFailedFirstReadShowsTheErrorAndRetries() {
        var s = onColor()
        send(&s, .select, .select, .authDone(token: 2, ok: true), .tracksLoaded(token: 1, playlist: Playlist.likedSongsID, tracks: nil))
        #expect(s.top.screen == .yourMusic && s.top.error && !s.setupDone)
        #expect(send(&s, .select) == [.fetchTracks(token: 2, playlist: Playlist.likedSongsID)])
        send(&s, .tracksLoaded(token: 2, playlist: Playlist.likedSongsID, tracks: liked.tracks))
        #expect(s.stack == [Frame(screen: .main)] && s.setupDone)
    }

    @Test func aStoredLoginSkipsTheLoginStep() {
        var s = AppState()
        send(&s, .launch, .restored(token: 1, ok: true))
        #expect(s.stack == [Frame(screen: .hello)] && s.signedIn)  // Hello stays until the press
        send(&s, .select, .select)
        #expect(s.top.screen == .yourMusic)
        // The restore ends while the login screen waits for it: setup goes on.
        s = AppState()
        send(&s, .launch, .select, .select)
        #expect(s.top.screen == .login && s.restoring && s.rows(for: s.top).isEmpty)
        send(&s, .restored(token: 1, ok: true))
        #expect(s.top.screen == .yourMusic && s.navForward)
    }

    @Test func theSpotifyAppScreenShowsOnlyWhenTheAppIsMissing() {
        var s = onColor()
        send(&s, .spotifyAppFound(false), .select, .select, .authDone(token: 2, ok: true))
        #expect(s.stack == [Frame(screen: .spotifyApp)] && s.spotifyApp == false)
        send(&s, .menu, .select, .wheel(1), .spotifyAppFound(false))  // MENU does nothing, and the check goes on
        #expect(s.stack == [Frame(screen: .spotifyApp)])
        send(&s, .spotifyAppFound(true))
        #expect(s.top.screen == .yourMusic && s.spotifyApp == true)
        send(&s, .reset)  // the Mac still has the app
        #expect(s.spotifyApp == true)
    }

    @Test func aLaterLaunchSkipsSetupAndChecksTheSpotifyApp() {
        var s = afterSetup()
        send(&s, .spotifyAppFound(true), .launch)
        #expect(s.stack == [Frame(screen: .login)])
        send(&s, .restored(token: 1, ok: true))
        #expect(s.stack == [Frame(screen: .main)])
        s = afterSetup()
        send(&s, .spotifyAppFound(false), .launch, .restored(token: 1, ok: true))
        #expect(s.stack == [Frame(screen: .spotifyApp)])
        send(&s, .spotifyAppFound(true))  // no library read: it goes straight to the main menu
        #expect(s.stack == [Frame(screen: .main)])
        // A login after a logout skips setup too.
        send(&s, .wheel(5), .select, .wheel(6), .select, .wheel(1), .select, .select)
        #expect(s.top == Frame(screen: .auth, token: 2) && s.toast == "Logged out")
        send(&s, .authDone(token: 2, ok: true))
        #expect(s.stack == [Frame(screen: .main)] && s.toast == "Signed in")
    }
}

@MainActor @Test func storeSavesTheEndOfSetup() async {
    let saved = FakeSettings()
    let store = Store(player: FakePlayer(), library: FakeLibrary(), env: Dependencies(now: { 0 }, random: { _ in 0 }), settings: saved)
    store.send(.launch)
    #expect(store.state.top.screen == .hello)
    while store.state.restoring { await Task.yield() }  // the fake restores a stored login
    store.send(.select)
    store.send(.select)
    #expect(store.state.top.screen == .yourMusic && saved.values["setup.done"] == nil)
    while store.state.top.screen == .yourMusic { await Task.yield() }
    #expect(store.state.top.screen == .main && saved.values["setup.done"] == "true")
    #expect(Settings(from: saved).setupDone)
}
