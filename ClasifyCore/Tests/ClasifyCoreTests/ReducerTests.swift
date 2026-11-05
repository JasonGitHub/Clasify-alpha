import Testing
@testable import ClasifyCore

func tracks(_ p: String, _ n: Int, _ d: Double) -> [Track] {
    (0..<n).map { Track(id: "\(p)\($0)", title: "\(p)\($0)", artist: "x", duration: d) }
}

let liked = Playlist(id: Playlist.likedSongsID, name: "Liked Songs", tracks: tracks("l", 2, 10))
let focus = Playlist(id: "focus", name: "Focus", tracks: tracks("f", 8, 30))
let library = [liked, focus]
/// Focus as the playlist list has it: a name and a count, no tracks.
let focusInfo = Playlist(id: "focus", name: "Focus", tracks: [], trackCount: 8)

/// Opens Playlists, then Focus, with fresh reads that use tokens `first` and `first + 1`.
func openFocus(_ first: Int) -> [Action] {
    [.select, .playlistsLoaded(token: first, playlists: [focusInfo]),
     .select, .tracksLoaded(token: first + 1, playlist: "focus", tracks: focus.tracks)]
}

@discardableResult
func send(_ s: inout AppState, _ actions: Action..., now: Double = 100) -> [Effect] {
    let e = Dependencies(now: { now }, random: { _ in 0 })
    return actions.flatMap { reduce(&s, $0, e) }
}

@discardableResult
func send(_ s: inout AppState, _ actions: [Action]) -> [Effect] {
    let e = Dependencies(now: { 100 }, random: { _ in 0 })
    return actions.flatMap { reduce(&s, $0, e) }
}

/// Signed in on the main menu. Nothing of the library is read yet.
func mainMenu() -> AppState {
    var s = AppState()
    send(&s, .select, .authDone(token: 1, ok: true))
    return s
}

/// Playing Focus track `i` on the Now Playing screen.
func playing(_ i: Int = 0) -> AppState {
    var s = mainMenu()
    send(&s, openFocus(1))
    send(&s, .wheel(i), .select)
    return s
}

@Suite struct ReducerTests {
    @Test func wheelMovesSelectionScrollsAndSetsVolume() {
        var s = mainMenu()
        send(&s, .wheel(-3))
        #expect(s.top.sel == 0)
        send(&s, .wheel(99))
        #expect(s.top.sel == 3)  // clamped to last row

        s = playing()
        send(&s, .menu, .wheel(7))  // back to Focus tracks, where the bar leaves 4 rows
        #expect(s.top.sel == 7 && s.top.off == 4)
        send(&s, .menu, .menu, .select)  // Now Playing
        #expect(send(&s, .wheel(-2)) == [.setVolume(50)])
        #expect(s.overlayUntil == 101.5)
        #expect(send(&s, .select, .wheel(2)) == [.seek(10, generation: 2)])  // scrub
    }

    @Test func listKeepsTheSelectionInTheRowsThatShow() {
        var s = mainMenu()
        send(&s, openFocus(1))
        send(&s, .wheel(7))
        #expect(s.shownRows == 5 && s.top.sel == 7 && s.top.off == 3)
        send(&s, .select, .menu)  // play track 7, then back: the bar now takes a row
        #expect(s.shownRows == 4 && s.top.sel == 7 && s.top.off == 4)
        send(&s, .wheel(-1))  // the selection moves up, the rows stay
        #expect(s.top.sel == 6 && s.top.off == 4)
        send(&s, .wheel(-6))
        #expect(s.top.sel == 0 && s.top.off == 0)
    }

    @Test func selectPushesScreensAndTogglesSettings() {
        var s = mainMenu()
        send(&s, .wheel(3), .select)
        #expect(s.top.screen == .settings)
        send(&s, .select, .wheel(1), .select, .select)
        #expect(s.shuffle && s.repeatMode == .one)
        s.toast = ""  // the "Signed in" toast from mainMenu()
        send(&s, .wheel(1), .select)
        #expect(!s.showArt && s.skin == .pocket && s.toast.isEmpty)
        #expect(!s.rows(for: s.top).contains(.skin))  // only the Pocket skin in 1.0
        #expect(s.rows(for: s.top).count == 6)  // no Playback engine, EQ or Skin row in 1.0
    }

