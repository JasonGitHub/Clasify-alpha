import Testing
@testable import ClasifyCore

/// CLA-128 card BW: setup's Activate screens 319 to 327, behind the `activate.on` switch (off
/// by default). Order: Hello, Color, Pick Your Music, Log In, Activate, Your Music.
@Suite struct ActivationTests {
    let sam = Activation.waiting(email: "sam@example.com", mail: 1)

    /// The first launch on "You’re in", after the login; the switch as given.
    func loggedIn(switchOn: Bool) -> AppState {
        var s = AppState()
        s.activateOn = switchOn
        send(&s, .spotifyAppFound(true), .launch, .restored(token: 1, ok: false), .select)  // on the color pick
        send(&s, .select, .select, .select, .authDone(token: 2, ok: true))  // the color, Spotify, Log In
        return s
    }

    /// On 319 "Join the beta" at time 200.
    func join() -> AppState {
        var s = loggedIn(switchOn: true)
        send(&s, .tick, now: 101.5)
        return s
    }

    /// Card AN.1 (CLA-43, 348): Activate shows a hidden myPod when it opens.
    @Test func activateShowsTheWindow() {
        var s = loggedIn(switchOn: true)
        #expect(send(&s, .tick, now: 101.5).contains(.showWindow))
        #expect(s.top.screen == .activate)
    }

    /// On 321 "Check your mail": the page opened at 200 and the mail went out.
    func mailOut() -> AppState {
        var s = join()
        send(&s, .select, now: 200)
        send(&s, .checkActivation, .activation(sam, request: 2), now: 210)
        return s
    }

    @Test func theSwitchIsOffByDefaultAndSetupIsAsToday() {
        #expect(!AppState().activateOn && AppState().activation == .locked)
        var s = loggedIn(switchOn: false)
        send(&s, .tick, now: 101.5)
        #expect(s.top.screen == .yourMusic)
    }

    /// 319, 320, 321, 323, then Your Music after 1.5 s.
    @Test func activateComesBeforeYourMusic() {
        var s = join()
        #expect(s.stack == [Frame(screen: .activate)] && s.activateStep == .join && s.rows(for: s.top) == [.openActivate])
        #expect(send(&s, .select, now: 200) == [.openActivatePage(request: 1)])
        #expect(s.activateStep == .browserOpen && s.rows(for: s.top) == [.openActivateAgain, .cancelActivate])
        #expect(send(&s, .checkActivation, now: 210) == [.checkActivation(request: 2)])  // the app came back
        send(&s, .activation(.locked, request: 2), now: 211)  // no mail yet
        #expect(s.activateStep == .browserOpen)
        send(&s, .wheel(1), .checkActivation, .activation(sam, request: 3), now: 212)
        #expect(s.activateStep == .checkMail && s.top.sel == 0 && s.rows(for: s.top) == [.sendAgain, .useAnotherEmail])
        send(&s, .checkActivation, .activation(.active(), request: 4), now: 220)
        #expect(s.activateStep == .confirmed && s.rows(for: s.top).isEmpty)
        send(&s, .tick, now: 221.4)
        #expect(s.top.screen == .activate)
        let fx = send(&s, .tick, now: 221.5)
        #expect(s.top.screen == .yourMusic && fx.contains(.fetchTracks(token: s.top.token, playlist: Playlist.likedSongsID)))
    }

    @Test func aPressOnConfirmedGoesOnAtOnce() {
        var s = mailOut()
        send(&s, .checkActivation, .activation(.active(), request: 3), .select, now: 220)
        #expect(s.top.screen == .yourMusic && s.activatedAt == 0)
    }

    /// CLA-146: 3 s in minute 1, 10 s in minute 2, 15 s in minute 3, then no more.
    @Test func theScheduleSlowsDownAndStopsAt3Minutes() {
        let delays = [0.0, 59, 60, 119, 120, 179, 180, 900].map { activateCheckDelay(elapsed: $0) }
        #expect(delays == [3, 3, 10, 10, 15, 15, nil, nil])
        #expect(activateChecksFor == 180)
    }

    /// CLA-146: the timer asks at most 30 times (as the old 30 s for 15 minutes did), when
    /// every answer comes at once. Then 322 shows.
    @Test func theTimerAsksAtMost30Times() {
        var s = join()
        send(&s, .select, now: 200)
        var times: [Double] = []
        var t = 200.0
        while t <= 400 {
            if s.activateDue(at: t) {
                for case .checkActivation(let r) in send(&s, .tick, now: t) {
                    times.append(t - 200)
                    send(&s, .activation(sam, request: r), now: t)
                }
            }
            t += 0.25
        }
        #expect(times.count <= 30 && times.count == 29)
        #expect(Array(times.prefix(3)) == [3, 6, 9] && times.contains(60) && times.contains(70) && times.contains(135))
        #expect(times.last == 165 && s.activateStep == .stopped)
    }

