import Testing
@testable import ClasifyCore

/// Card BV (CLA-125): at launch a beta reads the newest beta's build number once. A newer
/// build shows one notice (312), not on a launch with the day-27 warning or the end (313), and
/// nothing when there is no good answer (314).
@Suite struct NewBetaTests {
    let beta = BetaBuild(signed: 1000, number: 286)

    /// Signed in on the main menu, as a launch leaves it: no key pressed yet.
    func launched(_ s: AppState = mainMenu()) -> AppState {
        var s = s
        s.touched = false
        return s
    }

    /// The next launch, with the saved settings: the main menu, signed in, no key pressed yet.
    func nextLaunch(_ old: AppState) -> AppState {
        var s = launched()
        s.settings = old.settings
        return s
    }

    @Test func aBetaChecksOnceAndAnAdHocBuildNever() {
        var s = launched()
        #expect(send(&s, .betaBuild(beta)) == [.checkLatestBeta])
        #expect(send(&s, .betaBuild(beta)).isEmpty)  // once a launch
        var adHoc = launched()
        #expect(send(&adHoc, .betaBuild(nil)).isEmpty)
        send(&adHoc, .latestBeta(290))
        #expect(adHoc.top.screen == .main)
    }

    /// Change 312: a newer build shows the notice over the main menu. "Get New Beta" opens the
    /// page and closes it; the notice does not show again for that build.
    @Test func aNewerBuildShowsTheNoticeOnce() {
        var s = launched()
        send(&s, .betaBuild(beta))
        #expect(send(&s, .latestBeta(290)).contains(.showWindow))  // card AN.1, 348: a hidden myPod shows
        #expect(s.top.screen == .betaNew && s.stack.count == 2 && s.newBeta == 290 && s.betaNoticed == 290)
        #expect(s.rows(for: s.top) == [.getNewBeta, .later] && s.betaDue == beta.endsAt)  // the warning waits for the main screens
        #expect(send(&s, .select) == [.getNewBeta])
        #expect(s.top.screen == .main)
        var next = nextLaunch(s)
        send(&next, .betaBuild(beta), .latestBeta(290))
        #expect(next.top.screen == .main && next.newBeta == 290)
        send(&next, .latestBeta(291))  // a later build shows once more
        #expect(next.top.screen == .betaNew && next.betaNoticed == 291)
    }

    /// After the notice showed on this launch, a newer answer is only saved.
    @Test func aNewerAnswerAfterTheNoticeIsOnlySaved() {
        var s = launched()
        send(&s, .betaBuild(beta), .latestBeta(290))
        #expect(s.top.screen == .betaNew)
        send(&s, .menu, .latestBeta(291), .tick)
        #expect(s.top.screen == .main && s.newBeta == 291 && s.betaNoticed == 290)
        var next = nextLaunch(s)
        send(&next, .betaBuild(beta))  // no answer yet: the saved build shows at once
        #expect(next.top.screen == .betaNew && next.newBetaNow == 291 && next.betaNoticed == 291)
    }

    /// Change 312: "Later" and MENU close it. Music is never stopped or started.
    @Test func laterAndMenuCloseTheNoticeAndTheMusicGoesOn() {
        for close in [[Action.wheel(1), .select], [.menu]] {
            var s = launched(playing())
            #expect(send(&s, .betaBuild(beta), .latestBeta(290)) == [.checkLatestBeta, .showWindow])  // AN.1, 348: the notice shows myPod
            #expect(s.top.screen == .betaNew && s.isPlaying)
            var fx: [Effect] = []
            for action in close { fx += send(&s, action) }
            #expect(fx.isEmpty && s.top.screen == .now && s.isPlaying)
        }
    }

    /// Change 312: an answer after the first key or wheel turn shows nothing on this launch.
    /// It is saved, and the next launch shows it at once, with no answer from the check.
    @Test func aLateAnswerIsSavedAndShowsAtTheNextLaunch() {
        for key in [Action.wheel(1), .menu, .play] {
            var s = launched()
            send(&s, .betaBuild(beta), key, .latestBeta(290), .tick)
            #expect(s.top.screen != .betaNew && s.betaNoticed == nil && s.newBeta == 290)
            var next = nextLaunch(s)
            #expect(send(&next, .betaBuild(beta)) == [.checkLatestBeta, .showWindow])  // AN.1, 348: the notice shows myPod
            #expect(next.top.screen == .betaNew && next.betaNoticed == 290)
        }
    }

    /// A saved build that is not newer than this one (the user updated) shows nothing.
    @Test func aSavedBuildNotNewerShowsNothing() {
        var s = launched()
        s.newBeta = 290
        send(&s, .betaBuild(BetaBuild(signed: 1000, number: 290)), .tick)
        #expect(s.top.screen == .main && s.betaNoticed == nil)
    }