    @Test func selectTrackLoadsAndPlays() {
        var s = mainMenu()
        send(&s, openFocus(1))
        send(&s, .wheel(3))
        let load: [Effect] = [.setShuffle(false), .setRepeat(.off), .load(trackID: "f3", context: "focus", autoplay: true, generation: 1)]
        #expect(send(&s, .select) == load)
        #expect(s.top.screen == .now && s.isPlaying && s.current == TrackRef(playlist: "focus", track: "f3"))
    }

    @Test func shuffleSongsLoadsLikedSongsFirst() {
        var s = mainMenu()  // fresh sign-in: nothing read yet
        #expect(send(&s, .wheel(2), .select) == [.fetchTracks(token: 1, playlist: Playlist.likedSongsID)])
        #expect(s.top.screen == .tracks(playlist: Playlist.likedSongsID) && s.top.loading)
        let load: [Effect] = [.setShuffle(true), .setRepeat(.off), .load(trackID: "l0", context: "liked", autoplay: true, generation: 1)]
        #expect(send(&s, .tracksLoaded(token: 1, playlist: Playlist.likedSongsID, tracks: liked.tracks)) == load)
        #expect(s.top.screen == .now && s.shuffle && s.shuffleToken == nil)
        send(&s, .menu, .menu, .wheel(1))  // back to Shuffle Songs, one row lower under Now Playing
        #expect(s.rows(for: s.top)[s.top.sel] == .shuffleSongs)
        // Liked Songs is read now, so the next shuffle starts at once.
        #expect(send(&s, .select).contains(.load(trackID: "l0", context: "liked", autoplay: true, generation: 2)))

        s = mainMenu()
        send(&s, .wheel(2), .select, .tracksLoaded(token: 1, playlist: Playlist.likedSongsID, tracks: nil))  // read fails
        #expect(s.top.error)
        send(&s, .select, .tracksLoaded(token: 2, playlist: Playlist.likedSongsID, tracks: liked.tracks))  // retry succeeds and still shuffles
        #expect(s.top.screen == .now && s.shuffle && s.current?.track == "l0")
    }

    @Test func selectOnErrorRetriesWithNewToken() {
        var s = mainMenu()
        #expect(send(&s, .select) == [.fetchPlaylists(token: 1)])
        send(&s, .playlistsLoaded(token: 1, playlists: nil))
        #expect(s.top.error && !s.playlistsLoaded)
        #expect(send(&s, .select) == [.fetchPlaylists(token: 2)])
        #expect(s.top.loading && !s.top.error && s.top.token == 2)
        send(&s, .playlistsLoaded(token: 2, playlists: [focusInfo]), .select)
        send(&s, .tracksLoaded(token: 3, playlist: "focus", tracks: nil))
        #expect(send(&s, .select) == [.fetchTracks(token: 4, playlist: "focus")])
    }

    @Test func menuPopsButNotFromRoot() {
        var s = AppState()
        send(&s, .menu)
        #expect(s.stack.count == 1)

        s = playing()
        send(&s, .select, .menu)  // leave scrub first
        #expect(s.top.screen == .now && s.nowMode == .volume)
        send(&s, .menu)
        #expect(s.top.screen == .tracks(playlist: "focus"))
    }

    @Test func playTogglesAndBlocksResumeOffline() {
        var s = mainMenu()
        send(&s, .play)
        #expect(s.toast == "Nothing playing yet")
        s = playing()
        #expect(send(&s, .play) == [.pause] && !s.isPlaying)
        send(&s, .offline(true))
        #expect(send(&s, .play) == [] && s.toast == "Offline. Can’t resume")
    }

    @Test func nextAndPrevSkipInTheEngine() {
        var s = playing(6)
        #expect(send(&s, .next) == [.next(generation: 2)] && s.current?.track == "f6")  // moves on `.trackChanged`
        send(&s, .position(130, generation: 1))  // from before the skip
        send(&s, .trackChanged("f7", playing: true, generation: 2))
        #expect(s.current?.track == "f7" && s.t == 0)
        #expect(send(&s, .prev) == [.prev(generation: 3)])
        s.repeatMode = .all; s.shuffle = true
        #expect(send(&s, .next) == [.next(generation: 4)])  // the engine applies shuffle and repeat
        s = playing(3)
        send(&s, .offline(true))
        #expect(send(&s, .next, .prev) == [] && s.current?.track == "f3" && s.toast == "Offline. Can’t start playback")
    }

