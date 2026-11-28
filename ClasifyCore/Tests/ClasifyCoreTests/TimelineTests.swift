import Foundation
import Testing
@testable import ClasifyCore

/// CLA-203: the problem timeline, the last 2 minutes in memory, with no names or IDs.
@Suite struct TimelineTests {
    @Test func theTextIsNewestLastWithSecondsAgo() {
        let t = Timeline()
        t.record("play", at: 100)
        t.record("song", at: 100.8)
        t.record(EngineNote.deviceGone.text, at: 175.9)
        #expect(t.text(at: 175.9) == "play@-75.9 song@-75.1 dev_gone@-0.0")
        #expect(Timeline().text(at: 0) == "")
    }

    @Test func wheelStepsWithinOneSecondMerge() {
        let t = Timeline()
        t.record("wheel", at: 10)
        t.record("wheel", at: 10.5)
        t.record("wheel", at: 11.4)  // 0.9 s after the last step
        t.record("wheel", at: 13)  // more than 1 s: a new entry
        t.record("select", at: 13.2)
        t.record("wheel", at: 13.5)  // after another entry: a new one
        #expect(t.text(at: 14) == "wheel:3@-2.6 wheel:1@-1.0 select@-0.8 wheel:1@-0.5")
    }

    /// Codex on #527: a burst longer than 2 minutes keeps its entry, at the time of its last step.
    @Test func aLongWheelBurstStays() {
        let t = Timeline()
        for i in 0...242 { t.record("wheel", at: Double(i) * 0.5) }
        #expect(t.text(at: 121.5) == "wheel:243@-0.5")
    }

    @Test func entriesOlderThanTwoMinutesGoAndAtMost60Stay() {
        let t = Timeline()
        t.record("play", at: 0)
        t.record("menu", at: 50)
        #expect(t.text(at: 120) == "play@-120.0 menu@-70.0")
        #expect(t.text(at: 120.1) == "menu@-70.1")
        for i in 0..<70 { t.record("select", at: 200 + Double(i)) }
        #expect(t.entries.count == Timeline.limit && t.entries.first?.at == 210)
    }

    @Test func eachNoteHasAShortTextWithNoNames() {
        let notes: [EngineNote] = [
            .deviceHere, .deviceGone, .deviceOther, .appRunning, .appQuit, .dealerReconnect, .newLogin,
            .commandTimeout, .error(7), .musicKitError(-8102), .sleep, .wake, .pathChange,
        ]
        #expect(notes.map(\.text) == [
            "dev_here", "dev_gone", "dev_other", "app_run", "app_quit", "dealer", "login", "timeout",
            "err:7", "mk_err:-8102", "sleep", "wake", "path",
        ])
    }

    /// Each state copy in a debug test frame is large (reducer stack limit): the states are
    /// made one at a time in these helpers, and the test keeps only the text.
    @inline(never) static func changed(_ s: AppState, playing: Bool) -> AppState {
        var s = s
        s.current = TrackRef(playlist: "p1", track: "t1")
        s.isPlaying = playing
        return s
    }

    @inline(never) func recordedText() -> String {
        let t = Timeline()
        let start = mainMenu()
        let played = Self.changed(start, playing: true)
        t.record(.play, from: start, to: played, at: 10)
        let paused = Self.changed(played, playing: false)
        t.record(.controlLost(.stoppedInSpotify), from: played, to: paused, at: 12)
        t.record(.tick, from: paused, to: paused, at: 13)  // nothing changed: no entry
        t.record(.note(.wake), from: paused, to: paused, at: 14)
        return t.text(at: 14)
    }

    @Test func theActionsAndThePlayerFactsAreRecorded() {
        let text = recordedText()
        #expect(text == "play@-4.0 song@-4.0 playing@-4.0 lost:stopped_in_spotify@-2.0 paused@-2.0 wake@-0.0")
        #expect(!text.contains("p1") && !text.contains("t1"))
    }

    /// Codex on #529: `back` only when a loss was open; a normal load sends `.controlBack` too.
    @MainActor @Test func backIsRecordedOnlyAfterALoss() {
        let store = Store(player: FakePlayer(), library: FakeLibrary(), state: mainMenu(), env: Dependencies(now: { 50 }, random: { _ in 0 }))
        store.send(.controlBack)
        #expect(!store.timeline.text(at: 50).contains("back"))
        store.send(.controlLost(.stoppedInSpotify))
        store.send(.controlBack)
        #expect(store.timeline.text(at: 50).hasSuffix("back@-0.0"))
    }

    /// The Store records each action; `.note` changes no state and has no effect.
    @MainActor @Test func theStoreRecordsAndANoteChangesNothing() {
        let store = Store(player: FakePlayer(), library: FakeLibrary(), state: mainMenu(), env: Dependencies(now: { 50 }, random: { _ in 0 }))
        store.send(.note(.pathChange))
        store.send(.menu)
        #expect(store.timeline.text(at: 50).hasPrefix("path@-0.0 menu@-0.0"))
        var s = mainMenu()
        let fx = reduce(&s, .note(.sleep), Dependencies(now: { 50 }, random: { _ in 0 }))
        #expect(fx.isEmpty && s == mainMenu())
    }
}
