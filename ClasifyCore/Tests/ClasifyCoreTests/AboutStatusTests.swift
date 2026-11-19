import Foundation
import Testing
@testable import ClasifyCore

/// CLA-141, card BF.2 (changes 360-362): About's Status row and the Activation screen.
@Suite struct AboutStatusTests {
    let info = ActiveInfo(email: "s***@example.com", since: 1_795_000_000, macs: 1, limit: 2)

    /// About, on a Mac activated (or not), and the server's answer `answer`.
    func about(_ answer: Activation?, activated: Bool = true) -> AppState {
        var s = ReducerTests().openAbout()
        s.activated = activated
        if let answer { send(&s, .activation(answer, request: nil)) }
        return s
    }

    @Test func theActiveAnswerCarriesTheInfo() {
        // A real answer: `since` is Date.now() on the server, in milliseconds.
        let json: [String: Any] = ["state": "active", "account": "a1", "email": "s***@example.com", "since": 1_795_000_000_000, "macs": 1, "limit": 2]
        var withAccount = info
        withAccount.account = "a1"  // CLA-97: kept in memory for the beta events
        #expect(Activation(status: 200, json: json) == .active(withAccount) && Activation.active(withAccount).account == "a1")
        let utc = TimeZone(identifier: "UTC")!
        #expect(ActiveInfo(since: 1_795_000_000).subtitle(in: utc) == "Activated on 18 Nov 2026")
        #expect(Activation(status: 200, json: ["state": "active", "since": 1500.0]) == .active(ActiveInfo(since: 1.5)))
        #expect(Activation(status: 200, json: ["state": "active", "account": "a1"]) == .active(ActiveInfo(account: "a1")))  // an old server: only the account
        #expect(Activation.locked.account == nil && Activation.active(nil).account == nil)
        #expect(Activation.active(info).isActive && !Activation.locked.isActive)
    }

    /// "d MMM yyyy" in English in the Mac's time zone, a middle dot, and only the parts known.
    @Test func theSubtitleShowsWhatItHas() throws {
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo")), utc = try #require(TimeZone(identifier: "UTC"))
        let at = 1_795_014_000.0  // 2026-11-18 15:00 UTC, 2026-11-19 00:00 JST
        #expect(ActiveInfo(since: at, macs: 1, limit: 2).subtitle(in: tokyo) == "Activated on 19 Nov 2026 · 1 of 2 Macs")
        #expect(ActiveInfo(since: at).subtitle(in: utc) == "Activated on 18 Nov 2026")
        #expect(ActiveInfo(macs: 2, limit: 2).subtitle(in: utc) == "2 of 2 Macs")
        #expect(ActiveInfo(macs: 2).subtitle(in: utc) == nil)  // no limit: no count
        #expect(ActiveInfo(email: "s***@example.com").subtitle(in: utc) == nil)
        #expect(ActiveInfo(since: 1_796_464_800).subtitle(in: utc) == "Activated on 5 Dec 2026")  // no leading zero
        #expect(ActiveInfo(since: 1_788_220_800).subtitle(in: utc) == "Activated on 1 Sep 2026")  // "Sep", not "Sept"
    }

    @Test func theStatusFollowsTheFlagAndTheAnswer() {
        #expect(about(nil, activated: false).aboutStatus == .notActivated)
        #expect(about(.active(info)).aboutStatus == .activated(info) && about(.active(info)).aboutStatus.opens)
        // No connection at launch (the answer is dropped) or an old server: "Activated", no chevron.
        #expect(about(.offline).aboutStatus == .activated(nil) && !about(.offline).aboutStatus.opens)
        #expect(!about(.active(nil)).aboutStatus.opens)
        #expect(!about(.active(ActiveInfo(since: 1))).aboutStatus.opens)  // no email: nothing to show
        #expect(about(.active(ActiveInfo(email: "s***@example.com"))).aboutStatus.opens)
    }

    /// Step 1 (card CC) opens Activation when the row opens: one two-line row. The wheel and a
    /// press do nothing there, and MENU goes back to About at step 1.
    @Test func step1OpensActivation() {
        var s = about(.active(info))
        send(&s, .wheel(1), now: 1005)
        #expect(s.top.off == AppState.aboutStatusStep)
        send(&s, .select, now: 1006)
        #expect(s.top.screen == .activation && s.rows(for: s.top) == [.activatedAs] && s.shownRows == trackRows)
        let there = s
        send(&s, .wheel(1), .wheel(-1), .select, now: 1007)
        #expect(s.stack == there.stack)
        send(&s, .menu, now: 1100)
        #expect(s.top.screen == .about && s.top.off == AppState.aboutStatusStep && s.aboutIdleAt == 1100)
    }

    /// A row that does not open: a press at step 1 waves, as at step 0.
    @Test func step1WithNoInfoWaves() {
        for answer: Activation? in [nil, .offline, .active(nil)] {
            var s = about(answer, activated: answer != nil)
            send(&s, .wheel(1), now: 1005)
            send(&s, .select, now: 1006)
            #expect(s.top.screen == .about && s.aboutWaveAt == 1006)
        }
    }

    /// The email is never saved: the settings hold no part of it.
    @Test func theEmailIsNeverSaved() {
        let store = FakeSettings()
        let s = about(.active(info))
        s.settings.save(to: store)
        #expect(!store.values.values.contains { $0.contains("@") || $0.contains("***") })
    }
}