    @Test func shuffleAndRepeatSettingsGoToEngine() {
        var s = mainMenu()
        send(&s, .wheel(3), .select)  // Settings
        #expect(send(&s, .select) == [.setShuffle(true)])
        #expect(send(&s, .wheel(1), .select) == [.setRepeat(.all)])
        #expect(send(&s, .select) == [.setRepeat(.one)])
        #expect(send(&s, .select) == [.setRepeat(.off)])
    }

    @Test func centerStepsThroughTheNowPlayingSliders() {
        var s = playing()
        send(&s, .select)
        #expect(s.nowMode == .scrub && s.overlayUntil == 106)
        send(&s, .select)
        #expect(s.nowMode == .shuffle)
        #expect(send(&s, .wheel(1)) == [.setShuffle(true)] && s.shuffle)
        #expect(send(&s, .wheel(2)) == [])  // already at Songs
        #expect(send(&s, .wheel(-1)) == [.setShuffle(false)] && !s.shuffle)
        send(&s, .select)
        #expect(s.nowMode == .repeatMode)
        #expect(send(&s, .wheel(1)) == [.setRepeat(.one)])  // the slider goes Off, One, All
        #expect(send(&s, .wheel(3)) == [.setRepeat(.all)])  // one stop for each step
        #expect(send(&s, .wheel(1)) == [])
        #expect(send(&s, .wheel(-1)) == [.setRepeat(.one)])
        send(&s, .select)
        #expect(s.nowMode == .volume && s.overlayUntil == 101.5)  // the volume bar shows briefly
    }

    @Test func slidersGoBackToTheProgressBarAfterSixSeconds() {
        var s = playing()
        send(&s, .select, .select)  // the shuffle slider, until 106
        send(&s, .tick, now: 105)
        #expect(s.nowMode == .shuffle)
        send(&s, .wheel(1), now: 105)  // a turn starts the 6 seconds again
        send(&s, .tick, now: 110)
        #expect(s.nowMode == .shuffle && s.overlayUntil == 111)
        send(&s, .tick, now: 111.5)
        #expect(s.nowMode == .volume && s.overlayUntil == 0)
        send(&s, .select, .select, .select, .menu)  // MENU leaves the repeat slider at once
        #expect(s.nowMode == .volume && s.overlayUntil == 0 && s.top.screen == .now)
    }

    @Test func shuffleAndRepeatKeysWorkOnEveryScreen() {
        var s = mainMenu()
        #expect(send(&s, .toggleShuffle) == [.setShuffle(true)] && s.shuffle)
        #expect(send(&s, .cycleRepeat) == [.setRepeat(.all)])
        #expect(send(&s, .cycleRepeat) == [.setRepeat(.one)])
        #expect(send(&s, .cycleRepeat) == [.setRepeat(.off)])
        s = playing()
        #expect(send(&s, .toggleShuffle) == [.setShuffle(true)] && s.top.screen == .now)
    }

    @Test func fastWheelStepsMoveMoreRows() {
        var speed = WheelSpeed()
        let quick = (0..<16).map { speed.rows(at: Double($0) * 0.1) }
        #expect(quick == [1, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 4])
        #expect(speed.rows(at: 10) == 1)  // a pause ends the streak

        var s = mainMenu()
        send(&s, openFocus(1))
        for i in 0..<6 { send(&s, .wheel(1), now: 200 + Double(i) * 0.05) }
        #expect(s.top.sel == 7)  // five steps of 1, then one of 2
        s = playing()
        for i in 0..<8 { send(&s, .wheel(1), now: 200 + Double(i) * 0.05) }
        #expect(s.volume == 100)  // 60 + 8 x 5: on Now Playing each step stays one step
    }

    @Test func theBarTakesARowExceptOnNowPlaying() {
        var s = playing()
        #expect(!s.showsBar && s.shownRows == 8)  // Now Playing
        send(&s, .menu)
        #expect(s.showsBar && s.shownRows == 4)  // five two-line song rows, less one
        send(&s, .menu)
        #expect(s.showsBar && s.shownRows == 7)  // Playlists
        send(&s, .menu)
        #expect(!s.showsBar && s.shownRows == 8)  // the main menu shows covers instead
    }

