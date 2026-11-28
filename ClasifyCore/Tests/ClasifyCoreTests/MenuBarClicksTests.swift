import Foundation
import Testing
@testable import ClasifyCore

/// CLA-201 (Jason 08:31 JST 11-28): `day_active` says how often the menu bar icon was clicked that day.
@Suite struct MenuBarClicksTests {
    let day = DayActiveTests()

    @Test func eachClickCountsShownOrHidden() {
        var s = mainMenu()
        _ = day.events(&s, .menuBarClick(shown: false), .menuBarClick(shown: true), .menuBarClick(shown: false), now: day.at(10))
        #expect(s.today?.menuBarClicks == 3 && s.today?.day == 20261119)
        var setup = activatedMac()  // before the setup ends too
        _ = day.events(&setup, .menuBarClick(shown: true), now: day.at(10))
        #expect(!setup.setupDone && setup.today?.menuBarClicks == 1)
    }

    @Test func aDayWithOnlyClicksIsUsedAndGoesOut() {
        var s = mainMenu()
        _ = day.events(&s, .menuBarClick(shown: true), .menuBarClick(shown: false), now: day.at(10))
        #expect(s.today?.hadUse == true && s.today?.songs == 0 && s.today?.seconds == 0)
        let sent = day.events(&s, .tick, now: day.at(9, day: 20))  // the next day
        guard sent.count == 1, case .dayActive(let d, _, _, _) = sent[0] else { Issue.record("no day_active"); return }
        #expect(d.day == 20261119 && d.menuBarClicks == 2)
        #expect(sent[0].properties["menu_bar_clicks"] == .number(2) && sent[0].properties["songs"] == .number(0))
    }

    /// Like the other counts, the number always goes out, also 0.
    @Test func theNumberGoesOutAlsoAsZero() {
        var d = DayUse(day: 20261119, weekday: 5)
        d.songs = 1
        #expect(BetaEvent.dayActive(d, service: .spotify, color: .silver).properties["menu_bar_clicks"] == .number(0))
    }

    /// A quit sends the day so far and starts again from zero (CLA-182): two runs add up.
    @Test func aQuitSendsTheClicksAndStartsAgainFromZero() {
        var s = mainMenu()
        _ = day.events(&s, .menuBarClick(shown: true), now: day.at(10))
        let sent = day.events(&s, .willQuit(openSeconds: nil), now: day.at(10) + 5)
        guard case .dayActive(let d, _, _, _)? = sent.first else { Issue.record("no day_active at quit"); return }
        #expect(d.menuBarClicks == 1 && s.today?.menuBarClicks == 0 && s.settings.today == s.today)
        var next = mainMenu()
        next.settings = s.settings
        _ = day.events(&next, .menuBarClick(shown: false), .menuBarClick(shown: true), now: day.at(11))
        let rest = day.events(&next, .willQuit(openSeconds: nil), now: day.at(11) + 5)
        guard case .dayActive(let r, _, _, _)? = rest.first else { Issue.record("no day_active at quit"); return }
        #expect(r.day == 20261119 && r.menuBarClicks == 2)  // 1 + 2 = 3 for the day
    }

    @Test func theClicksSaveAndAnOldSavedDayReadsAsZero() {
        var d = DayUse(day: 20261119, weekday: 5)
        d.songsShuffle = 2; d.songsRepeat = 1; d.songsCut = 1; d.menuBarClicks = 7
        #expect(d.saved.hasSuffix("|2,1,1,7|0,0.0") && DayUse(saved: d.saved) == d)
        let old = "20261119|5|3|0,0,0,0||Spotify|1,2,3|0,0,0,0,0,0,0,0,0;0;|"
        #expect(DayUse(saved: old + "2,1,1")?.menuBarClicks == 0 && DayUse(saved: old + "2,1,1")?.songsCut == 1)
        #expect(DayUse(saved: old + "2,1")?.menuBarClicks == 0)
        #expect(DayUse(saved: old + "2,1,1,7,9") == nil)
        var s = mainMenu()  // the saved copy follows a click
        _ = day.events(&s, .menuBarClick(shown: true), now: day.at(10))
        #expect(s.savedToday?.menuBarClicks == 1)
    }
}
