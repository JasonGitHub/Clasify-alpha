import Testing
@testable import ClasifyCore

/// A free Spotify account (CLA-66): the login works, but Clasify needs Premium to play. The
/// Premium screen shows (card AX, screen 135), with no toast (change 180).
@Suite struct PremiumTests {
    /// A later launch: the browser login of a free account ended on the Premium screen.
    func onPremium() -> AppState {
        var s = afterSetup()
        send(&s, .select)  // Log in with Spotify
        #expect(send(&s, .notPremium(token: s.authAttempt)).isEmpty)  // the stored login stays for "Check again"
        return s
    }

    @Test func aFreeAccountSeesThePremiumScreen() {
        let s = onPremium()
        #expect(s.stack == [Frame(screen: .premium)] && !s.signedIn && !s.restoring)
        #expect(s.rows(for: s.top) == [.checkPremium, .getPremium, .premiumLogOut] && s.top.sel == 0)
        #expect(s.toast.isEmpty && !s.premiumFound && s.premiumAt == 0 && s.navForward)
        // A late login result of that attempt changes nothing.
        var late = s
        send(&late, .authDone(token: 1, ok: true))
        #expect(late == s)
    }

    @Test func checkAgainWithNoPremiumChangesNothing() {
        var s = onPremium()
        let token = s.authAttempt + 1
        #expect(send(&s, .select, now: 200) == [.restoreSession(token: token)])
        #expect(s.restoring && s.premiumAt == 200)  // the cable's light flows once from here
        #expect(send(&s, .select, now: 200.5).isEmpty)  // a second press while it checks starts no login
        send(&s, .notPremium(token: token), now: 201)
        #expect(s.stack == [Frame(screen: .premium)] && !s.restoring && !s.premiumFound && s.toast.isEmpty)
        send(&s, .restored(token: token, ok: true))  // late, from that check: stale
        #expect(!s.signedIn && !s.premiumFound)
    }

    @Test func checkAgainFindsPremiumAndGoesOn() {
        var s = onPremium()
        send(&s, .select, now: 200)
        #expect(send(&s, .restored(token: s.authAttempt, ok: true), now: 300) == [.prefetch])
        #expect(s.signedIn && s.premiumFound && s.premiumAt == 300 && s.top.screen == .premium)
        send(&s, .tick, now: 301)
        #expect(s.top.screen == .premium)  // "Premium" shows for 1.5 s
        send(&s, .tick, now: 301.6)
        #expect(s.stack == [Frame(screen: .main)])  // setup ended before: the main menu

        // A press during the 1.5 s goes on at once. During setup, with the Spotify app missing,
        // the Spotify App screen comes next (card BB).
        var setup = onPremium()
        setup.setupDone = false; setup.spotifyApp = false
        send(&setup, .select, .restored(token: setup.authAttempt + 1, ok: true), .select)
        #expect(setup.stack == [Frame(screen: .spotifyApp)])
    }

    @Test func checkAgainThatFailsChangesNothing() {
        var s = onPremium()
        send(&s, .select, .restored(token: s.authAttempt + 1, ok: false))
        #expect(s.stack == [Frame(screen: .premium)] && !s.restoring && !s.signedIn && s.toast.isEmpty)
    }

    @Test func getPremiumOpensTheBrowser() {
        var s = onPremium()
        #expect(send(&s, .wheel(1), .select) == [.getPremium])
        #expect(s.top.screen == .premium && s.top.sel == 1)
    }

    @Test func logOutAndMenuGoBackToTheLogin() {
        for keys: [Action] in [[.wheel(2), .select], [.menu]] {
            var s = onPremium()
            send(&s, .select)  // a "Check again" that still runs
            let token = s.authAttempt
            #expect(send(&s, keys) == [.logOut])  // the stored login goes
            #expect(s.stack == [Frame(screen: .login)] && !s.navForward && !s.restoring && !s.sessionEnded)
            #expect(s.toast.isEmpty && s.rows(for: s.top) == [.logIn])  // the normal words (as change 181)
            send(&s, .notPremium(token: token))  // late, from that check: dropped
            #expect(s.stack == [Frame(screen: .login)])
        }
    }

    @Test func aLateResultOfAnOlderLoginIsDropped() {
        // "Open browser again" starts a new login. The older one ends late as not Premium.
        var s = afterSetup()
        send(&s, .select)  // Log in with Spotify
        let old = s.authAttempt
        send(&s, .select)  // Open browser again
        #expect(s.top.screen == .auth && s.top.token != old)
        var late = s
        send(&late, .notPremium(token: old))
        #expect(late == s)
        // The result of the new login counts.
        send(&s, .notPremium(token: s.authAttempt))
        #expect(s.stack == [Frame(screen: .premium)])
        // A restore token that is not the one that runs is dropped too.
        var check = s
        send(&check, .select)  // Check again
        let before = check
        send(&check, .notPremium(token: check.authAttempt - 1))
        #expect(check == before && check.restoring)
    }

    @Test func aStoredFreeLoginShowsThePremiumScreenAtLaunch() {
        var s = afterSetup()
        send(&s, .launch)
        send(&s, .notPremium(token: s.authAttempt))
        #expect(s.stack == [Frame(screen: .premium)] && !s.restoring)
        // During the first launch setup, Hello stays. The browser login after it shows the screen.
        var first = AppState()
        send(&first, .launch)
        send(&first, .notPremium(token: first.authAttempt))
        #expect(first.stack == [Frame(screen: .hello)] && !first.restoring)
    }

    @Test func aSessionThatFindsOutLaterShowsThePremiumScreen() {
        var s = playing()
        #expect(send(&s, .notPremium(token: nil)) == [.stop])
        #expect(s.stack == [Frame(screen: .premium)] && !s.signedIn && s.current == nil && s.library.isEmpty)
        // Signed out, with no login running: a second report is dropped.
        var none = afterSetup()
        send(&none, .notPremium(token: nil))
        #expect(none.stack == [Frame(screen: .login)])
    }
}

@MainActor @Test func storeShowsThePremiumScreenForAFreeLogin() async {
    let lib = FakeLibrary()
    lib.loginResult = .notPremium
    let store = Store(player: FakePlayer(), library: lib, state: afterSetup(), env: Dependencies(now: { 0 }, random: { _ in 0 }))
    store.send(.select)  // Log in with Spotify
    while store.state.top.screen != .premium { await Task.yield() }
    store.send(.select)  // Check again
    while store.state.restoring { await Task.yield() }
    #expect(lib.calls == ["logIn", "restoreSession"] && store.state.top.screen == .premium)
    lib.loginResult = .ok
    store.send(.select)
    while !store.state.premiumFound { await Task.yield() }
    #expect(store.state.signedIn)
}
