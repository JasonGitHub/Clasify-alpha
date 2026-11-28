import Testing
@testable import ClasifyCore

/// CLA-202: `tickDue(at:)`, the timer rules that both shells' timer loops use.
@Suite struct TickDueTests {
    @Test func noTimerMeansNoTick() {
        #expect(!AppState().tickDue(at: 100))
    }

    /// The toast, overlay, scroll bar, cover and letter timers end only after their time.
    @Test func aScreenTimerIsDueAfterItsEnd() {
        let timers: [WritableKeyPath<AppState, Double>] = [\.toastUntil, \.overlayUntil, \.scrollUntil, \.artUntil, \.letterUntil]
        for timer in timers {
            var s = AppState()
            s[keyPath: timer] = 100
            #expect(!s.tickDue(at: 99))
            #expect(!s.tickDue(at: 100))
            #expect(s.tickDue(at: 100.25))
        }
    }

    /// The "You’re in" beat and the playlist names' hold end at their time.
    @Test func aBeatIsDueAtItsEnd() {
        let timers: [WritableKeyPath<AppState, Double>] = [\.beatUntil, \.namesHold]
        for timer in timers {
            var s = AppState()
            s[keyPath: timer] = 100
            #expect(!s.tickDue(at: 99.75))
            #expect(s.tickDue(at: 100))
        }
    }

    /// A song's read with no answer in 3 s.
    @Test func aLateReadIsDue() {
        var s = AppState()
        s.readsPending["song"] = 100
        #expect(!s.tickDue(at: 100 + readWait - 0.25))
        #expect(s.tickDue(at: 100 + readWait))
    }

    /// A play press that brought no music in 20 s.
    @Test func aSilentPlayIsDue() {
        var s = AppState()
        s.firstStepsBox.value.silentAt = 120
        #expect(!s.tickDue(at: 119))
        #expect(s.tickDue(at: 120))
    }
}
