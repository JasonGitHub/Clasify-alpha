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
        #expect(s.helloAt == 100)  // the skin times the hello from here
        #expect(send(&s, .wheel(1), .menu, .restored(token: 1, ok: false)).isEmpty)
        #expect(s.stack == [Frame(screen: .hello)])  // a turn and MENU do nothing on Hello
        let whole = s.wholeSeq
        send(&s, .select)  // a press begins setup
        #expect(s.stack == [Frame(screen: .color)] && s.navForward)
        // CLA-62: Hello has no title bar, so the whole screen pushes, title bar and all.
        #expect(s.wholeSeq == whole + 1 && s.navMove == .push)
        #expect(s.rows(for: s.top) == [.color(.silver), .color(.black)] && s.top.sel == 0)
        // CLA-62: MENU on the color pick goes back to Hello, which starts again. The whole
        // screen moves back. A color turned to but not pressed is dropped.
        let back = s.wholeSeq
        send(&s, .wheel(1), .menu, now: 130)
        #expect(s.stack == [Frame(screen: .hello)] && s.helloAt == 130 && !s.navForward)
        #expect(s.wholeSeq == back + 1 && s.deviceColor == .silver && s.shownColor == .silver)
        send(&s, .select)  // a press begins setup again, on the saved color
        #expect(s.top.screen == .color && s.top.sel == 0)
    }

    @Test func theColorPickSavesTheColorAndMenuOnTheLoginGoesBack() {
        var s = onColor()
        let whole = s.wholeSeq
        send(&s, .wheel(1), .select)
        #expect(s.deviceColor == .black && s.top.screen == .login && s.rows(for: s.top) == [.logIn])
        #expect(s.wholeSeq == whole)  // between two setup screens, only the content slides
        send(&s, .menu)  // back to the color pick, with Black selected (card AX, change 172)
        #expect(s.top.screen == .color && s.top.sel == 1 && !s.navForward)
        #expect(s.colorAt == 100 && s.colorTurnAt == 100)  // it keeps its times: the center glows, no rim light
        send(&s, .reset, .launch, .restored(token: 2, ok: false), .select)  // a reset keeps the settings
        #expect(s.top.screen == .color && s.top.sel == 1)  // the pick starts on the color that is set
    }

    /// Card AW: a turn tries the color on the device at once. A press saves it.
    @Test func theColorPickTriesAColorOnAtTheFirstTurn() {
        var s = onColor()
        #expect(s.colorAt == 100 && s.colorTurnAt == 0 && s.shownColor == .silver)
        send(&s, .wheel(1), now: 105)
        #expect(s.colorTurnAt == 105 && s.shownColor == .black && s.deviceColor == .silver)
        send(&s, .wheel(-1), now: 107)  // only the first turn counts
        #expect(s.colorTurnAt == 105 && s.shownColor == .silver)
        send(&s, .wheel(1), .select, now: 108)
        #expect(s.top.screen == .login && s.deviceColor == .black && s.shownColor == .black)
        #expect(mainMenu().shownColor == .silver)  // off the color pick, the setting shows
    }

    @Test func aLoginInSetupReadsTheLibraryThenOpensTheMainMenu() {
        var s = onColor()
        #expect(send(&s, .select, .select) == [.logIn(token: 2)])
        #expect(send(&s, .authDone(token: 2, ok: true)) == [.prefetch])
        #expect(s.top.screen == .loggedIn && s.navForward)  // "You’re in" (card AX, change 175)
        // Card AY: Liked Songs, and the playlist names for the small screen (change 141).
        #expect(send(&s, .tick, now: 101.5) == [.fetchTracks(token: 1, playlist: Playlist.likedSongsID), .refreshPlaylists])
        #expect(s.stack == [Frame(screen: .yourMusic, loading: true, token: 1)] && s.signedIn && s.navForward)
        #expect(s.toast == "" && !s.setupDone && s.namesAt == 0)
        send(&s, .playlistsRefreshed([focusInfo]), now: 106)  // a slow read: they still fill in one by one from now
        #expect(s.top.loading && s.library.map(\.id) == ["focus"] && s.namesAt == 106)  // the read goes on
        send(&s, .tracksLoaded(token: 1, playlist: Playlist.likedSongsID, tracks: liked.tracks), now: 110)
        // "You’re all set" for 2.5 s (change 140), then the main menu.
        #expect(s.stack == [Frame(screen: .yourMusic, token: 1)] && s.setupDone && s.loadedTracks == [Playlist.likedSongsID])
        #expect(s.beatUntil == 112.5 && send(&s, .menu, .wheel(1), now: 111).isEmpty && s.top.screen == .yourMusic)
        send(&s, .tick, now: 112.5)
        #expect(s.stack == [Frame(screen: .main)] && s.beatUntil == 0)
    }

    /// Change 141: the first read counts up as the library reports how far it is. Other reads,
    /// and reports after the read, change nothing.
    @Test func theFirstReadCountsUp() {
        var s = onColor()
        send(&s, .select, .select, .authDone(token: 2, ok: true), .select)
        #expect(s.top.screen == .yourMusic && s.readDone == 0 && s.readTotal == 0)
        send(&s, .readProgress(Playlist.likedSongsID, done: 0, total: 1240), .readProgress(Playlist.likedSongsID, done: 300, total: 1240))
        #expect(s.readDone == 300 && s.readTotal == 1240)
        send(&s, .readProgress(Playlist.likedSongsID, done: 200, total: 1240))  // a late report
        #expect(s.readDone == 300)
        send(&s, .readProgress("focus", done: 5, total: 8))  // another read
        #expect(s.readDone == 300 && s.readTotal == 1240)
        send(&s, .tracksLoaded(token: 1, playlist: Playlist.likedSongsID, tracks: liked.tracks), .readProgress(Playlist.likedSongsID, done: 1240, total: 1240))
        #expect(s.readDone == 300)  // late: the read has ended
    }

    @Test func aPressOnAllSetGoesOnAtOnce() {
        var s = onColor()
        send(&s, .select, .select, .authDone(token: 2, ok: true), .select)
        #expect(s.top.screen == .yourMusic && send(&s, .select).isEmpty && s.top.screen == .yourMusic)  // no press while it reads
        send(&s, .tracksLoaded(token: 1, playlist: Playlist.likedSongsID, tracks: liked.tracks), .select)
        #expect(s.stack == [Frame(screen: .main)] && s.beatUntil == 0)
    }

    @Test func aFailedFirstReadShowsTheErrorAndRetries() {
        var s = onColor()
        send(&s, .select, .select, .authDone(token: 2, ok: true), .select)
        send(&s, .readProgress(Playlist.likedSongsID, done: 900, total: 1240), .tracksLoaded(token: 1, playlist: Playlist.likedSongsID, tracks: nil))
        #expect(s.top.screen == .yourMusic && s.top.error && !s.setupDone)
        #expect(send(&s, .select) == [.fetchTracks(token: 2, playlist: Playlist.likedSongsID)])
        #expect(s.readDone == 0 && s.readTotal == 0)  // the retry counts from 0 again
        send(&s, .readProgress(Playlist.likedSongsID, done: 300, total: 1240))
        #expect(s.readDone == 300)
        send(&s, .tracksLoaded(token: 2, playlist: Playlist.likedSongsID, tracks: liked.tracks), .select)
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
        send(&s, .spotifyAppFound(false), .select, .select, .authDone(token: 2, ok: true), .select)
        #expect(s.stack == [Frame(screen: .spotifyApp)] && s.spotifyApp == false)
        #expect(s.rows(for: s.top) == [.getSpotifyApp])
        #expect(send(&s, .menu, .wheel(1), .spotifyAppFound(false)).isEmpty)  // MENU does nothing, and the check goes on
        #expect(send(&s, .select) == [.getSpotifyApp])  // opens the download page
        #expect(s.stack == [Frame(screen: .spotifyApp)])
        send(&s, .spotifyAppFound(true), now: 200)  // "Linked" shows for 1.5 s (change 174)
        #expect(s.top.screen == .spotifyApp && s.spotifyApp == true && s.beatUntil == 201.5)
        send(&s, .spotifyAppFound(true), now: 201)  // the next check does not restart it
        #expect(s.beatUntil == 201.5)
        send(&s, .tick, now: 201.5)
        #expect(s.top.screen == .yourMusic && s.beatUntil == 0)
        send(&s, .reset)  // the Mac still has the app
        #expect(s.spotifyApp == true)
    }

    /// Change 131: when a play finds the Spotify app gone, the Spotify App screen opens over
    /// the screen that shows. When the app is back, it closes to that screen, with no toast.
    @Test func theSpotifyAppScreenOpensWhenTheAppGoesAway() {
        var s = playing()
        let before = s.stack
        send(&s, .spotifyAppFound(false), .playbackFailed("Install the Spotify app to play music", generation: s.playGen))
        #expect(s.stack == before + [Frame(screen: .spotifyApp)] && s.toast.isEmpty && !s.isPlaying)
        send(&s, .menu, .spotifyAppFound(false))
        #expect(s.stack == before + [Frame(screen: .spotifyApp)])
        send(&s, .spotifyAppFound(true), .tick, now: 200)
        #expect(s.top.screen == .spotifyApp)  // "Linked" first
        send(&s, .tick, now: 201.5)
        #expect(s.stack == before)
        s = AppState()
        send(&s, .spotifyAppFound(false))  // the check at launch, before the login: nothing opens
        #expect(s.stack == [Frame(screen: .login)])
    }

    /// A login after a logout, when the player then finds the Spotify app gone: the screen takes
    /// the place of "You’re in", and the app found goes on to the main menu.
    @Test func theSpotifyAppScreenReplacesYoureIn() {
        var s = afterSetup()
        send(&s, .select, .authDone(token: 1, ok: true), .spotifyAppFound(false), now: 10)
        #expect(s.stack == [Frame(screen: .spotifyApp)] && s.beatUntil == 0)
        send(&s, .spotifyAppFound(true), now: 20)
        send(&s, .tick, now: 21.5)
        #expect(s.stack == [Frame(screen: .main)])
    }

    /// A first play that fails under the Spotify App screen leaves no empty Now Playing, and a
    /// read that ended under it starts again when it closes.
    @Test func closingTheSpotifyAppScreenCleansUpUnderIt() {
        var s = mainMenu()
        send(&s, openFocus(1))
        send(&s, .select)  // the first track: Now Playing opens, and the load starts
        let list = s.stack.dropLast().map(\.screen)  // the main menu's selection moves with its Now Playing row
        send(&s, .spotifyAppFound(false), .loadFailed("Install the Spotify app to play music", generation: s.playGen))
        #expect(s.current == nil && s.toast.isEmpty)
        send(&s, .spotifyAppFound(true), .select)
        #expect(s.stack.map(\.screen) == list && s.top.screen == .tracks(playlist: "focus"))  // the list, not an empty Now Playing
        s = mainMenu()
        send(&s, .wheel(1), .select)  // Playlists starts to read
        #expect(s.top.loading && s.top.token == 1)
        send(&s, .spotifyAppFound(false), .playlistsLoaded(token: 1, playlists: [focusInfo]))  // dropped under the screen
        #expect(send(&s, .spotifyAppFound(true), .select) == [.fetchPlaylists(token: 2)])  // so it reads again
        #expect(s.top == Frame(screen: .playlists, loading: true, token: 2))
        send(&s, .playlistsLoaded(token: 2, playlists: [focusInfo]))
        #expect(!s.top.loading && s.rows(for: s.top) == [.playlist("focus")])
    }

    @Test func aLaterLaunchSkipsSetupAndChecksTheSpotifyApp() {
        var s = afterSetup()
        send(&s, .spotifyAppFound(true), .launch)
        #expect(s.stack == [Frame(screen: .login)] && s.helloAt == 0)
        send(&s, .restored(token: 1, ok: true))
        #expect(s.stack == [Frame(screen: .main)])
        s = afterSetup()
        send(&s, .spotifyAppFound(false), .launch, .restored(token: 1, ok: true))
        #expect(s.stack == [Frame(screen: .spotifyApp)])
        send(&s, .spotifyAppFound(true), .select)  // a press on "Linked" goes on at once
        #expect(s.stack == [Frame(screen: .main)])  // no library read: straight to the main menu
        // A login after a logout skips setup too.
        send(&s, .wheel(5), .select, .wheel(6), .select, .wheel(1), .select, .select)
        #expect(s.top == Frame(screen: .auth, token: 2) && s.toast == "")  // change 181: no toast
        send(&s, .authDone(token: 2, ok: true), .select)
        #expect(s.stack == [Frame(screen: .main)])
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
    while !store.state.setupDone { await Task.yield() }
    #expect(store.state.top.screen == .yourMusic && saved.values["setup.done"] == "true")  // "You’re all set"
    #expect(store.state.readDone == 1 && store.state.readTotal == 2)  // the library's progress reached the store
    store.send(.select)
    #expect(store.state.top.screen == .main)
    #expect(Settings(from: saved).setupDone)
}