    /// CLA-146: on 322 an app return asks but starts no timer; "Check again" starts the 3 minutes again.
    @Test func anAppReturnAsksAlsoAfterTheStop() {
        var s = mailOut()
        send(&s, .tick, now: 1100)
        #expect(s.activateStep == .stopped && s.rows(for: s.top) == [.checkMail, .sendAgain, .useAnotherEmail])
        #expect(send(&s, .checkActivation, now: 1200) == [.checkActivation(request: 3)])
        send(&s, .activation(sam, request: 3), now: 1201)
        #expect(s.activateStep == .stopped && s.activateStopAt == 0 && send(&s, .tick, now: 1300).isEmpty)
        #expect(send(&s, .select, now: 1400) == [.checkActivation(request: 4)])
        #expect(s.activateStep == .checkMail && s.activateStopAt == 1400 + activateChecksFor && s.activateCheckAt == 1403)
        send(&s, .activation(sam, request: 4), now: 1401)
        send(&s, .checkActivation, .activation(.active(), request: 5), now: 1500)  // the app came back
        #expect(s.activateStep == .confirmed)
    }

    /// CLA-146: one check at a time. A due check waits for the answer, or 12 s; a press
    /// takes the answer on its way as its own; "Send again" always goes.
    @Test func oneCheckAtATime() {
        var s = mailOut()  // the next check is due at 213
        #expect(send(&s, .tick, now: 213) == [.checkActivation(request: 3)])
        #expect(!s.activateDue(at: 216) && send(&s, .tick, now: 216).isEmpty && send(&s, .checkActivation, now: 217).isEmpty)
        #expect(s.activateDue(at: 225) && send(&s, .tick, now: 225) == [.checkActivation(request: 4)])  // 3 was stuck
        send(&s, .activation(sam, request: 4), now: 226)
        #expect(send(&s, .tick, now: 229) == [.checkActivation(request: 5)])
        #expect(send(&s, .select, now: 230) == [.sendActivationAgain(request: 6)])  // "Send again" while 5 is on its way
        var pressed = mailOut()
        send(&pressed, .tick, now: 1100)  // 322
        send(&pressed, .checkActivation, now: 1200)  // request 3 is on its way
        #expect(send(&pressed, .select, now: 1201).isEmpty && pressed.activatePressed == 3)  // "Check again"
        send(&pressed, .activation(.offline, request: 3), now: 1202)
        #expect(pressed.activateStep == .offline)
    }

    /// "Send again" asks the server and starts the 15 minutes again; "Use another email"
    /// opens the page (320) until a newer mail is out.
    @Test func sendAgainAndUseAnotherEmail() {
        var s = mailOut()
        #expect(send(&s, .select, now: 500) == [.sendActivationAgain(request: 3)])
        #expect(s.activateStopAt == 500 + activateChecksFor && s.activatePressed == 3)
        send(&s, .activation(.waiting(email: "sam@example.com", mail: 2), request: 3), .wheel(1), now: 501)
        #expect(send(&s, .select, now: 502) == [.openActivatePage(request: 4)] && s.activateStep == .browserOpen)
        send(&s, .checkActivation, .activation(.waiting(email: "sam@example.com", mail: 2), request: 5), now: 510)
        #expect(s.activateStep == .browserOpen)  // the old mail
        send(&s, .checkActivation, .activation(.waiting(email: "kim@example.com", mail: 3), request: 6), now: 520)
        #expect(s.activateStep == .checkMail && s.activation == .waiting(email: "kim@example.com", mail: 3))
    }

    /// An answer on its way when MENU cancels is dropped; "Send again" on 322 shows 321 on its first row.
    @Test func cancelDropsTheAnswerAndSendAgainStartsOnTheFirstRow() {
        var s = mailOut()
        send(&s, .tick, now: 240)  // request 3 is out
        send(&s, .menu, .activation(sam, request: 3), now: 241)
        #expect(s.activateStep == .join)
        var stopped = mailOut()
        send(&stopped, .tick, .wheel(1), now: 2000)
        #expect(send(&stopped, .select, now: 2001) == [.sendActivationAgain(request: 3)])
        #expect(stopped.activateStep == .checkMail && stopped.top.sel == 0)
    }