    @Test func prevRestartsAfterThreeSecondsElseGoesBack() {
        var s = playing(2)
        send(&s, .position(5, generation: 1))
        #expect(send(&s, .prev) == [.seek(0, generation: 2)] && s.current?.track == "f2")
        #expect(send(&s, .trackEnded(generation: 1)) == [])  // queued before the restart
        #expect(send(&s, .prev) == [.prev(generation: 3)] && s.current?.track == "f2")
    }

    @Test func theScrollBarShowsAfterAStepOrAScreenChange() {
        var s = mainMenu()
        send(&s, .tick, now: 102)
        #expect(s.scrollUntil == 0)
        send(&s, .wheel(1))
        #expect(s.scrollUntil == 100 + scrollBarTime)
        send(&s, .tick, now: 101)
        #expect(s.scrollUntil == 101.5)  // still showing
        send(&s, .tick, now: 102)
        #expect(s.scrollUntil == 0)
        send(&s, .select, now: 200)  // Liked Songs opens, and loads first: no list yet
        #expect(s.top.loading && s.scrollUntil == 0)
        send(&s, .tracksLoaded(token: s.top.token, playlist: Playlist.likedSongsID, tracks: liked.tracks), now: 203)
        #expect(s.scrollUntil == 204.5)  // the list shows
        send(&s, .tick, now: 205)
        send(&s, .menu, now: 300)  // back to the main menu
        #expect(s.scrollUntil == 301.5)
        s = playing()
        send(&s, .tick, now: 200)
        send(&s, .wheel(1), now: 300)  // volume on Now Playing: no scroll bar
        #expect(s.scrollUntil == 0)
    }

    @Test func theMainMenuCoversStartWithThePlayingTrack() {
        var s = mainMenu()
        #expect(s.mainArt.isEmpty)
        s.library = library
        #expect(s.mainArt.map(\.id) == ["l0", "l1", "l0", "l1"])  // two Liked Songs, repeated
        s = playing(3)
        s.library = library
        #expect(s.mainArt.map(\.id) == ["f3", "l0", "l1", "f3"])
    }

    @Test func screenChangesSlideInFromTheRightOrTheLeft() {
        var s = AppState()
        send(&s, .select)  // the login wait opens
        #expect(s.navSeq == 1 && s.navForward)
        send(&s, .authDone(token: 1, ok: true))  // the main menu replaces login: still forward
        #expect(s.navSeq == 2 && s.navForward)
        send(&s, .wheel(1))  // no screen change
        #expect(s.navSeq == 2)
        send(&s, .select)  // Liked Songs opens
        #expect(s.navSeq == 3 && s.navForward)
        send(&s, .menu)  // back
        #expect(s.navSeq == 4 && !s.navForward)
        send(&s, .reset)
        #expect(s.navSeq == 4)  // the same screen identity, so no slide
    }

    @Test func tickExpiresToastAndOverlay() {
        var s = playing()
        s.toast = "hi"; s.toastUntil = 101; s.overlayUntil = 101
        send(&s, .tick)
        #expect(s.toast == "hi" && s.t == 0)  // tick no longer moves playback
        send(&s, .tick, now: 102)
        #expect(s.toast == "" && s.overlayUntil == 0)
    }

    @Test func positionAndTrackEndedComeFromEngine() {
        var s = playing()
        send(&s, .position(12.5, generation: 1))
        #expect(s.t == 12.5)
        #expect(send(&s, .position(20, generation: 0)) == [] && s.t == 12.5)  // from an earlier load
        #expect(send(&s, .trackEnded(generation: 0)) == [] && s.isPlaying)
        #expect(send(&s, .trackEnded(generation: 1)) == [])  // the engine stopped at the end of the context
        #expect(!s.isPlaying && s.t == 0 && s.current?.track == "f0")
        #expect(send(&s, .trackEnded(generation: 1)) == [] && !s.isPlaying)
    }

