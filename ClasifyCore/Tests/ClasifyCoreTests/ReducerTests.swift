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
    send(&s, .select, .authDone)
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
        send(&s, .menu, .wheel(7))  // back to Focus tracks
        #expect(s.top.sel == 7 && s.top.off == 2)
        send(&s, .menu, .menu, .select)  // Now Playing
        #expect(send(&s, .wheel(-2)) == [.setVolume(50)])
        #expect(s.overlayUntil == 101.5)
        #expect(send(&s, .select, .wheel(2)) == [.seek(10)])  // scrub
    }

    @Test func selectPushesScreensAndTogglesSettings() {
        var s = mainMenu()
        send(&s, .wheel(3), .select)
        #expect(s.top.screen == .settings)
        send(&s, .select, .wheel(1), .select, .select)
        #expect(s.shuffle && s.repeatMode == .one)
        send(&s, .wheel(2), .select)
        #expect(s.skin == .aqua && s.toast == "Window switches to Aqua skin")
        #expect(s.rows(for: s.top).count == 8)  // no Playback engine row in 1.0
    }

    @Test func selectTrackLoadsAndPlays() {
        var s = mainMenu()
        send(&s, .select, .loaded(token: 1, library: library), .select, .loaded(token: 2, library: library), .wheel(3))
        #expect(send(&s, .select) == [.load(trackID: "f3", autoplay: true, generation: 1)])
        #expect(s.top.screen == .now && s.isPlaying && s.current == TrackRef(playlist: "focus", track: "f3"))
    }

    @Test func shuffleSongsLoadsLikedSongsFirst() {
        var s = mainMenu()
        s.library = []  // fresh sign-in: nothing fetched yet
        send(&s, .wheel(2), .select)
        #expect(s.top.screen == .tracks(playlist: Playlist.likedSongsID) && s.top.loading)
        #expect(send(&s, .loaded(token: 1, library: library)) == [.load(trackID: "l0", autoplay: true, generation: 1)])
        #expect(s.top.screen == .now && s.shuffle && s.shuffleToken == nil)

        s = mainMenu(); s.library = []
        send(&s, .wheel(2), .select, .loaded(token: 1, library: nil))  // fetch fails
        #expect(s.top.error)
        send(&s, .select, .loaded(token: 2, library: library))  // retry succeeds and still shuffles
        #expect(s.top.screen == .now && s.shuffle && s.current?.track == "l0")
    }

    @Test func selectOnErrorRetriesWithNewToken() {
        var s = mainMenu()
        send(&s, .select, .loaded(token: 1, library: nil))
        #expect(s.top.error)
        send(&s, .select)
        #expect(s.top.loading && !s.top.error && s.top.token == 2)
    }

    @Test func menuPopsButNotFromAuthOrRoot() {
        var s = AppState()
        send(&s, .menu)
        #expect(s.stack.count == 1)
        send(&s, .select, .menu)
        #expect(s.top.screen == .auth)

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

    @Test func nextAdvancesAndStopsAtEndUnlessRepeatAll() {
        var s = playing(6)
        #expect(send(&s, .next) == [.load(trackID: "f7", autoplay: true, generation: 2)])
        #expect(send(&s, .next) == [.pause, .seek(0)])
        #expect(s.current?.track == "f7" && !s.isPlaying)
        s = playing(7); s.repeatMode = .all
        send(&s, .next)
        #expect(s.current?.track == "f0")
        send(&s, .prev)  // wraps back under Repeat All
        #expect(s.current?.track == "f7")
        s = playing(3); s.shuffle = true
        send(&s, .next)
        #expect(s.current?.track == "f0")  // random 0, skips current
        s = playing(3)
        send(&s, .offline(true))
        #expect(send(&s, .next, .prev) == [] && s.current?.track == "f3" && s.toast == "Offline. Can’t start playback")
    }

    @Test func prevRestartsAfterThreeSecondsElseGoesBack() {
        var s = playing(2)
        send(&s, .position(5, generation: 1))
        #expect(send(&s, .prev) == [.seek(0)] && s.current?.track == "f2")
        send(&s, .prev)
        #expect(s.current?.track == "f1")
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
        #expect(send(&s, .trackEnded(generation: 1)) == [.load(trackID: "f1", autoplay: true, generation: 2)])
        // late callbacks from the first load are ignored
        #expect(send(&s, .position(20, generation: 1), .trackEnded(generation: 1)) == [] && s.t == 0)
        s.repeatMode = .one
        #expect(send(&s, .trackEnded(generation: 2)) == [.load(trackID: "f1", autoplay: true, generation: 3)])
        #expect(send(&s, .trackEnded(generation: 2)) == [])  // same track reloaded, old callback still stale
        #expect(s.current?.track == "f1" && s.t == 0)
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
        send(&s, .next)
        #expect(s.current?.track == "f1")  // next in the new order
    }

    @Test func authDoneSignsInOrFailsOffline() {
        var s = AppState()
        send(&s, .select, .offline(true), .authDone)
        #expect(s.top.screen == .login && !s.signedIn && s.toast == "Can’t reach Spotify")
        send(&s, .offline(false), .select, .authDone)
        #expect(s.stack == [Frame(screen: .main)] && s.signedIn)
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
        #expect(send(&s, .expire) == [.stop])
        #expect(s.stack == [Frame(screen: .login)] && !s.signedIn && s.current == nil && s.library.isEmpty)
        #expect(s.toast == "Session expired. Log in again")
    }

    @Test func resetRestoresInitialState() {
        var s = playing()
        #expect(send(&s, .reset) == [.stop])
        var fresh = AppState()
        fresh.tok = s.tok; fresh.playGen = s.playGen
        #expect(s == fresh && s.tok == 2)
        send(&s, .select, .authDone, .select, .loaded(token: 1, library: library))  // late load from before reset
        #expect(s.top.loading && s.top.token == 3)
    }

    @Test func logOutGoesThroughConfirm() {
        var s = playing()
        send(&s, .menu, .menu, .menu, .wheel(4), .select, .wheel(7), .select)
        #expect(s.top.screen == .confirm)
        send(&s, .select)  // Cancel
        #expect(s.top.screen == .settings)
        send(&s, .select, .wheel(1), .select)
        #expect(s.top.screen == .login && s.toast == "Logged out" && s.current == nil)
    }
}

@MainActor final class FakePlayer: Player {
    var calls: [String] = []
    func load(trackID: String, autoplay: Bool, generation: Int) { calls.append("load \(trackID) \(autoplay)") }
    func pause() { calls.append("pause") }
    func resume() { calls.append("resume") }
    func stop() { calls.append("stop") }
    func seek(to seconds: Double) { calls.append("seek \(seconds)") }
    func setVolume(_ percent: Int) { calls.append("volume \(percent)") }
}

@MainActor @Test func storeRunsEffectsAgainstPlayer() {
    let player = FakePlayer()
    var s = playing()
    s.isPlaying = true
    let store = Store(player: player, state: s, env: Dependencies(now: { 0 }, random: { _ in 0 }))
    store.send(.play)
    store.send(.wheel(1))
    store.send(.next)
    #expect(player.calls == ["pause", "volume 65", "load f1 false"])
}
