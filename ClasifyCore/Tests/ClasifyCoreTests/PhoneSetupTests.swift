import Testing
@testable import ClasifyCore

/// CLA-202, PR 2: the phone's setup has no Pick Your Music (Apple Music is its only service), and
/// it has no Activate and no beta notices. The Mac keeps all of them.
@Suite struct PhoneSetupTests {
    /// A new phone with Apple Music, as the Store gives it (the service lock and the library's words).
    func newPhone() -> AppState {
        var s = AppState(platform: .phone)
        s.service = .appleMusic
        send(&s, .libraryWords(.appleMusic))
        return s
    }

    /// The setup's events in order, and every effect, from the launch to a song that plays.
    func fullSetupAndPlay(_ s: inout AppState) -> (steps: [String], effects: [Effect]) {
        var fx: [Effect] = []
        func send(_ s: inout AppState, _ actions: Action..., now: Double) -> [Effect] {  // keeps `.track`
            let e = Dependencies(now: { now }, random: { _ in 0 })
            return actions.flatMap { reduce(&s, $0, e) }
        }
        fx += send(&s, .launch, .restored(token: 1, ok: false), now: 100)
        fx += send(&s, .select, now: 101)  // Hello
        fx += send(&s, .select, now: 102)  // Color: the Apple Music login starts
        fx += send(&s, .authDone(token: s.top.token, ok: true), now: 103)
        fx += send(&s, .tick, now: 105)  // Logged In, then Your Music
        fx += send(&s, .playlistsRefreshed([focusInfo]), now: 106)
        fx += send(&s, .libraryCounted(LibraryCount(playlists: [focusInfo], songs: liked.tracks)), now: 107)  // `all_set` waits for it
        fx += send(&s, .tracksLoaded(token: s.top.token, playlist: s.albumsList, tracks: liked.tracks), now: 110)
        fx += send(&s, .tick, now: 120)  // the main menu
        fx += send(&s, .wheel(4), .select, now: 121)  // Songs
        fx += send(&s, .tracksLoaded(token: s.top.token, playlist: "library:songs", tracks: focus.tracks), .select, now: 121)
        fx += send(&s, .play, .menuBarClick(shown: true), .view3D(.turn, open: true), now: 122)
        let steps = fx.compactMap { e -> String? in
            if case .track(let event) = e, event.name == "setup_step", case .text(let step)? = event.properties["step"] { return step }
            return nil
        }
        return (steps, fx)
    }

    @Test func aPhoneSetupHasNoPickAndNoMacOrSpotifyEffect() {
        var s = newPhone()
        let (steps, fx) = fullSetupAndPlay(&s)
        #expect(s.setupDone && s.service == .appleMusic && s.current != nil)
        #expect(steps == ["hello", "color", "your_music", "all_set"])  // the Mac's values for these steps
        #expect(fx.contains(.logIn(token: 2)))
        let mac: [Effect] = [.showWindow, .hideWindow, .getSpotifyApp, .getPremium, .getNewBeta, .checkLatestBeta, .quitPlayer, .quit]
        for e in fx {
            #expect(!mac.contains(e), "\(e)")
            switch e {
            case .logInActivating, .openActivatePage, .checkActivation, .sendActivationAgain, .setVolume: Issue.record("\(e)")
            case .setService(let service) where service != .appleMusic: Issue.record("\(e)")
            case .track(let event) where ["music_pick", "service_switch", "beta_renewal"].contains(event.name): Issue.record("\(e)")
            default: break
            }
        }
    }

    @Test func theMacSetupStillPicksTheService() {
        var s = activatedMac()
        send(&s, .spotifyAppFound(true), .launch, .restored(token: 1, ok: false), .select, .select)
        #expect(s.top.screen == .pickMusic)
        var gated = AppState()  // not activated: the Mac still shows Activate after the login
        #expect(gated.activateGated)
        gated.platform = .phone
        #expect(!gated.activateGated)
    }

    @Test func aDeniedPromptOnColorShowsAccessOffWithoutUseSpotify() {
        var s = newPhone()
        send(&s, .launch, .restored(token: 1, ok: false), .select, .select)
        #expect(s.top.screen == .color && s.top.token == 2)
        send(&s, .accessDenied(token: 1))  // an older attempt
        #expect(s.top.screen == .color)
        send(&s, .accessDenied(token: 2))
        #expect(s.stack == [Frame(screen: .accessOff)] && s.rows(for: s.top) == [.openPrivacy])
        #expect(AppState().rows(for: Frame(screen: .accessOff)) == [.openPrivacy, .useSpotify])  // the Mac
    }

    @Test func noPlanOnColorShowsThePlanScreenWithoutUseSpotify() {
        var s = newPhone()
        send(&s, .launch, .restored(token: 1, ok: false), .select, .select)
        send(&s, .notPremium(token: 2))
        #expect(s.top.screen == .premium && s.rows(for: s.top) == [.checkPremium, .getPremium])
        var mac = AppState()
        mac.service = .appleMusic
        #expect(mac.rows(for: Frame(screen: .premium)) == [.checkPremium, .getPremium, .useSpotify])
    }

    @Test func aFailedPromptAsksAgainWithTheNextPress() {
        var s = newPhone()
        send(&s, .launch, .restored(token: 1, ok: false), .select, .select)
        send(&s, .authDone(token: 2, ok: false))
        #expect(s.top.screen == .color && s.top.token == 0)
        #expect(send(&s, .select).contains(.logIn(token: 3)))
    }

    @Test func aLogOutGoesBackToColorAndALoginStartsAgain() {
        var s = newPhone()
        _ = fullSetupAndPlay(&s)
        for _ in 0..<4 where s.top.screen != .main { send(&s, .menu) }
        s.top.sel = s.rows(for: s.top).firstIndex(of: .settings) ?? -1
        send(&s, .select)
        s.top.sel = s.rows(for: s.top).firstIndex(of: .logOut) ?? -1
        send(&s, .select, .wheel(1), .select)  // Log out, then confirm
        #expect(s.stack == [Frame(screen: .color)] && !s.signedIn)
        #expect(send(&s, .select).contains { if case .logIn = $0 { true } else { false } })
    }

    @Test func thePhoneHasNoActivateAndNoBetaNotices() {
        var s = AppState(platform: .phone)
        s.setupDone = true
        send(&s, .launch)
        #expect(s.top.screen == .main)  // a Mac that is not activated shows Activate here
        let beta = BetaBuild(signed: 1000)
        #expect(send(&s, .betaBuild(beta), now: 2000).isEmpty)
        #expect(send(&s, .latestBeta(999), .tick, now: beta.warnsAt + 1).isEmpty && s.top.screen == .main)
        #expect(send(&s, .tick, now: beta.endsAt + 1).isEmpty && s.top.screen == .main)
        var mac = mainMenu()
        #expect(send(&mac, .betaBuild(beta), now: 2000) == [.checkLatestBeta])
    }

    @MainActor @Test func theStoreReadsASavedSpotifyServiceAsAppleMusicOnThePhone() {
        let saved = FakeSettings()
        var settings = Settings()
        settings.service = .spotify
        settings.save(to: saved)
        #expect(Store(player: FakePlayer(), library: FakeLibrary(), settings: saved, platform: .phone).state.service == .appleMusic)
        #expect(Store(player: FakePlayer(), library: FakeLibrary(), settings: saved).state.service == .spotify)
    }
}