    @Test func trackChangedMovesCurrentWithoutLoading() {
        var s = playing()
        send(&s, .position(12.5, generation: 1))
        #expect(send(&s, .trackChanged("f1", playing: true, generation: 1)) == [])
        #expect(s.current == TrackRef(playlist: "focus", track: "f1") && s.t == 0 && s.isPlaying)
        send(&s, .trackChanged("f5", playing: false, generation: 0))  // from an earlier load
        #expect(s.current?.track == "f1" && s.isPlaying)
        send(&s, .trackChanged("zz", playing: false, generation: 1))  // not in our copy of the playlist
        #expect(s.current == TrackRef(playlist: "focus", track: "zz") && s.track(s.current!) == nil && !s.isPlaying)
        #expect(send(&s, .select, .wheel(1)) == [.seek(5, generation: 2)])  // scrub with no known duration
        s = playing()
        send(&s, .trackEnded(generation: 1))
        send(&s, .next, .trackChanged("f1", playing: true, generation: 2))  // Next after the end plays again
        #expect(s.isPlaying && s.current?.track == "f1")
        s = mainMenu()
        #expect(send(&s, .trackChanged("f1", playing: true, generation: 0)) == [] && s.current == nil)
    }

    @Test func playbackFailedPausesAndShowsToast() {
        var s = playing()
        send(&s, .playbackFailed("Old", generation: 0))  // stale load
        #expect(s.isPlaying && s.toast == "Signed in")  // unchanged
        #expect(send(&s, .playbackFailed("Install Spotify to play music", generation: 1)) == [])
        #expect(!s.isPlaying && s.toast == "Install Spotify to play music" && s.current?.track == "f0")
    }

    @Test func playlistsLoadedIgnoresStaleTokens() {
        var s = mainMenu()
        send(&s, .select, .playlistsLoaded(token: 99, playlists: [focusInfo]))
        #expect(s.top.loading && !s.playlistsLoaded)
        send(&s, .playlistsLoaded(token: 1, playlists: [focusInfo]))
        #expect(!s.top.loading && !s.top.error && s.playlistsLoaded)
        #expect(s.rows(for: s.top) == [.playlist("focus")] && s.library[0].trackCount == 8)
    }

    @Test func tracksLoadedIgnoresStaleTokensAndFillsThePlaylist() {
        var s = mainMenu()
        send(&s, .select, .playlistsLoaded(token: 1, playlists: [focusInfo]), .select)
        #expect(s.top.loading && s.rows(for: s.top) == [])
        send(&s, .tracksLoaded(token: 1, playlist: "focus", tracks: focus.tracks))  // stale
        #expect(s.top.loading && !s.loadedTracks.contains("focus"))
        send(&s, .tracksLoaded(token: 2, playlist: "focus", tracks: focus.tracks))
        #expect(!s.top.loading && s.rows(for: s.top).count == 8 && s.loadedTracks == ["focus"])
        send(&s, .menu, .menu, .wheel(1), .select, .tracksLoaded(token: 3, playlist: Playlist.likedSongsID, tracks: liked.tracks))
        #expect(s.library.map(\.id) == [Playlist.likedSongsID, "focus"])  // Liked Songs goes first
    }

    @Test func listsReadOnceOpenAtOnce() {
        var s = mainMenu()
        send(&s, openFocus(1))
        #expect(send(&s, .menu, .menu, .select) == [] && !s.top.loading && s.top.screen == .playlists)
        #expect(send(&s, .select) == [] && !s.top.loading && s.rows(for: s.top).count == 8)
    }

    @Test func playlistsReloadKeepsTracksAlreadyRead() {
        var s = mainMenu()
        send(&s, openFocus(1))
        let other = Playlist(id: "other", name: "Other", tracks: [], trackCount: 3)
        s.playlistsLoaded = false  // as if the list must be read again
        send(&s, .menu, .menu, .select, .playlistsLoaded(token: 3, playlists: [other, focusInfo]))
        #expect(s.tracks(in: "focus") == focus.tracks && s.rows(for: s.top) == [.playlist("other"), .playlist("focus")])
        s.playlistsLoaded = false
        send(&s, .menu, .select, .playlistsLoaded(token: 4, playlists: [other]))  // Focus is gone
        #expect(s.loadedTracks.isEmpty && s.library.map(\.id) == ["other"])
    }

    @Test func tracksReloadThatReordersKeepsCurrentTrack() {
        var s = playing(2)
        s.loadedTracks = []  // as if Focus must be read again
        send(&s, .menu, .menu, .select, .tracksLoaded(token: 3, playlist: "focus", tracks: focus.tracks.reversed()))
        #expect(s.track(s.current!)?.id == "f2")
    }

