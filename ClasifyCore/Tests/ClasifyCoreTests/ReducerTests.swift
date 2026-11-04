import Testing
@testable import ClasifyCore

func tracks(_ p: String, _ n: Int, _ d: Double) -> [Track] {
    (0..<n).map { Track(id: "\(p)\($0)", title: "\(p)\($0)", artist: "x", duration: d) }
}

let liked = Playlist(id: Playlist.likedSongsID, name: "Liked Songs", tracks: tracks("l", 2, 10))
let focus = Playlist(id: "focus", name: "Focus", tracks: tracks("f", 8, 30))
let library = [liked, focus]

@discardableResult
func send(_ s: inout AppState, _ actions: Action..., now: Double = 100) -> [Effect] {
    let e = Dependencies(now: { now }, random: { _ in 0 })
    return actions.flatMap { reduce(&s, $0, e) }
}

/// Signed in on the main menu, library loaded.
func mainMenu() -> AppState {
    var s = AppState()
    send(&s, .select, .authDone(token: 1, ok: true))
    s.library = library
    return s
}

/// Playing Focus track `i` on the Now Playing screen.
func playing(_ i: Int = 0) -> AppState {
    var s = mainMenu()
    send(&s, .select, .loaded(token: 1, library: library), .select, .loaded(token: 2, library: library), .wheel(i), .select)
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
        send(&s, .menu, .wheel(7))  // back to Focus tracks, where the bar leaves 5 rows
        #expect(s.top.sel == 7 && s.top.off == 3)
        send(&s, .menu, .menu, .select)  // Now Playing
        #expect(send(&s, .wheel(-2)) == [.setVolume(50)])
        #expect(s.overlayUntil == 101.5)
        #expect(send(&s, .select, .wheel(2)) == [.seek(10, generation: 2)])  // scrub
    }

    @Test func listKeepsTheSelectionInTheRowsThatShow() {
        var s = mainMenu()
        send(&s, .select, .loaded(token: 1, library: library), .select, .loaded(token: 2, library: library), .wheel(5))
        #expect(s.shownRows == 6 && s.top.sel == 5 && s.top.off == 0)
        send(&s, .select, .menu)  // play track 5, then back: the bar now takes a row
        #expect(s.shownRows == 5 && s.top.sel == 5 && s.top.off == 1)
        send(&s, .wheel(-1))  // the selection moves up, the rows stay
        #expect(s.top.sel == 4 && s.top.off == 1)
        send(&s, .wheel(-4))
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
        send(&s, .select, .loaded(token: 1, library: library), .select, .loaded(token: 2, library: library), .wheel(3))
        let load: [Effect] = [.setShuffle(false), .setRepeat(.off), .load(trackID: "f3", context: "focus", autoplay: true, generation: 1)]
        #expect(send(&s, .select) == load)
        #expect(s.top.screen == .now && s.isPlaying && s.current == TrackRef(playlist: "focus", track: "f3"))
    }

    @Test func shuffleSongsLoadsLikedSongsFirst() {
        var s = mainMenu()
        s.library = []  // fresh sign-in: nothing fetched yet
        send(&s, .wheel(2), .select)
        #expect(s.top.screen == .tracks(playlist: Playlist.likedSongsID) && s.top.loading)
        let load: [Effect] = [.setShuffle(true), .setRepeat(.off), .load(trackID: "l0", context: "liked", autoplay: true, generation: 1)]
        #expect(send(&s, .loaded(token: 1, library: library)) == load)
        #expect(s.top.screen == .now && s.shuffle && s.shuffleToken == nil)

        s = mainMenu(); s.library = []
        send(&s, .wheel(2), .select, .loaded(token: 1, library: nil))  // fetch fails
        #expect(s.top.error)
        send(&s, .select, .loaded(token: 2, library: library))  // retry succeeds and still shuffles
        #expect(s.top.screen == .now && s.shuffle && s.current?.track == "l0")
    }

    @Test func selectOnErrorRetriesWithNewToken() {
        var s = mainMenu()
        #expect(send(&s, .select) == [.fetchLibrary(token: 1)])
        send(&s, .loaded(token: 1, library: nil))
        #expect(s.top.error)
        #expect(send(&s, .select) == [.fetchLibrary(token: 2)])
        #expect(s.top.loading && !s.top.error && s.top.token == 2)
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

    @Test func prevRestartsAfterThreeSecondsElseGoesBack() {
        var s = playing(2)
        send(&s, .position(5, generation: 1))
        #expect(send(&s, .prev) == [.seek(0, generation: 2)] && s.current?.track == "f2")
        #expect(send(&s, .trackEnded(generation: 1)) == [])  // queued before the restart
        #expect(send(&s, .prev) == [.prev(generation: 3)] && s.current?.track == "f2")
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

    @Test func loadedIgnoresStaleTokens() {
        var s = mainMenu()
        send(&s, .select, .loaded(token: 99, library: library))
        #expect(s.top.loading)
        send(&s, .loaded(token: 1, library: library))
        #expect(!s.top.loading && !s.top.error)
        #expect(s.rows(for: s.top) == [.playlist("focus")])
    }

    @Test func reloadThatReordersKeepsCurrentTrack() {
        var s = playing(2)
        let reordered = [Playlist(id: "focus", name: "Focus", tracks: focus.tracks.reversed()), liked]
        send(&s, .menu, .menu, .select, .loaded(token: 3, library: reordered))
        #expect(s.track(s.current!)?.id == "f2")
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
        #expect(s.toast == "Session expired. Log in again")
    }

    @Test func resetRestoresInitialState() {
        var s = playing()
        #expect(send(&s, .reset) == [.stop])
        var fresh = AppState()
        fresh.tok = s.tok; fresh.playGen = s.playGen; fresh.authAttempt = s.authAttempt
        #expect(s == fresh && s.tok == 2)
        send(&s, .select, .authDone(token: 2, ok: true), .select, .loaded(token: 1, library: library))  // late load from before reset
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
    var result: [Playlist]? = library
    var fetches = 0
    var loginResult = true
    var calls: [String] = []
    func fetchLibrary() async -> [Playlist]? { fetches += 1; return result }
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
    #expect(lib.fetches == 1 && !store.state.top.loading && store.state.library == library)
    #expect(store.state.rows(for: store.state.top) == [.playlist("focus")])
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
        #expect(pick([pc], "WORK-PC") == .found(id: "w1"))  // a name match always wins
    }
}
