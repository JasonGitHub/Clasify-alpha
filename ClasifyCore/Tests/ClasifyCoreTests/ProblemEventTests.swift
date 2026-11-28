import Foundation
import Synchronization
import Testing
@testable import ClasifyCore

/// CLA-203: problem events carry the 2 minutes before them, and `problem_after` the 2 minutes
/// after. A cut song is its own event.
@MainActor @Suite struct ProblemEventTests {
    final class Clock: Sendable {
        let now = Mutex(1_000.0)
        func set(_ t: Double) { now.withLock { $0 = t } }
    }

    @MainActor final class Sent { var events: [BetaEvent] = [] }

    let clock = Clock()
    let sent = Sent()

    func store(_ state: AppState = mainMenu()) -> Store {
        let clock = self.clock
        let store = Store(player: FakePlayer(), library: FakeLibrary(), state: state,
                          env: Dependencies(now: { clock.now.withLock { $0 } }, random: { _ in 0 }))
        let sent = self.sent
        store.onBetaEvent = { event in sent.events.append(event) }
        return store
    }

    var events: [BetaEvent] { sent.events }

    func playingState() -> AppState {
        var s = mainMenu()
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "l0"); s.isPlaying = true; s.t = 75.6
        return s
    }

    @Test func aLossCarriesTheTimelineThePlaceThePlayAndTheScreen() {
        let store = store(playingState())
        store.send(.menu)
        clock.set(1_010)
        store.send(.controlLost(.stoppedInSpotify))
        guard case .problem(let inner, let context)? = events.first(where: { $0.name == "control_lost" }) else {
            Issue.record("no control_lost with a timeline"); return
        }
        #expect(inner == .controlLost(.stoppedInSpotify, service: .spotify))
        let screen = mainMenu().top.screen.eventName
        #expect(context.timeline == "menu@-10.0 lost:stopped_in_spotify@-0.0")
        #expect(context.pos == 75 && context.playing && context.screen == screen)
        let p = events.first { $0.name == "control_lost" }!.properties
        #expect(p["reason"] == .text("stopped_in_spotify") && p["pos_s"] == .number(75) && p["playing"] == .flag(true))
        #expect(p["timeline"] == .text(context.timeline) && p["screen"] == .text(screen))
    }

    /// CTO: a pause made on another device (the engine reports it, no myPod press) is in the
    /// timeline, and `state_s` says how long the pause held, past the 2 minutes.
    @Test func aPauseFromAnotherDeviceIsRecordedAndStateSecondsHasNoLimit() {
        let store = store(playingState())
        store.send(.menu)  // the first fact of the launch
        clock.set(1_010)
        store.send(.trackChanged("l0", playing: false, generation: store.state.playGen))  // paused on the phone
        #expect(store.timeline.text(at: 1_010).hasSuffix("paused@-0.0"))
        clock.set(1_010 + 1_800)  // 30 minutes later
        store.send(.controlLost(.stoppedInSpotify))
        guard case .problem(_, let context)? = events.first(where: { $0.name == "control_lost" }) else {
            Issue.record("no control_lost with a timeline"); return
        }
        #expect(context.stateSeconds == 1_800 && !context.playing)
        #expect(!context.timeline.contains("paused"))  // older than 2 minutes: only state_s tells
        #expect(events.first { $0.name == "control_lost" }?.properties["state_s"] == .number(1_800))
    }

    /// The action that is the problem does not reset its own `state_s`.
    @Test func stateSecondsIsTheStateBeforeTheProblem() {
        let store = store(playingState())
        store.send(.menu)
        clock.set(1_200)
        store.send(.controlLost(.stoppedInSpotify))
        guard case .problem(_, let context)? = events.first(where: { $0.name == "control_lost" }) else {
            Issue.record("no control_lost with a timeline"); return
        }
        #expect(context.stateSeconds == 200 && context.playing)
    }

    @Test func otherEventsGoOutAsBefore() {
        let store = store()
        store.send(.willQuit(openSeconds: 60))
        #expect(events.contains { $0.name == "app_closed" } && !events.contains { if case .problem = $0 { true } else { false } })
    }

    @Test func problemAfterComesTwoMinutesLaterWithBackAndPlaying() {
        let store = store(playingState())
        store.send(.controlLost(.stoppedInSpotify))
        clock.set(1_006.5)
        store.send(.controlBack)
        clock.set(1_119)
        store.send(.tick)
        #expect(!events.contains { $0.name == "problem_after" })
        clock.set(1_120)
        store.send(.tick)
        guard case .problemAfter(let problem, let timeline, let quit, let back, _, _)? = events.last else {
            Issue.record("no problem_after"); return
        }
        #expect(problem == "control_lost:stopped_in_spotify" && !quit && back)
        #expect(timeline.hasPrefix("lost:stopped_in_spotify@+0.0") && timeline.contains("back@+6.5"))
        #expect(events.last?.properties["playing"] != nil)
        store.send(.tick)
        #expect(events.filter { $0.name == "problem_after" }.count == 1)
    }

    /// Codex on #529: a late follow-up (the Mac slept) still has the 2 minutes after the problem,
    /// and the entries after those 2 minutes are not in it.
    @Test func aLateProblemAfterKeepsItsTwoMinutes() {
        let store = store(playingState())
        store.send(.controlLost(.stoppedInSpotify))
        clock.set(1_006.5)
        store.send(.controlBack)
        clock.set(1_000 + 1_800)  // 30 minutes later
        store.send(.menu)
        guard case .problemAfter(_, let timeline, _, let back, _, _)? = events.last else {
            Issue.record("no problem_after"); return
        }
        #expect(timeline == "lost:stopped_in_spotify@+0.0 back@+6.5" && back)
        #expect(store.timeline.text(at: 2_800) == "menu@-0.0")
    }

    /// Codex on #529: a `.controlBack` with no loss open (a normal load) is not a recovery.
    @Test func backIsOnlyARealReturnOfControl() {
        let store = store(playingState())
        store.track(.songCut(pos: 2, len: 200, service: .spotify), before: store.state, at: 1_000)
        store.send(.controlBack)
        clock.set(1_120)
        store.send(.tick)
        #expect(events.last?.name == "problem_after" && events.last?.properties["back"] == .flag(false))
    }

    @Test func aQuitSendsProblemAfterAtOnce() {
        let store = store(playingState())
        store.send(.controlLost(.stoppedInSpotify))
        clock.set(1_030)
        store.send(.willQuit(openSeconds: 60))
        guard let after = events.first(where: { $0.name == "problem_after" }) else { Issue.record("no problem_after"); return }
        #expect(after.properties["quit"] == .flag(true) && after.properties["back"] == .flag(false))
        #expect(after.properties["timeline"] == .text("lost:stopped_in_spotify@+0.0 quit@+30.0"))
    }

    /// Codex on #529: a problem made while myPod quits gets its `problem_after` at once.
    @Test func aProblemAtTheQuitGetsProblemAfterAtOnce() {
        var s = playingState()
        s.quitting = true  // as after `.willQuit`, where a first Play's silent deadline can end
        let store = store(s)
        store.track(.firstStep(.playNoMusic, how: .failed, seconds: 3, service: .spotify), before: store.state, at: 1_000)
        guard let after = events.first(where: { $0.name == "problem_after" }) else { Issue.record("no problem_after"); return }
        #expect(after.properties["quit"] == .flag(true) && after.properties["problem"] == .text("first_step:play_no_music"))
    }

    /// At most 10 events with a timeline in a launch, `problem_after` included. Over it, the
    /// problem still goes out, with no timeline.
    @Test func atMostTenTimelinesALaunch() {
        let store = store()
        for i in 0..<12 {
            clock.set(1_000 + Double(i) * 200)
            store.send(.controlLost(.stoppedInSpotify))
            store.send(.controlBack)
        }
        let withTimeline = events.filter { if case .problem = $0 { true } else { $0.name == "problem_after" } }
        #expect(withTimeline.count == Store.timelineCap)
        #expect(events.filter { $0.name == "control_lost" }.count == 12)
    }

    @Test func eachEventKindThatIsAProblem() {
        #expect(BetaEvent.controlLost(.otherDevice, service: .spotify).isProblem)
        #expect(BetaEvent.useError(.songNotPlayed, offline: false, service: .spotify).isProblem)
        #expect(BetaEvent.useError(.listNotLoaded, offline: false, service: .spotify).isProblem)
        #expect(!BetaEvent.useError(.loginFailed, offline: false, service: .spotify).isProblem)
        #expect(BetaEvent.firstStep(.playNoMusic, how: .failed, seconds: 3, service: .spotify).isProblem)
        #expect(!BetaEvent.controlBack(seconds: 3, service: .spotify).isProblem)
        #expect(BetaEvent.songCut(pos: 2, len: nil, service: .spotify).isProblem)
    }
}