    @Test func loginAndRestorePrefetchTheLibrary() {
        var s = AppState()
        #expect(send(&s, .select, .authDone(token: 1, ok: true)) == [.logIn(token: 1), .prefetch])
        s = AppState()
        #expect(send(&s, .launch, .restored(token: 1, ok: true)) == [.restoreSession(token: 1), .prefetch])
        s = AppState()
        #expect(send(&s, .launch, .restored(token: 1, ok: false)) == [.restoreSession(token: 1)])
    }

    @Test func authDoneSignsInOrFailsOffline() {
        var s = AppState()
        #expect(send(&s, .select) == [.logIn(token: 1)])
        send(&s, .offline(true), .authDone(token: 1, ok: false))  // offline, the login fails
        #expect(s.top.screen == .login && !s.signedIn && s.toast == "Can’t reach Spotify")
        send(&s, .offline(false), .select, .authDone(token: 1, ok: true))  // late, from the first attempt
        #expect(s.top.screen == .auth && !s.signedIn)
        send(&s, .reset, .select, .authDone(token: 2, ok: true))  // from before the reset
        #expect(s.top.screen == .auth && !s.signedIn)
        send(&s, .offline(true), .authDone(token: 3, ok: true))  // a login that worked counts offline too
        #expect(s.stack == [Frame(screen: .main)] && s.signedIn)
    }

    @Test func failedLoginGoesBackToLogin() {
        var s = AppState()
        send(&s, .select, .authDone(token: 1, ok: false))
        #expect(s.stack == [Frame(screen: .login)] && !s.signedIn && s.toast == "Can’t reach Spotify")
    }

    @Test func menuCancelsLogin() {
        var s = AppState()
        send(&s, .select)
        #expect(send(&s, .menu) == [.cancelLogIn])
        #expect(s.stack == [Frame(screen: .login)])
        send(&s, .authDone(token: 1, ok: false))  // the cancelled login reports late
        #expect(s.stack == [Frame(screen: .login)] && s.toast == "")
    }

    @Test func launchRestoresTheStoredLogin() {
        var s = AppState()
        #expect(send(&s, .launch) == [.restoreSession(token: 1)])
        #expect(s.restoring && s.rows(for: s.top) == [])
        send(&s, .restored(token: 1, ok: true))
        #expect(s.stack == [Frame(screen: .main)] && s.signedIn && !s.restoring && s.toast == "")
        #expect(send(&s, .launch) == [])  // already signed in
    }

    @Test func failedRestoreOffersLogIn() {
        var s = AppState()
        send(&s, .launch, .restored(token: 1, ok: false))
        #expect(s.stack == [Frame(screen: .login)] && !s.signedIn && !s.restoring)
        #expect(s.rows(for: s.top) == [.logIn])
    }

    @Test func noLoginWhileRestoring() {
        var s = AppState()
        #expect(send(&s, .launch, .wheel(1), .select, .menu) == [.restoreSession(token: 1)])
        #expect(s.stack == [Frame(screen: .login)] && s.restoring)
        send(&s, .reset, .restored(token: 1, ok: true))  // from before the reset
        #expect(s.stack == [Frame(screen: .login)] && !s.signedIn)
    }

    @Test func offlinePausesPlayback() {
        var s = playing()
        #expect(send(&s, .offline(true)) == [.pause])
        #expect(s.offline && !s.isPlaying && s.toast == "Connection lost. Paused")
        send(&s, .menu, .select)  // Focus track 0
        #expect(s.top.screen == .tracks(playlist: "focus") && s.toast == "Offline. Can’t start playback")
    }

    @Test func expireSignsOut() {
        var s = AppState()
        #expect(send(&s, .expire) == [] && s.toast == "")
        s = playing()
        #expect(send(&s, .expire) == [.stop, .logOut])
        #expect(s.stack == [Frame(screen: .login)] && !s.signedIn && s.current == nil && s.library.isEmpty)
        #expect(!s.playlistsLoaded && s.loadedTracks.isEmpty)
        #expect(s.toast == "Session expired. Log in again")
    }

