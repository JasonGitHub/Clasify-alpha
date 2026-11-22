import Testing
@testable import ClasifyCore

/// CLA-97, A1: the setup events, the Pick Your Music detail and the first song.
@Suite struct BetaEventTests {
    /// The `.track` events of the actions, at `now`.
    func events(_ s: inout AppState, _ actions: Action..., now: Double) -> [BetaEvent] {
        let e = Dependencies(now: { now }, random: { _ in 0 })
        return actions.flatMap { reduce(&s, $0, e) }.compactMap { (fx: Effect) -> BetaEvent? in
            if case .track(let event) = fx { return event }
            return nil
        }
    }

    /// The first launch at 100, on the color pick at 110.
    func onColor(spotifyApp: Bool = true) -> AppState {
        var s = AppState()
        _ = events(&s, .spotifyAppFound(spotifyApp), .launch, now: 100)
        _ = events(&s, .restored(token: 1, ok: false), .select, now: 110)
        return s
    }

    @Test func setupSendsEachStepOnceWithTheSecondsSinceTheFirstLaunch() {
        var s = activatedMac()
        #expect(events(&s, .spotifyAppFound(true), .launch, now: 100) == [.setupStep(.hello, seconds: 0, service: .spotify)])
        #expect(s.firstLaunchAt == 100 && s.settings.firstLaunchAt == 100)
        #expect(events(&s, .restored(token: 1, ok: false), .select, now: 110) == [.setupStep(.color, seconds: 10, service: .spotify)])
        #expect(events(&s, .select, now: 115) == [.setupStep(.pickMusic, seconds: 15, service: .spotify, color: .silver)])
        #expect(events(&s, .select, now: 120) == [
            .musicPick(.spotify, top: .spotify, spotifyApp: true), .setupStep(.logIn, seconds: 20, service: .spotify),
        ])
        #expect(events(&s, .select, .authDone(token: 2, ok: true), now: 125).isEmpty)  // the browser is still Log In
        #expect(events(&s, .tick, now: 127) == [.setupStep(.yourMusic, seconds: 27, service: .spotify)])
        #expect(events(&s, .playlistsRefreshed([]), .tracksLoaded(token: 1, playlist: Playlist.likedSongsID, tracks: liked.tracks), now: 130)
            == [.setupStep(.allSet, seconds: 30, service: .spotify)])
        #expect(s.setupDone)
        #expect(events(&s, .tick, now: 140).isEmpty && s.top.screen == .main)  // after setup: no steps
        #expect(events(&s, .menu, .reset, now: 150).isEmpty && s.firstLaunchAt == 100)  // a reset keeps the time
    }

    @Test func aStepAgainAfterMenuGoesOutAgainAndAMacSetUpBeforeHasNoTime() {
        var s = onColor()
        #expect(events(&s, .menu, now: 112) == [.setupStep(.hello, seconds: 12, service: .spotify)])
        #expect(events(&s, .select, now: 113) == [.setupStep(.color, seconds: 13, service: .spotify)])
        var old = afterSetup()
        _ = events(&old, .launch, now: 100)
        #expect(old.firstLaunchAt == nil)
    }

    /// Jason 14:23 JST 11-22: the step that the press on Color sends says the color picked.
    @Test func thePressOnColorSendsTheColorPicked() {
        var s = onColor()
        #expect(events(&s, .wheel(1), now: 111).isEmpty)  // a turn tries Black on; nothing goes out
        let sent = events(&s, .select, now: 112)
        #expect(sent == [.setupStep(.pickMusic, seconds: 12, service: .spotify, color: .black)])
        #expect(sent.first?.properties["color"] == .text("black"))
        var silver = onColor()
        let picked = events(&silver, .select, now: 112)
        #expect(picked.first?.properties["color"] == .text("silver"))
        // MENU on Color is no pick, and other steps have no color.
        var back = onColor()
        #expect(events(&back, .menu, now: 112) == [.setupStep(.hello, seconds: 12, service: .spotify)])
        #expect(BetaEvent.setupStep(.hello, seconds: 1, service: .spotify).properties["color"] == nil)
    }

    @Test func pickYourMusicSaysThePickTheTopRowAndTheSpotifyApp() {
        var s = onColor(spotifyApp: false)
        _ = events(&s, .select, now: 115)  // Apple Music is the top row with no Spotify app (CLA-103)
        #expect(events(&s, .wheel(1), .select, now: 120).first == .musicPick(.spotify, top: .appleMusic, spotifyApp: false))
        var apple = onColor()
        _ = events(&apple, .select, now: 115)
        #expect(events(&apple, .wheel(1), .select, now: 120).first == .musicPick(.appleMusic, top: .spotify, spotifyApp: true))
        #expect(BetaEvent.musicPick(.appleMusic, top: .spotify, spotifyApp: true).properties
            == ["service": .text("apple_music"), "top": .text("spotify"), "spotify_app": .flag(true)])
    }

    @Test func setupErrorsSayTheirKind() {
        var failed = onColor()
        _ = events(&failed, .select, .select, .select, now: 120)
        #expect(events(&failed, .authDone(token: 2, ok: false), now: 130) == [.setupError(.loginFailed, service: .spotify)])
        var missing = onColor()
        let toApp = events(&missing, .spotifyAppFound(false), .select, .wheel(1), .select, .select, .authDone(token: 2, ok: true), .select, now: 120)
        #expect(toApp.contains(.setupError(.spotifyNotFound, service: .spotify)))
        #expect(toApp.contains(.setupStep(.spotifyCheck, seconds: 20, service: .spotify)))
        var premium = onColor()
        _ = events(&premium, .select, .select, .select, now: 120)
        #expect(events(&premium, .notPremium(token: premium.authAttempt), now: 130) == [.setupError(.premiumNeeded, service: .spotify)])
        var access = afterSetup()
        access.setupDone = false
        _ = events(&access, .launch, .restored(token: 1, ok: false), .select, .select, .select, now: 100)  // Apple Music is on top
        #expect(events(&access, .accessDenied(token: 2), now: 110) == [.setupError(.accessOff, service: .appleMusic)])
        #expect(events(&access, .wheel(1), now: 111).isEmpty)  // the same screen: no new error
    }

    @Test func activateSendsItsStepAndItsFourErrors() {
        let answers: [(Activation, SetupError)] = [(.mailBusy, .mailBusy), (.full, .betaFull), (.off, .accountOff), (.offline, .noConnection)]
        for (answer, error) in answers {
            var s = AppState()
            _ = events(&s, .spotifyAppFound(true), .launch, .restored(token: 1, ok: false), .select, now: 100)
            _ = events(&s, .select, .select, .select, .authDone(token: 2, ok: true), now: 100)
            #expect(events(&s, .tick, now: 101.5) == [.setupStep(.activate, seconds: 2, service: .spotify)])
            _ = events(&s, .select, now: 200)
            _ = events(&s, .checkActivation, .activation(.waiting(email: "sam@example.com", mail: 1), request: 2), now: 210)
            #expect(events(&s, .select, .activation(answer, request: 3), now: 300) == [.setupError(error, service: .spotify)], "\(answer)")
        }
    }

    @Test func theFirstSongGoesOutOnceWhenTheMusicPlays() {
        var s = afterSetup()
        s.firstLaunchAt = 40
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "l0"); s.isPlaying = true
        #expect(events(&s, .tick, now: 90).isEmpty)  // not yet heard
        s.t = 30  // a scrub sets the place, but the engine has not played yet
        #expect(events(&s, .tick, now: 95).isEmpty && !s.firstSongSent)
        #expect(events(&s, .position(1, generation: s.playGen + 1), now: 96).isEmpty)  // another load
        // CLA-97 A3: the sender does not take events yet: not made, made again at the next play.
        #expect(events(&s, .position(1, generation: s.playGen), now: 97).isEmpty && !s.firstSongSent)
        _ = events(&s, .analyticsOn(true), now: 99)
        #expect(s.analyticsOn)
        #expect(events(&s, .position(1, generation: s.playGen), now: 100) == [.firstSong(seconds: 60, service: .spotify)])
        #expect(s.firstSongSent && s.settings.firstSongSent)
        #expect(events(&s, .position(2, generation: s.playGen), now: 101).isEmpty)
        var old = afterSetup()  // set up before CLA-97: no time, no event
        old.current = s.current; old.isPlaying = true; old.analyticsOn = true
        #expect(events(&old, .position(1, generation: old.playGen), now: 100).isEmpty)
        #expect(BetaEvent.firstSong(seconds: 60, service: .appleMusic).properties == ["seconds": .number(60), "service": .text("apple_music")])
        #expect(BetaEvent.setupStep(.allSet, seconds: 3, service: .spotify).name == "setup_step")
    }

    @Test func theSettingsSaveTheTimeAndTheFirstSong() {
        let store = FakeSettings()
        var saved = Settings()
        saved.firstLaunchAt = 12.5; saved.firstSongSent = true
        saved.save(to: store)
        #expect(store.values["analytics.firstLaunch"] == "12.5" && store.values["analytics.firstSong"] == "true")
        #expect(Settings(from: store).firstLaunchAt == 12.5 && Settings(from: store).firstSongSent)
    }

    // A2a

    @Test func aSetUpMacThatMustActivateSendsTheStepWithNoSeconds() {
        var s = afterSetup()
        s.activated = false  // CLA-156: the gate is always on
        #expect(events(&s, .launch, now: 100) == [.setupStep(.activate, seconds: nil, service: .spotify)])
        #expect(BetaEvent.setupStep(.activate, seconds: nil, service: .spotify).properties == ["step": .text("activate"), "service": .text("spotify")])
    }

    @Test func controlLostOnceThenControlBackWithTheSeconds() {
        var s = mainMenu()
        #expect(events(&s, .controlBack, now: 100).isEmpty)  // nothing was lost
        #expect(events(&s, .controlLost(.otherDevice), now: 100) == [.controlLost(.otherDevice, service: .spotify)])
        #expect(events(&s, .controlLost(.timeout), now: 101).isEmpty)  // one loss until control comes back
        #expect(events(&s, .controlBack, now: 112) == [.controlBack(seconds: 12, service: .spotify)])
        #expect(events(&s, .controlBack, now: 113).isEmpty && s.controlLostAt == nil)
        #expect(BetaEvent.controlLost(.stoppedInSpotify, service: .appleMusic).properties
            == ["reason": .text("stopped_in_spotify"), "service": .text("apple_music")])
    }

    @Test func aBetaNoticeSaysWhenItShowsAndWhenItsButtonIsPressed() {
        let beta = BetaBuild(signed: 1000, number: 7)
        var s = mainMenu()
        #expect(events(&s, .betaBuild(beta), now: beta.warnsAt + 1).contains(.betaRenewal(.warning, pressed: false, daysLeft: 3)))
        #expect(events(&s, .select, now: beta.warnsAt + 1) == [.betaRenewal(.warning, pressed: true, daysLeft: 3)])
        var ended = mainMenu()
        #expect(events(&ended, .betaBuild(beta), now: beta.endsAt + 1).contains(.betaRenewal(.end, pressed: false, daysLeft: 0)))
        #expect(BetaEvent.betaRenewal(.update, pressed: true, daysLeft: 2).properties
            == ["notice": .text("update"), "pressed": .flag(true), "days_left": .number(2)])
    }

    @Test func aNewBuildSendsAppUpdatedOnceAtItsFirstStart() {
        var s = mainMenu()
        #expect(events(&s, .betaBuild(BetaBuild(signed: 0, number: 350)), now: 10).isEmpty && s.lastBuild == 350)  // the first build: no update
        var next = mainMenu()
        next.lastBuild = 350
        let fresh = BetaBuild(signed: 1000, number: 352)
        #expect(events(&next, .betaBuild(fresh), now: 1000 + 2.5 * BetaBuild.day) == [.appUpdated(from: 350, to: 352, days: 2)])
        #expect(next.lastBuild == 352 && next.settings.lastBuild == 352)
        var again = next
        again.beta = nil
        #expect(events(&again, .betaBuild(fresh), now: 1000 + 3 * BetaBuild.day).isEmpty)  // the same build
        var adHoc = mainMenu()
        adHoc.lastBuild = 350
        #expect(events(&adHoc, .betaBuild(nil), now: 10).isEmpty && adHoc.lastBuild == 350)
        #expect(BetaEvent.appUpdated(from: 350, to: 352, days: 2).properties
            == ["old_build": .number(350), "new_build": .number(352), "days": .number(2)])
        let store = FakeSettings()
        var saved = Settings()
        saved.lastBuild = 352
        saved.save(to: store)
        #expect(store.values["analytics.lastBuild"] == "352" && Settings(from: store).lastBuild == 352)
    }
}