    /// "Use another email" drops the answer to a "Send again" still on its way. The app's
    /// ticker sends `.tick` when a check, the end of the checks or the beat is due.
    @Test func useAnotherEmailDropsTheResendAndTheTickerKnowsTheDeadlines() {
        var s = mailOut()
        #expect(!s.activateDue(at: 212.9) && s.activateDue(at: 213))
        send(&s, .select, .wheel(1), .select, now: 300)  // "Send again", then "Use another email"
        send(&s, .activation(.waiting(email: "sam@example.com", mail: 2), request: 3), now: 301)
        #expect(s.activateStep == .browserOpen)
        send(&s, .checkActivation, .activation(.active(), request: 5), now: 310)
        #expect(!s.activateDue(at: 311.4) && s.activateDue(at: 311.5) && !join().activateDue(at: 1000))
    }

    /// MENU on 320 and 321 is "Cancel" (to 319). On 319 and 322 to 327 it does nothing.
    @Test func menuCancelsOnlyWhileTheChecksRun() {
        var open = join()
        send(&open, .select, now: 200)
        send(&open, .menu, now: 201)
        #expect(open.activateStep == .join && open.activateStopAt == 0)
        var out = mailOut()
        send(&out, .menu, now: 220)
        #expect(out.activateStep == .join && out.activation == .locked)
        var cancel = join()
        send(&cancel, .select, .wheel(1), .select, now: 200)  // "Cancel"
        #expect(cancel.activateStep == .join)
        for answer in [Activation.mailBusy, .full, .off, .offline] {
            var s = mailOut()
            send(&s, .select, .activation(answer, request: 3), .menu, now: 300)  // "Send again"
            #expect(s.activation == answer && s.top.screen == .activate)
        }
        var stopped = mailOut()
        send(&stopped, .tick, .menu, now: 2000)
        #expect(stopped.activateStep == .stopped)
        var first = join()
        send(&first, .menu, now: 200)
        #expect(first.activateStep == .join)
    }

    /// 324 and 327 have "Try again", 325 and 326 "Check again"; their checks stop.
    @Test func theOtherAnswersKeepTheScreen() {
        let rows: [(Activation, [Row])] = [(.mailBusy, [.tryActivateAgain]), (.full, [.checkMail]), (.off, [.checkMail]), (.offline, [.tryActivateAgain])]
        for (answer, row) in rows {
            var s = mailOut()
            send(&s, .select, .activation(answer, request: 3), now: 300)  // "Send again"
            #expect(s.top.screen == .activate && s.rows(for: s.top) == row && s.activateStopAt == 0)
            let fx = send(&s, .select, now: 400)
            #expect(fx == (answer == .mailBusy ? [.openActivatePage(request: 4)] : [.checkActivation(request: 4)]))
            if answer != .mailBusy {  // the checks run again: a mail still out shows 321
                send(&s, .activation(sam, request: 4), now: 401)
                #expect(s.activateStep == .checkMail)
            }
        }
    }

    /// An answer to an older request is dropped, and a timer check with no connection is
    /// not shown. The stored activation (no request number) always lands.
    @Test func anOlderAnswerAndAFailedTimerCheckAreDropped() {
        var s = mailOut()
        send(&s, .select, now: 300)  // request 3 is out
        send(&s, .activation(.active(), request: 2), now: 301)
        #expect(s.activateStep == .checkMail)
        send(&s, .tick, .activation(.offline, request: 4), now: 330)
        #expect(s.activateStep == .checkMail)
        var launch = AppState()
        send(&launch, .activation(.active(), request: nil))
        #expect(launch.activation == .active())
    }

    /// Already active (the stored activation, sent before the launch): no Activate step.
    @Test func anActiveMacSkipsTheStep() {
        var s = AppState()
        s.activateOn = true
        send(&s, .activation(.active(), request: nil))
        send(&s, .spotifyAppFound(true), .launch, .restored(token: 1, ok: false), .select)
        send(&s, .select, .select, .select, .authDone(token: 2, ok: true))
        send(&s, .tick, now: 101.5)
        #expect(s.top.screen == .yourMusic)
    }

    /// The switch is saved; the email never is.
    @Test func theSwitchIsSavedAndTheEmailIsNot() {
        let store = FakeSettings()
        #expect(!Settings(from: store).activateOn)
        var s = mailOut()
        s.activateOn = true
        s.settings.save(to: store)
        #expect(Settings(from: store).activateOn)
        #expect(!store.values.keys.contains { $0.contains("mail") } && !store.values.values.contains { $0.contains("@") })
    }

