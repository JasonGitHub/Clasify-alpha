import Testing
@testable import ClasifyCore

/// Card BI v2 (CLA-96): a beta warns once on day 27 and ends on day 30. Ad-hoc builds never end.
@Suite struct BetaTests {
    let beta = BetaBuild(signed: 1000)
    var day27: Double { beta.warnsAt + 1 }
    var day30: Double { beta.endsAt + 1 }

    @Test func aBetaWarnsOnDay27AndEndsOnDay30() {
        #expect(beta.warnsAt == 1000 + 27 * 86_400)
        #expect(beta.endsAt == 1000 + 30 * 86_400)
    }

    /// Change 233: one warning over the main screens, shown once. "Get New Beta" opens the
    /// page and closes it.
    @Test func theWarningShowsOnceAndGetNewBetaClosesIt() {
        var s = mainMenu()
        send(&s, .betaBuild(beta))
        #expect(s.top.screen == .main && s.betaDue == beta.warnsAt)
        send(&s, .tick, now: beta.warnsAt - 1)
        #expect(s.top.screen == .main)
        send(&s, .tick, now: day27)
        #expect(s.top.screen == .betaSoon && s.stack.count == 2)
        #expect(s.rows(for: s.top) == [.getNewBeta, .later])
        #expect(s.betaWarned == beta.signed && s.betaDue == beta.endsAt)
        #expect(send(&s, .select, now: day27).contains(.getNewBeta))
        #expect(s.top.screen == .main)
        send(&s, .tick, now: day27 + 60)  // shown once
        #expect(s.top.screen == .main)
    }

    /// Change 233: "Later" and MENU close the warning.
    @Test func laterAndMenuCloseTheWarning() {
        for close in [[Action.wheel(1), .select], [.menu]] {
            var s = mainMenu()
            send(&s, .betaBuild(beta), now: day27)
            #expect(s.top.screen == .betaSoon)
            var fx: [Effect] = []
            for action in close { fx += send(&s, action, now: day27) }
            #expect(!fx.contains(.getNewBeta) && s.top.screen == .main)
        }
    }

    /// The warning waits for the main screens: not during setup or at the login.
    @Test func theWarningWaitsForTheMainScreens() {
        var s = afterSetup()
        send(&s, .betaBuild(beta), .tick, now: day27)
        #expect(s.top.screen == .login && s.betaWarned == nil && s.betaDue == beta.endsAt)
        send(&s, .select, .authDone(token: 1, ok: true), .select, now: day27)
        #expect(s.top.screen == .main && s.betaDue == beta.warnsAt)
        send(&s, .tick, now: day27)
        #expect(s.top.screen == .betaSoon)
    }

    /// A new beta warns again: the warning is kept by the build's signing time.
    @Test func aNewBetaWarnsAgain() {
        var s = mainMenu()
        s.betaWarned = beta.signed
        send(&s, .betaBuild(beta), now: day27)
        #expect(s.top.screen == .main)
        let next = BetaBuild(signed: beta.signed + 20 * BetaBuild.day)
        send(&s, .betaBuild(next), now: next.warnsAt)
        #expect(s.top.screen == .betaSoon && s.betaWarned == next.signed)
    }

    /// Change 234: on day 30 the ended screen replaces everything and the song stops. Only the
    /// wheel and its rows work: no MENU, no playback.
    @Test func anEndedBetaStopsPlaybackAndTakesOnlyItsRows() {
        var s = playing()
        s.beta = beta
        #expect(send(&s, .tick, now: day30) == [.stop])
        #expect(s.stack == [Frame(screen: .betaEnded)] && s.current == nil && !s.isPlaying)
        #expect(s.rows(for: s.top) == [.getNewBeta, .quit] && s.betaDue == 0)
        for action in [Action.menu, .play, .next, .prev, .toggleShuffle, .launch, .spotifyAppFound(false), .expire] {
            #expect(send(&s, action, now: day30).isEmpty)
            #expect(s.stack == [Frame(screen: .betaEnded)])
        }
        #expect(send(&s, .select, now: day30) == [.getNewBeta])
        #expect(s.top.screen == .betaEnded)  // it stays
        #expect(send(&s, .wheel(1), .select, now: day30) == [.quit])
    }

    /// Change 234: a beta that has ended at launch shows the ended screen, with no login.
    @Test func aBetaEndedAtLaunchShowsOnlyTheEnd() {
        var s = afterSetup()
        #expect(send(&s, .betaBuild(beta), .launch, now: day30).isEmpty)
        #expect(s.stack == [Frame(screen: .betaEnded)] && s.betaWarned == nil)
    }

    /// An ad-hoc build is no beta: nothing is due, and it never ends.
    @Test func anAdHocBuildNeverEnds() {
        var s = mainMenu()
        send(&s, .betaBuild(nil), .tick, now: day30 + 365 * BetaBuild.day)
        #expect(s.beta == nil && s.betaDue == 0 && s.top.screen == .main)
    }

    /// A reset keeps the build: it is the app, not the account.
    @Test func aResetKeepsTheBeta() {
        var s = mainMenu()
        send(&s, .betaBuild(beta), .reset)
        #expect(s.beta == beta)
    }

    @Test func theWarningIsSavedWithTheSettings() {
        let store = FakeSettings()
        var saved = Settings()
        #expect(Settings(from: store).betaWarned == nil)
        saved.betaWarned = 1234.5
        saved.save(to: store)
        #expect(Settings(from: store).betaWarned == 1234.5)
    }
}
