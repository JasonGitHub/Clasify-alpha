import Testing
@testable import ClasifyCore

/// CLA-140: the activation gate works after setup too. The app remembers "activated"
/// (`activate.done`). A set-up Mac that is not activated sees only Activate at launch, and a
/// remembered Mac that the server no longer counts as active locks again.
@Suite struct ActivationGateTests {
    let sam = Activation.waiting(email: "sam@example.com", mail: 1)

    /// After setup, at launch, with the gate on.
    func gated(remembered: Bool) -> AppState {
        var s = afterSetup()
        s.activateOn = true
        s.activated = remembered
        send(&s, .spotifyAppFound(true))
        return s
    }

    /// Playing on Now Playing, on a remembered Mac with the gate on.
    func rememberedPlaying() -> AppState {
        var s = playing()
        s.activateOn = true
        s.activated = true
        return s
    }

    @Test func aLaunchThatIsNotRememberedShowsOnlyActivate() {
        var s = gated(remembered: false)
        #expect(send(&s, .launch) == [.showWindow])  // no restore
        #expect(s.stack == [Frame(screen: .activate)] && s.activateStep == .join && !s.restoring)
    }

    /// Nothing starts a restore or playback behind Activate: the app comes to the front, the
    /// menu bar icon, the keys, or a song that Spotify already plays.
    @Test func nothingRestoresOrPlaysBehindActivate() {
        var s = gated(remembered: false)
        send(&s, .launch)
        var fx = send(&s, .activated)
        fx += send(&s, .menuBarClick(shown: true), .menuBarClick(shown: false))
        fx += send(&s, .play, .next, .prev)
        fx += send(&s, .adopted(track: "t1", playlist: nil, playing: true, position: 0, generation: s.playGen))
        #expect(fx.allSatisfy { $0 == .showWindow || $0 == .hideWindow })
        #expect(!s.restoring && !s.signedIn && s.current == nil && s.stack == [Frame(screen: .activate)])
    }

    /// 323, then the main menu, and only now the stored login comes back.
    @Test func activatingAtLaunchGoesToMainAndRestores() {
        var s = gated(remembered: false)
        send(&s, .launch)
        send(&s, .activation(.active, request: nil), now: 100)
        #expect(s.activated && s.settings.activated && s.activateStep == .confirmed)
        #expect(send(&s, .tick, now: 101.5) == [.restoreSession(token: 1)])
        #expect(s.stack == [Frame(screen: .main)] && s.restoring)
        send(&s, .restored(token: 1, ok: true))
        #expect(s.signedIn && s.stack == [Frame(screen: .main)])
    }

    @Test func aRememberedLaunchOpensMainAsToday() {
        var s = gated(remembered: true)
        #expect(send(&s, .launch) == [.restoreSession(token: 1)])
        #expect(s.stack == [Frame(screen: .main)])
    }

    @Test func theGateOffChangesNothing() {
        var s = gated(remembered: false)
        s.activateOn = false
        #expect(send(&s, .launch) == [.restoreSession(token: 1)])
        #expect(s.stack == [Frame(screen: .main)])
        send(&s, .activation(.off, request: nil))
        #expect(s.stack == [Frame(screen: .main)])
    }

    /// The launch answer for a remembered Mac: locked (319), mail out (321, a new flow after a
    /// turn-off) and off (326) lock it. Playback stops, and Play cannot start it again.
    @Test func aLaunchAnswerThatIsNotActiveLocksARememberedMac() {
        let answers: [(Activation, ActivateStep)] = [(.locked, .join), (sam, .checkMail), (.off, .off)]
        for (answer, step) in answers {
            var s = rememberedPlaying()
            let fx = send(&s, .activation(answer, request: nil), now: 300)
            #expect(fx.contains(.stop) && fx.contains(.showWindow))
            #expect(s.stack == [Frame(screen: .activate)] && s.activateStep == step)
            #expect(!s.activated && !s.settings.activated && s.current == nil && !s.isPlaying)
            #expect(send(&s, .play, .next, .prev, now: 301).isEmpty)
        }
    }

    /// A lock while the launch restore still runs: its late results are stale, and Activate
    /// stays (Codex on #325). After 323 a new restore starts.
    @Test func aLockDropsTheRestoreOnItsWay() {
        var s = gated(remembered: true)
        send(&s, .launch, .activation(.off, request: nil))
        #expect(!s.restoring && s.stack == [Frame(screen: .activate)])
        send(&s, .accessDenied(token: 1), .notPremium(token: 1), .restored(token: 1, ok: true), .activated)
        #expect(s.stack == [Frame(screen: .activate)] && !s.signedIn && !s.restoring)
        send(&s, .activation(.active, request: nil), now: 100)
        #expect(send(&s, .tick, now: 101.5) == [.restoreSession(token: 3)])
        #expect(s.stack == [Frame(screen: .main)])
    }

    /// The session expires after a lock: the login after it goes to Activate, not to the main
    /// menu (Codex on #325).
    @Test func aLoginAfterALockGoesToActivate() {
        var s = gated(remembered: true)
        send(&s, .launch, .restored(token: 1, ok: true), .activation(.off, request: nil), .expire)
        #expect(s.top.screen == .login)
        send(&s, .select)  // Log In
        send(&s, .authDone(token: s.authAttempt, ok: true), .select)
        #expect(s.stack == [Frame(screen: .activate)] && s.activateStep == .off)
    }

    /// No connection, a full beta, a busy mail limit, or active: the remembered Mac stays open.
    @Test func theOtherLaunchAnswersKeepARememberedMacOpen() {
        for answer: Activation in [.offline, .full, .mailBusy, .active] {
            var s = rememberedPlaying()
            let stack = s.stack
            #expect(send(&s, .activation(answer, request: nil)).isEmpty)
            #expect(s.stack == stack && s.activated && s.isPlaying)
        }
    }

    @Test func logOutKeepsTheFlag() {
        var s = rememberedPlaying()
        send(&s, .menu, .menu, .menu, .wheel(5), .select, .wheel(9), .select)  // Settings > Log out
        #expect(send(&s, .wheel(1), .select) == [.stop, .logOut])
        #expect(s.top.screen == .login && s.activated)
    }

    /// The ended beta wins over the gate, at launch and after.
    @Test func theEndedBetaWinsOverTheGate() {
        let ended = BetaBuild(signed: 1000).endsAt + 1
        var s = gated(remembered: false)
        send(&s, .betaBuild(BetaBuild(signed: 1000)), .launch, now: ended)
        #expect(s.stack == [Frame(screen: .betaEnded)])
        var r = gated(remembered: true)
        send(&r, .betaBuild(BetaBuild(signed: 1000)), .launch, .activation(.off, request: nil), now: ended)
        #expect(r.stack == [Frame(screen: .betaEnded)])
    }

    @Test func theFlagIsSaved() {
        let store = FakeSettings()
        #expect(!Settings(from: store).activated)
        var saved = Settings()
        saved.activated = true
        saved.save(to: store)
        #expect(store.values["activate.done"] == "true" && Settings(from: store).activated)
    }
}
