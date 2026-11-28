import Foundation
import Synchronization
import Testing
@testable import ClasifyCore

/// CLA-203: problem events carry the 2 minutes before them and how long the play state held.
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

    /// At most 10 events with a timeline in a launch. Over it, the problem still goes out,
    /// with no timeline.
    @Test func atMostTenTimelinesALaunch() {
        let store = store()
        for i in 0..<12 {
            clock.set(1_000 + Double(i) * 200)
            store.send(.controlLost(.stoppedInSpotify))
            store.send(.controlBack)
        }
        let withTimeline = events.filter { if case .problem = $0 { true } else { false } }
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
    }
}