    @Test func resetRestoresInitialState() {
        var s = playing()
        #expect(send(&s, .reset) == [.stop])
        var fresh = AppState()
        fresh.tok = s.tok; fresh.playGen = s.playGen; fresh.authAttempt = s.authAttempt; fresh.navSeq = s.navSeq
        #expect(s == fresh && s.tok == 2 && s.navSeq > 0)  // the reset keeps the screen identity: no slide
        send(&s, .select, .authDone(token: 2, ok: true), .select, .playlistsLoaded(token: 1, playlists: [focusInfo]))  // late load from before reset
        #expect(s.top.loading && s.top.token == 3)
    }

    @Test func logOutGoesThroughConfirm() {
        var s = playing()
        send(&s, .menu, .menu, .menu, .wheel(4), .select, .wheel(6), .select)
        #expect(s.top.screen == .confirm)
        send(&s, .select)  // Cancel
        #expect(s.top.screen == .settings)
        #expect(send(&s, .select, .wheel(1), .select) == [.stop, .logOut])
        #expect(s.top.screen == .login && s.toast == "Logged out" && s.current == nil)
    }
}

@MainActor final class FakePlayer: Player {
    var calls: [String] = []
    func load(trackID: String, context: String?, autoplay: Bool, generation: Int) {
        calls.append("load \(trackID) \(context ?? "-") \(autoplay)")
    }
    func pause() { calls.append("pause") }
    func resume() { calls.append("resume") }
    func stop() { calls.append("stop") }
    func next(generation: Int) { calls.append("next") }
    func prev(generation: Int) { calls.append("prev") }
    func setShuffle(_ on: Bool) { calls.append("shuffle \(on)") }
    func setRepeat(_ mode: RepeatMode) { calls.append("repeat \(mode.rawValue)") }
    func seek(to seconds: Double, generation: Int) { calls.append("seek \(seconds)") }
    func setVolume(_ percent: Int) { calls.append("volume \(percent)") }
}

@MainActor @Test func storeRunsEffectsAgainstPlayer() {
    let player = FakePlayer()
    var s = playing()
    s.isPlaying = true
    let store = Store(player: player, library: FakeLibrary(), state: s, env: Dependencies(now: { 0 }, random: { _ in 0 }))
    store.send(.play)
    store.send(.wheel(1))
    store.send(.next)
    store.send(.prev)
    #expect(player.calls == ["pause", "volume 65", "next", "prev"])
}

@MainActor final class FakeLibrary: Library {
    var fetches: [String] = []
    var loginResult = true
    var calls: [String] = []
    func playlists() async -> [Playlist]? { fetches.append("playlists"); return [focusInfo] }
    func tracks(of playlist: String) async -> [Track]? {
        fetches.append(playlist); return library.first { $0.id == playlist }?.tracks
    }
    func prefetch() async { calls.append("prefetch") }
    func logIn() async -> Bool { calls.append("logIn"); return loginResult }
    func cancelLogIn() async { calls.append("cancelLogIn") }
    func restoreSession() async -> Bool { calls.append("restoreSession"); return loginResult }
    func logOut() { calls.append("logOut") }
}

@MainActor @Test func storeRunsLoginEffects() async {
    let lib = FakeLibrary()
    let store = Store(player: FakePlayer(), library: lib, env: Dependencies(now: { 0 }, random: { _ in 0 }))
    lib.loginResult = false
    store.send(.launch)
    while store.state.restoring { await Task.yield() }
    store.send(.select)  // Log in
    while lib.calls.count < 2 { await Task.yield() }
    #expect(lib.calls == ["restoreSession", "logIn"])
    while store.state.top.screen == .auth { await Task.yield() }
    #expect(store.state.stack == [Frame(screen: .login)] && store.state.toast == "Can’t reach Spotify")
    store.send(.select)
    store.send(.menu)
    while lib.calls.count < 4 { await Task.yield() }
    #expect(lib.calls.suffix(2).sorted() == ["cancelLogIn", "logIn"])
}

@MainActor @Test func storeFetchesLibraryAndDeliversLoaded() async {
    let lib = FakeLibrary()
    var s = AppState()
    send(&s, .select, .authDone(token: 1, ok: true))
    let store = Store(player: FakePlayer(), library: lib, state: s, env: Dependencies(now: { 0 }, random: { _ in 0 }))
    store.send(.select)  // Playlists
    #expect(store.state.top.loading)
    await store.settle()
    #expect(lib.fetches == ["playlists"] && !store.state.top.loading && store.state.library == [focusInfo])
    #expect(store.state.rows(for: store.state.top) == [.playlist("focus")])
    store.send(.select)  // Focus
    await store.settle()
    #expect(lib.fetches == ["playlists", "focus"] && store.state.tracks(in: "focus") == focus.tracks)
}

