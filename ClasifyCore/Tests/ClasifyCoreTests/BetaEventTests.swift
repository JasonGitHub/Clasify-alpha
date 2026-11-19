import Testing
@testable import ClasifyCore

/// CLA-97, A1: the setup events, the Pick Your Music detail and the first song.
@Suite struct BetaEventTests {
    /// The `.track` events of the actions, at `now`.
    func events(_ s: inout AppState, _ actions: Action..., now: Double) -> [BetaEvent] {
        let e = Dependencies(now: { now }, random: { _ in 0 })
        return actions.flatMap { reduce(&s, $0, e) }.compactMap { if case .track(let event) = $0 { event } else { nil } }
    }

    /// The first launch at 100, on the color pick at 110.
    func onColor(spotifyApp: Bool = true) -> AppState {
        var s = AppState()
        _ = events(&s, .spotifyAppFound(spotifyApp), .launch, now: 100)
        _ = events(&s, .restored(token: 1, ok: false), .select, now: 110)
        return s
    }

    @Test func setupSendsEachStepOnceWithTheSecondsSinceTheFirstLaunch() {
        var s = AppState()
        #expect(events(&s, .spotifyAppFound(true), .launch, now: 100) == [.setupStep(.hello, seconds: 0, service: .spotify)])
        #expect(s.firstLaunchAt == 100 && s.settings.firstLaunchAt == 100)
        #expect(events(&s, .restored(token: 1, ok: false), .select, now: 110) == [.setupStep(.color, seconds: 10, service: .spotify)])
        #expect(events(&s, .select, now: 115) == [.setupStep(.pickMusic, seconds: 15, service: .spotify)])
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
            s.activateOn = true
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
        #expect(events(&s, .position(1, generation: s.playGen), now: 100) == [.firstSong(seconds: 60, service: .spotify)])
        #expect(s.firstSongSent && s.settings.firstSongSent)
        #expect(events(&s, .position(2, generation: s.playGen), now: 101).isEmpty)
        var old = afterSetup()  // set up before CLA-97: no time, no event
        old.current = s.current; old.isPlaying = true
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
}
