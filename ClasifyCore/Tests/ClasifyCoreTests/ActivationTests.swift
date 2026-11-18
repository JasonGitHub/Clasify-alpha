import Testing
@testable import ClasifyCore

/// CLA-128 PR1: setup's Activate step, behind the `activate.on` switch (off by default).
/// Order: Hello, Color, Pick Your Music, Log In, Activate, Your Music.
@Suite struct ActivationTests {
    /// The first launch on "You’re in", after the login; the switch as given.
    func loggedIn(switchOn: Bool) -> AppState {
        var s = AppState()
        s.activateOn = switchOn
        send(&s, .spotifyAppFound(true), .launch, .restored(token: 1, ok: false), .select)  // on the color pick
        send(&s, .select, .select, .select, .authDone(token: 2, ok: true))  // the color, Spotify, Log In
        return s
    }

    @Test func theSwitchIsOffByDefaultAndSetupIsAsToday() {
        #expect(!AppState().activateOn && AppState().activation == .locked)
        var s = loggedIn(switchOn: false)
        send(&s, .tick, now: 101.5)
        #expect(s.top.screen == .yourMusic)
    }

    /// Activate comes after the login, before Your Music. "Activate" starts it; the mail is
    /// out; "Check again" asks; an active answer goes on to Your Music.
    @Test func activateComesBeforeYourMusic() {
        var s = loggedIn(switchOn: true)
        send(&s, .tick, now: 101.5)
        #expect(s.stack == [Frame(screen: .activate)] && s.rows(for: s.top) == [.activate])
        #expect(send(&s, .select) == [.startActivation(request: 1)])
        send(&s, .activation(.waiting, request: 1))
        #expect(s.activation == .waiting && s.top.screen == .activate && s.rows(for: s.top) == [.checkMail])
        #expect(send(&s, .select) == [.checkActivation(request: 2)])
        let fx = send(&s, .activation(.active, request: 2))
        #expect(s.activation == .active && s.top.screen == .yourMusic && s.top.loading)
        #expect(fx.contains(.fetchTracks(token: s.top.token, playlist: Playlist.likedSongsID)))
    }

    /// The app asks again when the person comes back or its timer runs: only while the mail
    /// is out and the Activate screen shows.
    @Test func checkActivationAsksOnlyWhileWaiting() {
        var s = loggedIn(switchOn: true)
        send(&s, .tick, now: 101.5)
        #expect(send(&s, .checkActivation).isEmpty)  // locked: nothing to check
        send(&s, .select, .activation(.waiting, request: 1))
        #expect(send(&s, .checkActivation) == [.checkActivation(request: 2)])
        var main = mainMenu()
        main.activation = .waiting
        #expect(send(&main, .checkActivation).isEmpty)  // not on the Activate screen
    }

    /// An answer to an older request is dropped. The stored activation (no request number)
    /// always lands.
    @Test func anOlderAnswerIsDropped() {
        var s = loggedIn(switchOn: true)
        send(&s, .tick, now: 101.5)
        send(&s, .select, .activation(.waiting, request: 1), .select)  // request 2 is out
        send(&s, .activation(.active, request: 1))
        #expect(s.activation == .waiting && s.top.screen == .activate)
        var launch = AppState()
        send(&launch, .activation(.active, request: nil))
        #expect(launch.activation == .active)
    }

    /// Full, turned off and mail busy keep the screen, with one row to try again.
    @Test func fullOffAndMailBusyStayOnTheScreen() {
        for answer in [Activation.full, .off, .mailBusy, .locked] {
            var s = loggedIn(switchOn: true)
            send(&s, .tick, now: 101.5)
            send(&s, .select, .activation(answer, request: 1))
            #expect(s.activation == answer && s.top.screen == .activate && s.rows(for: s.top) == [.activate])
            #expect(send(&s, .select) == [.startActivation(request: 2)])
        }
    }

    /// Already active (the stored activation, sent before the launch): no Activate step.
    @Test func anActiveMacSkipsTheStep() {
        var s = AppState()
        s.activateOn = true
        send(&s, .activation(.active, request: nil))
        send(&s, .spotifyAppFound(true), .launch, .restored(token: 1, ok: false), .select)
        send(&s, .select, .select, .select, .authDone(token: 2, ok: true), .tick, now: 101.5)
        #expect(s.top.screen == .yourMusic)
    }

    @Test func theSwitchIsSavedWithTheSettings() {
        let store = FakeSettings()
        #expect(!Settings(from: store).activateOn)
        var saved = Settings()
        saved.activateOn = true
        saved.save(to: store)
        #expect(Settings(from: store).activateOn)
    }

    /// The store asks the server and sends its answer back with the request number.
    @MainActor @Test func theStoreAsksTheActivator() async {
        var state = loggedIn(switchOn: true)
        send(&state, .tick, now: 101.5)
        let env = Dependencies(now: { 101.5 }, random: { _ in 0 })
        let store = Store(player: FakePlayer(), library: FakeLibrary(), state: state, env: env, activator: FakeActivator())
        store.send(.select)
        var tries = 0
        while tries < 200, store.state.activation != .waiting {
            tries += 1
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.state.activation == .waiting && store.state.activateRequest == 1)
    }
}

struct FakeActivator: Activator {
    func start() async -> Activation { .waiting }
    func status() async -> Activation { .active }
}
