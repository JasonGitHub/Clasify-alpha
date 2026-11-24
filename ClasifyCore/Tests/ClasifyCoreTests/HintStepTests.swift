import Testing
@testable import ClasifyCore

/// CLA-181: `hint_step`, the first-run hints in analytics. `start` once, then one event as each
/// tour step ends: `done` by the person's action, `unused` after `tourHideMax` hides.
@Suite struct HintStepTests {
    func hints(_ fx: [Effect]) -> [BetaEvent] {
        fx.compactMap { if case .track(let e) = $0, case .hintStep = e { e } else { nil } }
    }

    /// On the main menu right after the first setup, with the tour on and analytics on.
    func started() -> AppState {
        var s = TourTests().allSet()
        s.analyticsOn = true
        #expect(hints(send(&s, .select, now: 111)) == [.hintStep(.start, how: nil, service: .spotify)])
        #expect(s.tourOn && s.hintStartSent)
        return s
    }

    @Test func startThenPlayNextAndMenuDoneOnceEach() {
        var s = started()
        #expect(hints(send(&s, .play, now: 112)) == [.hintStep(.play, how: .done, service: .spotify)])
        #expect(hints(send(&s, .play, now: 113)).isEmpty)  // never twice
        #expect(hints(send(&s, .next, now: 114)) == [.hintStep(.next, how: .done, service: .spotify)])
        #expect(hints(send(&s, .next, now: 115)).isEmpty)
        s.stack.append(Frame(screen: .settings))
        #expect(hints(send(&s, .menu, now: 116)) == [.hintStep(.menu, how: .done, service: .spotify)])
        s.stack.append(Frame(screen: .settings))
        #expect(hints(send(&s, .menu, now: 117)).isEmpty)
    }

    @Test func aStepHiddenTheMostTimesIsUnused() {
        var s = started()
        s.hint = .tourPlay; s.hintTip = true; s.tourHides[.tourPlay] = AppState.tourHideMax - 1
        #expect(hints(send(&s, .wheel(1), now: 112)) == [.hintStep(.play, how: .unused, service: .spotify)])
        #expect(s.hintsDone.contains(.tourPlay))
        #expect(hints(send(&s, .play, now: 113)).isEmpty)
    }

    @Test func turnAndMenuBarOnlyAsTourSteps() {
        var s = started()
        s.hintsDone.formUnion([.tourPlay, .tourNext, .tourMenu])
        #expect(hints(send(&s, .deviceTurned(true), now: 112)).isEmpty)  // no trial: not a tour step
        #expect(hints(send(&s, .menuBarClick(shown: true), now: 113)).isEmpty)
        var trial = started()
        trial.hintsTrial = true; trial.menuBar = true
        trial.hintsDone.formUnion([.tourPlay, .tourNext, .tourMenu])
        #expect(hints(send(&trial, .deviceTurned(true), now: 112)) == [.hintStep(.turn, how: .done, service: .spotify)])
        #expect(hints(send(&trial, .menuBarClick(shown: true), now: 113)) == [.hintStep(.menuBar, how: .done, service: .spotify)])
        #expect(hints(send(&trial, .menuBarClick(shown: true), now: 114)).isEmpty)
        #expect(BetaEvent.hintStep(.menuBar, how: .unused, service: .appleMusic).properties
            == ["step": .text("menu_bar"), "how": .text("unused"), "service": .text("apple_music")])
        #expect(BetaEvent.hintStep(.start, how: nil, service: .spotify).properties == ["step": .text("start"), "service": .text("spotify")])
        #expect(BetaEvent.hintStep(.start, how: nil, service: .spotify).name == "hint_step")
    }

    /// A later start for the trial's steps sends `start` only if none went out before.
    @Test func startGoesOutOnceEver() {
        for sent in [false, true] {
            var s = mainMenu()
            s.analyticsOn = true; s.hintsTrial = true; s.hintStartSent = sent
            s.hintsDone.remove(.tourTurn)
            let fx = hints(send(&s, .tick, now: 200))
            #expect(s.tourOn)
            #expect(fx == (sent ? [] : [.hintStep(.start, how: nil, service: .spotify)]))
        }
        var off = TourTests().allSet()  // analytics off: nothing, and the start is not marked
        send(&off, .select, now: 111)
        #expect(off.tourOn && !off.hintStartSent)
    }

    @Test func theStartFlagIsSaved() {
        let store = FakeSettings()
        var settings = Settings()
        settings.hintStartSent = true
        settings.save(to: store)
        #expect(store.values["analytics.hintStart"] == "true" && Settings(from: store).hintStartSent)
        var s = AppState()
        s.settings = settings
        #expect(s.hintStartSent)
    }
}