@MainActor @Test func storeRunsPrefetchAfterLogin() async {
    let lib = FakeLibrary()
    let store = Store(player: FakePlayer(), library: lib, env: Dependencies(now: { 0 }, random: { _ in 0 }))
    store.send(.launch)
    while !lib.calls.contains("prefetch") { await Task.yield() }
    #expect(lib.calls == ["restoreSession", "prefetch"] && lib.fetches.isEmpty)
}

@Test func trackKeepsACoverIDAndDropsAnEmptyOne() {
    #expect(Track(id: "t", title: "T", artist: "A", duration: 1, coverID: "ab67").coverID == "ab67")
    #expect(Track(id: "t", title: "T", artist: "A", duration: 1, coverID: "").coverID == nil)
    #expect(Track(id: "t", title: "T", artist: "A", duration: 1).coverID == nil)
}

@Suite struct SpotifyAppDeviceTests {
    typealias D = SpotifyAppDevice.Candidate

    // From the spike build 9 log: the Spotify app's software string has no "osx".
    let mac = D(id: "a1", name: "Jason’s Macbook Air 15", type: "COMPUTER")
    let phone = D(id: "p1", name: "iPhone", type: "SMARTPHONE")

    @Test func picksThisMacByNameOrTheOnlyComputer() {
        func pick(_ devices: [D], _ name: String?) -> SpotifyAppDevice.Pick {
            SpotifyAppDevice.pick(devices, computerName: name)
        }
        #expect(pick([phone, mac], "jason's macbook air 15") == .found(id: "a1"))
        #expect(pick([phone, mac], "Other Mac") == .found(id: "a1"))
        #expect(pick([phone, mac], nil) == .found(id: "a1"))
        #expect(pick([phone], "Jason’s Macbook Air 15") == .none)
        let second = D(id: "a2", name: "Studio", type: "COMPUTER")
        #expect(pick([mac, second], "Studio") == .found(id: "a2"))
        #expect(pick([mac, second], "Laptop") == .ambiguous)
    }

    @Test func coldStartWaitsForThisMacInsteadOfAnotherComputer() {
        // Clasify just launched Spotify here. The work PC was in the list before the launch.
        let pc = D(id: "w1", name: "WORK-PC", type: "COMPUTER")
        let before: Set = ["w1", "p1"]
        func pick(_ devices: [D], _ name: String?) -> SpotifyAppDevice.Pick {
            SpotifyAppDevice.pick(devices, computerName: name, excluding: before)
        }
        #expect(pick([phone, pc], "Jason’s Macbook Air 15") == .none)  // keeps waiting
        #expect(pick([phone, pc], nil) == .none)
        #expect(pick([pc, mac], "Jason’s Macbook Air 15") == .found(id: "a1"))
        #expect(pick([pc, mac], "Renamed Mac") == .found(id: "a1"))  // the only new computer
        #expect(pick([pc], "WORK-PC") == .none)  // an excluded name match waits for a new computer
    }

    @Test func sameNameMacFromBeforeTheLaunchIsTakenOnlyAfterTheWait() {
        // A remote Mac with this Mac's name, or this Mac's own entry from before Spotify quit.
        let twin = D(id: "t1", name: "Jason’s Macbook Air 15", type: "COMPUTER")
        let before: Set = ["t1"]
        func pick(_ devices: [D], afterWait: Bool) -> SpotifyAppDevice.Pick {
            SpotifyAppDevice.pick(devices, computerName: mac.name, excluding: before, allowExcluded: afterWait)
        }
        #expect(pick([twin, mac], afterWait: false) == .found(id: "a1"))  // the new device wins
        #expect(pick([twin, mac], afterWait: true) == .found(id: "a1"))
        #expect(pick([twin], afterWait: false) == .none)  // keep waiting for a new device
        #expect(pick([twin], afterWait: true) == .found(id: "t1"))  // this Mac back with its old ID
    }
}
