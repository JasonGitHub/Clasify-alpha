import Testing
@testable import ClasifyCore

let library = [
    Playlist(name: "Liked Songs", tracks: [Track(title: "A", artist: "x", duration: 10), Track(title: "B", artist: "y", duration: 20)]),
    Playlist(name: "Focus", tracks: (0..<8).map { Track(title: "F\($0)", artist: "z", duration: 30) }),
]

let env = Dependencies(now: { 100 }, random: { _ in 0 })

func send(_ s: inout AppState, _ actions: Action..., now: Double = 100) {
    let e = Dependencies(now: { now }, random: { _ in 0 })
    for a in actions { reduce(&s, a, e) }
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
    @Test func wheelMovesSelectionAndScrollsWindow() {
        var s = mainMenu()
        send(&s, .wheel(-3))
        #expect(s.top.sel == 0)
        send(&s, .wheel(99))
        #expect(s.top.sel == 3)  // clamped to last row

        s = playing()
        send(&s, .menu)  // back to Focus tracks
        send(&s, .wheel(7))
        #expect(s.top.sel == 7 && s.top.off == 2)
        send(&s, .menu, .menu, .select, .wheel(-2))  // now playing, volume
        #expect(s.volume == 50 && s.overlayUntil == 101.5)
    }

    @Test func selectPushesScreensAndTogglesSettings() {
        var s = mainMenu()
        send(&s, .wheel(3), .select)
        #expect(s.top.screen == .settings)
        send(&s, .select, .wheel(1), .select, .select)
        #expect(s.shuffle && s.repeatMode == .one)
        send(&s, .wheel(5), .select)
        #expect(s.engine == .spotifyApp && s.toast == "Plays through the Spotify app")
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
        #expect(s.top.screen == .tracks(playlist: 1))
    }

    @Test func playTogglesAndBlocksResumeOffline() {
        var s = mainMenu()
        send(&s, .play)
        #expect(s.toast == "Nothing playing yet")
        s = playing()
        send(&s, .play)
        #expect(!s.isPlaying)
        send(&s, .offline(true), .play)
        #expect(!s.isPlaying && s.toast == "Offline. Can’t resume")
    }

    @Test func nextAdvancesAndStopsAtEndUnlessRepeatAll() {
        var s = playing(6)
        send(&s, .next)
        #expect(s.current?.track == 7)
        send(&s, .next)
        #expect(s.current?.track == 7 && !s.isPlaying)
        s = playing(7); s.repeatMode = .all
        send(&s, .next)
        #expect(s.current?.track == 0)
        s = playing(3); s.shuffle = true
        send(&s, .next)
        #expect(s.current?.track == 0)  // random 0, skips current
    }

    @Test func prevRestartsAfterThreeSecondsElseGoesBack() {
        var s = playing(2)
        s.t = 5
        send(&s, .prev)
        #expect(s.current?.track == 2 && s.t == 0)
        send(&s, .prev)
        #expect(s.current?.track == 1)
    }

    @Test func tickAdvancesTimeExpiresToastAndEndsTrack() {
        var s = playing()
        send(&s, .tick)
        #expect(s.t == 0.25)
        s.toast = "hi"; s.toastUntil = 101
        send(&s, .tick, now: 102)
        #expect(s.toast == "")
        s.t = 29.9
        send(&s, .tick)
        #expect(s.current?.track == 1 && s.t == 0)
        s.t = 29.9; s.repeatMode = .one
        send(&s, .tick)
        #expect(s.current?.track == 1 && s.t == 0)
    }

    @Test func loadedIgnoresStaleTokens() {
        var s = mainMenu()
        send(&s, .select, .loaded(token: 99, library: library))
        #expect(s.top.loading)
        send(&s, .loaded(token: 1, library: library))
        #expect(!s.top.loading && !s.top.error)
        #expect(s.rows(for: s.top) == [.playlist(1)])
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
        send(&s, .offline(true))
        #expect(s.offline && !s.isPlaying && s.toast == "Connection lost. Paused")
        send(&s, .menu, .select)  // Focus track 0
        #expect(s.top.screen == .tracks(playlist: 1) && s.toast == "Offline. Can’t start playback")
    }

    @Test func expireSignsOut() {
        var s = AppState()
        send(&s, .expire)
        #expect(s.toast == "")
        s = playing()
        send(&s, .expire)
        #expect(s.stack == [Frame(screen: .login)] && !s.signedIn && s.current == nil)
        #expect(s.toast == "Session expired. Log in again")
    }

    @Test func resetRestoresInitialState() {
        var s = playing()
        send(&s, .reset)
        #expect(s == AppState())
    }

    @Test func logOutGoesThroughConfirm() {
        var s = playing()
        send(&s, .menu, .menu, .menu, .wheel(4), .select, .wheel(8), .select)
        #expect(s.top.screen == .confirm)
        send(&s, .select)  // Cancel
        #expect(s.top.screen == .settings)
        send(&s, .select, .wheel(1), .select)
        #expect(s.top.screen == .login && s.toast == "Logged out" && s.current == nil)
    }

    @MainActor @Test func storeSendsThroughReducer() {
        let store = Store(env: env)
        store.send(.select)
        #expect(store.state.top.screen == .auth)
    }
}