/// CLA-203: `song_cut`, the song that `songs_cut` counts, as its own event.
extension DayActiveTests {
    @Test func aCutSongIsItsOwnEventWithItsPlaceAndLength() {
        var s = started()
        let sent = events(&s, .trackChanged("l1", playing: true, generation: s.playGen), now: at(10) + 2)
        guard let cut = sent.first(where: { $0.name == "song_cut" }) else { Issue.record("no song_cut"); return }
        #expect(cut.properties["pos_s"] == .number(2) && cut.properties["service"] == .text(s.service.eventName))
        let long = started(upTo: 4.5)
        var l = long
        #expect(!events(&l, .trackChanged("l1", playing: true, generation: l.playGen), now: at(10) + 5).contains { $0.name == "song_cut" })
    }
}

/// At most 3 `song_cut` a launch.
@MainActor @Test func atMostThreeCutSongsALaunch() {
    let store = Store(player: FakePlayer(), library: FakeLibrary(), state: mainMenu(), env: Dependencies(now: { 1 }, random: { _ in 0 }))
    let sent = ProblemEventTests.Sent()
    store.onBetaEvent = { event in sent.events.append(event) }
    for _ in 0..<5 { store.track(.songCut(pos: 1, len: 200, service: .spotify), before: store.state, at: 1) }
    #expect(sent.events.filter { $0.name == "song_cut" }.count == Store.cutCap)
}