    /// The store asks the server and sends its answer back with the request number, and
    /// opens the page through the app.
    @MainActor @Test func theStoreAsksTheActivator() async {
        let env = Dependencies(now: { 200 }, random: { _ in 0 })
        let store = Store(player: FakePlayer(), library: FakeLibrary(), state: join(), env: env, activator: FakeActivator())
        let opened = Count()
        store.onOpenActivatePage = { url in opened.n += 1; opened.url = url }
        store.send(.select)
        store.send(.checkActivation)
        var tries = 0
        while tries < 200, store.state.activateStep != .checkMail {
            tries += 1
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(opened.n == 1 && opened.url == "https://getmypod.app/activate/?d=code")
        #expect(store.state.activation == .waiting(email: "sam@example.com", mail: 1))
        store.send(.select)  // "Send again"
        tries = 0
        while tries < 200, store.state.activation != .waiting(email: "sam@example.com", mail: 2) {
            tries += 1
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.state.activation == .waiting(email: "sam@example.com", mail: 2) && store.state.activateRequest == 3)
    }

    /// The server's answers map 1:1; anything else, a 4xx or a 5xx is 327 (offline).
    @Test func theServerAnswersMapToActivation() {
        #expect(Activation(status: 200, json: ["state": "locked"]) == .locked)
        #expect(Activation(status: 200, json: ["state": "waiting", "email": "sam@example.com", "mail": 2]) == .waiting(email: "sam@example.com", mail: 2))
        #expect(Activation(status: 200, json: ["state": "active", "account": "a1"]) == .active())
        #expect(Activation(status: 200, json: ["state": "full"]) == .full)
        #expect(Activation(status: 200, json: ["state": "off"]) == .off)
        #expect(Activation(status: 200, json: ["state": "busy"]) == .mailBusy)
        #expect(Activation(status: 200, json: ["state": "waiting"]) == .offline)  // no email or number
        #expect(Activation(status: 200, json: ["state": "new"]) == .offline)
        #expect(Activation(status: 200, json: nil) == .offline)
        #expect(Activation(status: 400, json: ["error": "email"]) == .offline)
        #expect(Activation(status: 401, json: ["state": "active"]) == .offline)
        #expect(Activation(status: 503, json: nil) == .offline)
    }

    /// A page that cannot get its code (no connection) shows 327 and opens nothing.
    @MainActor @Test func aPageWithNoCodeShowsOffline() async {
        let env = Dependencies(now: { 200 }, random: { _ in 0 })
        let store = Store(player: FakePlayer(), library: FakeLibrary(), state: join(), env: env, activator: FakeActivator(page: nil))
        let opened = Count()
        store.onOpenActivatePage = { _ in opened.n += 1 }
        store.send(.select)
        var tries = 0
        while tries < 200, store.state.activateStep != .offline {
            tries += 1
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.state.activateStep == .offline && opened.n == 0)
        #expect(store.state.rows(for: store.state.top) == [.tryActivateAgain])
    }

    @MainActor @Test func cancelBeforeThePageAnswersOpensNoPage() async {
        let env = Dependencies(now: { 200 }, random: { _ in 0 })
        let store = Store(player: FakePlayer(), library: FakeLibrary(), state: join(), env: env, activator: FakeActivator())
        let opened = Count()
        store.onOpenActivatePage = { _ in opened.n += 1 }
        store.send(.select)
        store.send(.menu)  // Cancel before /v1/open answers
        try? await Task.sleep(for: .milliseconds(100))
        #expect(opened.n == 0 && store.state.activation == .locked)
    }

    @MainActor @Test func aLateLaunchAnswerDoesNotUndoACancel() async {
        let env = Dependencies(now: { 200 }, random: { _ in 0 })
        let store = Store(player: FakePlayer(), library: FakeLibrary(), state: join(), env: env, activator: FakeActivator())
        store.onOpenActivatePage = { _ in }
        store.checkActivationAtLaunch()
        store.send(.select)
        store.send(.menu)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(store.state.activation == .locked)
    }
}

@MainActor final class Count { var n = 0; var url = "" }

struct FakeActivator: Activator {
    var page: String? = "https://getmypod.app/activate/?d=code"
    var wait = 0.0
    func pageURL() async -> String? {
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        return page
    }
    func status() async -> Activation { .waiting(email: "sam@example.com", mail: 1) }
    func sendAgain() async -> Activation { .waiting(email: "sam@example.com", mail: 2) }
}