    /// Change 314: the same or an older build shows nothing.
    @Test func theSameOrAnOlderBuildShowsNothing() {
        for build in [286, 280] {
            var s = launched()
            send(&s, .betaBuild(beta), .latestBeta(build), .tick)
            #expect(s.top.screen == .main && s.betaNoticed == nil && s.betaDue == beta.warnsAt)
        }
    }

    /// The notice waits for the main screens: an answer during the stored login's restore
    /// shows when the login is back.
    @Test func theNoticeWaitsForTheLogin() {
        var s = afterSetup()
        send(&s, .betaBuild(beta), .launch, .latestBeta(290))
        #expect(s.top.screen == .main && !s.signedIn && s.betaNoticed == nil)
        send(&s, .restored(token: 1, ok: true))
        #expect(s.betaDue == 1)
        send(&s, .tick)
        #expect(s.top.screen == .betaNew && s.betaNoticed == 290)
    }

    /// "Never interrupt": an answer that came before the first key waits for the login; a key
    /// in the meantime stops it on this launch. It stays saved, and the next launch shows it.
    @Test func aKeyWhileTheNoticeWaitsStopsIt() {
        var s = afterSetup()
        send(&s, .betaBuild(beta), .launch, .latestBeta(290), .wheel(1), .restored(token: 1, ok: true), .tick)
        #expect(s.stack.first?.screen == .main && s.top.screen != .betaNew && s.betaNoticed == nil && s.newBeta == 290)
        #expect(s.betaDue != 1)
        var next = nextLaunch(s)
        send(&next, .betaBuild(beta))
        #expect(next.top.screen == .betaNew && next.betaNoticed == 290)
    }

    /// The number on the notice does not change while it shows; a newer answer is only saved.
    @Test func theNumberOnTheNoticeStays() {
        var s = launched()
        send(&s, .betaBuild(beta), .latestBeta(290), .latestBeta(291))
        #expect(s.top.screen == .betaNew && s.newBetaNow == 290 && s.newBeta == 291)
    }

    /// Change 313: on a launch where the day-27 warning shows, the notice does not.
    @Test func noNoticeOnALaunchWithTheWarning() {
        let day27 = beta.warnsAt + 1
        var s = launched()
        send(&s, .betaBuild(beta), now: day27)
        #expect(s.top.screen == .betaSoon)
        send(&s, .latestBeta(290), now: day27)
        s.stack.removeLast()  // Later, with no key: the notice still does not show
        send(&s, .tick, now: day27)
        #expect(s.top.screen == .main && s.betaNoticed == nil && s.newBeta == 290)
        var next = nextLaunch(s)  // the warning showed before: the next launch shows the notice
        send(&next, .betaBuild(beta), now: day27 + 60)
        #expect(next.top.screen == .betaNew && next.betaNoticed == 290)
    }

    /// Change 313: the ended beta shows only its end, also with a saved build.
    @Test func noNoticeOverTheEnd() {
        var s = launched()
        s.newBeta = 290
        #expect(send(&s, .betaBuild(beta), now: beta.endsAt + 1) == [.showWindow])  // no check: the end has Get New Beta; it shows myPod (AN.1, 348)
        send(&s, .latestBeta(291), .tick, now: beta.endsAt + 1)
        #expect(s.stack == [Frame(screen: .betaEnded)] && s.betaNoticed == nil && s.newBeta == 291)  // saved
    }

    @Test func theNoticedBuildIsSavedWithTheSettings() {
        let store = FakeSettings()
        var saved = Settings()
        #expect(Settings(from: store).betaNoticed == nil)
        saved.betaNoticed = 290
        saved.newBeta = 291
        saved.save(to: store)
        #expect(Settings(from: store).betaNoticed == 290 && Settings(from: store).newBeta == 291)
    }

    /// The store reads the feed off the main actor and sends a number back; no answer sends nothing.
    @MainActor @Test func theStoreAsksTheFeed() async {
        for (answer, screen) in [(Int?.some(290), Screen.betaNew), (nil, .main)] {
            let feed = FakeBetaFeed(answer: answer)
            let env = Dependencies(now: { 100 }, random: { _ in 0 })  // not past the beta's end
            let store = Store(player: FakePlayer(), library: FakeLibrary(), state: launched(), env: env, betaFeed: feed)
            store.send(.betaBuild(beta))
            var tries = 0
            while tries < 200, !(await feed.asked) || store.state.top.screen != screen {
                tries += 1
                try? await Task.sleep(for: .milliseconds(10))
            }
            #expect(await feed.asked && store.state.top.screen == screen)
        }
    }
}

actor FakeBetaFeed: BetaFeed {
    let answer: Int?
    var asked = false
    init(answer: Int?) { self.answer = answer }
    func latestBuild() async -> Int? { asked = true; return answer }
}
