import Testing
@testable import ClasifyCore

/// CLA-186: `first_step`, each step once per install, after setup.
@Suite struct FirstStepTests {
    func events(_ s: inout AppState, _ actions: Action..., now: Double = 100) -> [BetaEvent] {
        events(&s, actions, now: now)
    }

    func events(_ s: inout AppState, _ actions: [Action], now: Double = 100) -> [BetaEvent] {
        let e = Dependencies(now: { now }, random: { _ in 0 })
        return actions.flatMap { reduce(&s, $0, e) }.compactMap { (fx: Effect) -> BetaEvent? in
            if case .track(.firstStep(let step, let how, let seconds, let service)) = fx {
                return .firstStep(step, how: how, seconds: seconds, service: service)
            }
            return nil
        }
    }

    /// The main menu of a later launch at 90, with the sender on.
    func ready() -> AppState {
        var s = mainMenu()
        s.analyticsOn = true
        _ = events(&s, .launch, now: 90)
        return s
    }

    /// Focus is open and its song 0 was pressed at 100: it waits for music.
    func pressed() -> AppState {
        var s = ready()
        _ = events(&s, openFocus(1) + [.select])
        return s
    }

    @Test func theFirstOpenOfAListAndTheFirstPressOfPlayGoOutOnce() {
        var s = ready()
        #expect(events(&s, .wheel(1), .select, .playlistsLoaded(token: 1, playlists: [focusInfo])).isEmpty)  // Playlists: not songs
        #expect(events(&s, .select, now: 100) == [.firstStep(.listOpened, how: nil, seconds: 10, service: .spotify)])
        #expect(events(&s, .tracksLoaded(token: 2, playlist: "focus", tracks: focus.tracks), .wheel(1)).isEmpty)
        #expect(events(&s, .select, now: 101) == [.firstStep(.playPressed, how: nil, seconds: 11, service: .spotify)])
        #expect(s.firstStepsSent == [.listOpened, .playPressed])
        _ = events(&s, .menu, .menu)
        #expect(events(&s, .select, .select).isEmpty)  // Focus again, another song: once per install
        #expect(BetaEvent.firstStep(.playNoMusic, how: .silent, seconds: 3, service: .appleMusic).properties
            == ["step": .text("play_no_music"), "how": .text("silent"), "seconds": .number(3), "service": .text("apple_music")])
        #expect(BetaEvent.firstStep(.listOpened, how: nil, seconds: 3, service: .local).name == "first_step")
    }

    /// The setup's launch counts from `all_set`; nothing goes out in setup.
    @Test func secondsCountFromAllSetInTheSetupsLaunch() {
        var s = ready()
        s.firstStepsBox.value.allSetAt = 95
        #expect(events(&s, openFocus(1), now: 100) == [.firstStep(.listOpened, how: nil, seconds: 5, service: .spotify)])
        var setup = activatedMac()
        setup.analyticsOn = true
        _ = events(&setup, .launch, .select, now: 10)
        #expect(setup.firstStepsSent.isEmpty && setup.firstStepsBox.value.allSetAt == nil && setup.firstStepsBox.value.launchAt == 10)
    }

    @Test func musicInTimeEndsTheWait() {
        var s = pressed()
        #expect(s.firstStepDue(at: 120) && !s.firstStepDue(at: 119.9))
        #expect(events(&s, .position(1, generation: s.playGen), now: 105).isEmpty)
        #expect(!s.firstStepDue(at: 200))
        _ = events(&s, .menu, .wheel(1))
        #expect(events(&s, .select, now: 130).isEmpty && !s.firstStepDue(at: 200))  // music was heard: no more waits
    }

    @Test func aFailedLoadSendsFailed() {
        var s = pressed()
        #expect(events(&s, .loadFailed("That didn’t play", generation: s.playGen), now: 103)
            == [.firstStep(.playNoMusic, how: .failed, seconds: 13, service: .spotify)])
        #expect(!s.firstStepDue(at: 200))
        _ = events(&s, .menu, .wheel(1), .select)
        #expect(events(&s, .loadFailed("Again", generation: s.playGen), .tick, now: 200).isEmpty)  // once per install
    }

    @Test func noMusicIn20SecondsSendsSilent() {
        var s = pressed()
        #expect(events(&s, .tick, now: 119).isEmpty)
        #expect(events(&s, .tick, now: 120) == [.firstStep(.playNoMusic, how: .silent, seconds: 30, service: .spotify)])
        #expect(!s.firstStepDue(at: 300))
        // A new pick waits again from its own press.
        var again = pressed()
        _ = events(&again, .menu, .wheel(1), .select, now: 110)
        #expect(events(&again, .tick, now: 120).isEmpty && again.firstStepDue(at: 130))
    }

    @Test func aPauseOrAServiceSwitchCancelsTheWait() {
        var s = pressed()
        _ = events(&s, .play, now: 105)  // Pause
        #expect(!s.firstStepDue(at: 200) && events(&s, .tick, now: 200).isEmpty)
        var other = pressed()
        for _ in 0..<8 where other.top.screen != .main { _ = events(&other, .menu) }
        other.top.sel = other.rows(for: other.top).firstIndex(of: .settings) ?? -1
        _ = events(&other, .select, .select, .menu)  // Service: Apple Music
        #expect(other.service == .appleMusic && !other.firstStepDue(at: 200))
    }

    @Test func withTheSenderOffNothingGoesOutOrWaits() {
        var s = mainMenu()
        #expect(events(&s, openFocus(1) + [.select]).isEmpty)
        #expect(s.firstStepsSent.isEmpty && !s.firstStepDue(at: 200))
    }

    @Test func theSentStepsAreSaved() {
        let store = FakeSettings()
        var s = AppState()
        s.firstStepsSent = [.playPressed, .listOpened]
        s.settings.save(to: store)
        #expect(store.values["analytics.firstSteps"] == "list_opened,play_pressed")
        #expect(Settings(from: store).firstSteps == [.listOpened, .playPressed])
        store.values["analytics.firstSteps"] = "play_no_music,later_step"
        #expect(Settings(from: store).firstSteps == [.playNoMusic])  // an unknown step is dropped
    }
}
