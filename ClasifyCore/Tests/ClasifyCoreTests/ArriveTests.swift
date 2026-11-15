import Testing
@testable import ClasifyCore

/// Card BR, change 288: at the first launch ever, the device turns in before Hello.
@Suite struct ArriveTests {
    /// A first launch: Hello shows behind the turn, and the device has not arrived.
    func firstLaunch() -> AppState {
        var s = AppState()
        s.arrived = false
        send(&s, .launch, now: 10)
        return s
    }

    @Test func arrivedEndsTheTurnAndStartsHello() {
        var s = firstLaunch()
        #expect(s.top.screen == .hello && s.helloAt == 10)
        let fx = send(&s, .arrived, now: 12.35)
        #expect(s.arrived && s.helloAt == 12.35 && fx.isEmpty)  // Hello starts as the device lands
    }

    @Test func arrivedTwiceDoesNothing() {
        var s = firstLaunch()
        send(&s, .arrived, now: 12.35)
        let before = s
        let fx = send(&s, .arrived, now: 20)
        #expect(s == before && fx.isEmpty)
    }

    @Test func arrivedOffHelloKeepsTheScreen() {
        var s = mainMenu()
        s.arrived = false
        let at = s.helloAt
        send(&s, .arrived, now: 50)
        #expect(s.arrived && s.top.screen == .main && s.helloAt == at)
    }

    /// Input during the turn is ignored: the device is not in the hand yet.
    @Test func inputDuringTheTurnIsDropped() {
        var s = mainMenu()
        s.arrived = false
        let before = s
        for action: Action in [.wheel(1), .select, .menu, .play, .next, .prev, .toggleShuffle, .cycleRepeat] {
            let fx = send(&s, action)
            #expect(s == before && fx.isEmpty, "\(action)")
        }
        send(&s, .arrived)
        send(&s, .wheel(1))
        #expect(s.top.sel != before.top.sel)  // after the landing the wheel works
    }

    /// Dropped input does not count for the tour or the hints either (Codex on #245).
    @Test func inputDuringTheTurnSkipsNoTourStep() {
        var s = mainMenu()
        s.tourOn = true
        s.hintsDone = []
        s.arrived = false
        let before = s
        for action: Action in [.play, .next, .prev, .menu, .select, .wheel(1)] { send(&s, action) }
        #expect(s == before)
    }

    /// Other actions, such as a login result, still arrive during the turn.
    @Test func otherActionsGoOnDuringTheTurn() {
        var s = firstLaunch()
        send(&s, .restored(token: 1, ok: true))
        #expect(s.signedIn && !s.arrived)
    }

    @Test func aResetKeepsTheArrival() {
        var s = mainMenu()
        #expect(s.arrived)
        send(&s, .reset)
        #expect(s.arrived)
        s.arrived = false
        send(&s, .reset)
        #expect(!s.arrived)  // a reset does not end a turn either
    }
}
