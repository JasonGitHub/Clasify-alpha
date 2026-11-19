import Testing
@testable import ClasifyCore

/// CLA-143, card BY: on a Mac that still has to activate, the Spotify login page takes the
/// tab on to the activate page. The device then opens Activate on 320, not 319.
@Suite struct HandOverTests {
    /// The first setup on the Log In screen (Spotify), the gate as given. The next `.select`
    /// starts the browser login with token 2.
    func atLogIn(gate: Bool, activated: Bool = false) -> AppState {
        var s = AppState()
        s.activateOn = gate
        s.activated = activated
        send(&s, .spotifyAppFound(true), .launch, .restored(token: 1, ok: false), .select)  // on the color pick
        send(&s, .select, .select)  // the color, Spotify
        return s
    }

    @Test func aGatedSpotifyLoginCarriesTheActivatePage() {
        var s = atLogIn(gate: true)
        #expect(send(&s, .select) == [.logInActivating(token: 2)])
        var off = atLogIn(gate: false)
        #expect(send(&off, .select) == [.logIn(token: 2)])
        var done = atLogIn(gate: true, activated: true)
        #expect(send(&done, .select) == [.logIn(token: 2)])
    }

    /// "Open browser again" asks again, and a new login forgets the hand-over of the old one.
    @Test func openBrowserAgainAsksAgain() {
        var s = atLogIn(gate: true)
        send(&s, .select, .loginCarriesActivate(token: 2))
        #expect(s.activateHandOver)
        send(&s, .authDone(token: 2, ok: false))
        #expect(s.top.screen == .loginFailed && !s.activateHandOver)
        #expect(send(&s, .select) == [.logInActivating(token: 3)])
    }

    /// 175 "You’re in", then 320 with its checks; no second browser trip.
    @Test func theHandOverOpensActivateOn320() {
        var s = atLogIn(gate: true)
        send(&s, .select, .loginCarriesActivate(token: 2), .authDone(token: 2, ok: true))
        #expect(s.top.screen == .loggedIn)
        let fx = send(&s, .tick, now: 101.5)
        #expect(s.stack == [Frame(screen: .activate)] && s.activateStep == .browserOpen)
        #expect(s.activateStopAt == 101.5 + activateChecksFor && !s.activateHandOver)
        #expect(!fx.contains { if case .openActivatePage = $0 { true } else { false } })
        send(&s, .checkActivation, now: 120)
        send(&s, .activation(.waiting(email: "sam@example.com", mail: 1), request: s.activateRequest), now: 121)
        #expect(s.activateStep == .checkMail)
    }

    /// No page in time (offline, slow): today's 319.
    @Test func withNoPageActivateOpensOn319() {
        var s = atLogIn(gate: true)
        send(&s, .select, .authDone(token: 2, ok: true))
        send(&s, .tick, now: 101.5)
        #expect(s.top.screen == .activate && s.activateStep == .join)
    }

    /// The token exchange fails after the hop: today's login error, never 320.
    @Test func aFailedLoginAfterTheHopShowsTheLoginError() {
        var s = atLogIn(gate: true)
        send(&s, .select, .loginCarriesActivate(token: 2), .authDone(token: 2, ok: false))
        #expect(s.top.screen == .loginFailed && !s.activateHandOver && s.activateStopAt == 0)
    }

    @Test func aStaleHandOverIsDropped() {
        var s = atLogIn(gate: true)
        send(&s, .select, .loginCarriesActivate(token: 1))
        #expect(!s.activateHandOver)
        var off = atLogIn(gate: false)
        send(&off, .select, .loginCarriesActivate(token: 2))
        #expect(!off.activateHandOver)
    }

    /// Apple Music has no login page: its prompt is a plain `.logIn`.
    @Test func appleMusicKeepsThePlainLogin() {
        var s = AppState()
        s.activateOn = true
        send(&s, .spotifyAppFound(true), .launch, .restored(token: 1, ok: false), .select, .select)  // the color
        #expect(s.top.screen == .pickMusic)
        send(&s, .wheel(1))  // Apple Music, under Spotify
        #expect(send(&s, .select) == [.setService(.appleMusic), .logIn(token: 2)])
    }

    /// The store asks for the page first and hands it to the login.
    @MainActor @Test func theStoreHandsThePageToTheLogin() async {
        let lib = FakeLibrary()
        let store = Store(player: FakePlayer(), library: lib, state: atLogIn(gate: true), env: Dependencies(now: { 100 }, random: { _ in 0 }), activator: FakeActivator())
        store.send(.select)
        while store.state.top.screen != .loggedIn { await Task.yield() }
        #expect(lib.calls.first == "logIn https://getmypod.app/activate/?d=code" && store.state.activateHandOver)
    }

    /// No page (offline or an error): the login goes on as before.
    @MainActor @Test func withNoPageTheLoginGoesOnAsBefore() async {
        let lib = FakeLibrary()
        let store = Store(player: FakePlayer(), library: lib, state: atLogIn(gate: true), env: Dependencies(now: { 100 }, random: { _ in 0 }), activator: FakeActivator(page: nil))
        store.send(.select)
        while store.state.top.screen != .loggedIn { await Task.yield() }
        #expect(lib.calls.first == "logIn" && !store.state.activateHandOver)
    }

    /// MENU while the page is asked for: that login never starts (Codex on #330).
    @MainActor @Test func aLoginCancelledWhileThePageIsAskedForNeverStarts() async {
        let lib = FakeLibrary()
        let store = Store(player: FakePlayer(), library: lib, state: atLogIn(gate: true), env: Dependencies(now: { 100 }, random: { _ in 0 }), activator: FakeActivator(wait: 0.2))
        store.send(.select)
        store.send(.menu)  // back to the Log In screen
        try? await Task.sleep(for: .milliseconds(600))
        #expect(lib.calls == ["cancelLogIn"] && !store.state.activateHandOver && store.state.top.screen == .login)
    }

    /// The page wait is at most 2 s; a late answer counts as none.
    @MainActor @Test func aLatePageCountsAsNone() async {
        #expect(Store.pageWait == 2)
        #expect(await Store.within(0.05) { try? await Task.sleep(for: .seconds(5)); return "late" } == nil)
        #expect(await Store.within(5) { "on time" } == "on time")
    }
}
