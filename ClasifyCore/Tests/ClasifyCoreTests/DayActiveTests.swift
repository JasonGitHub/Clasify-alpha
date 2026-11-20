import Foundation
import Testing
@testable import ClasifyCore

/// CLA-97, A2b: `day_active`, one event for each day with music.
@Suite struct DayActiveTests {
    /// 2026-11-19 (a Thursday) at `hour`:`minute` in Tokyo, in `Dependencies.now` time.
    func at(_ hour: Int, _ minute: Double = 0, day: Int = 19) -> Double {
        var c = DateComponents(year: 2026, month: 11, day: day, hour: hour)
        c.timeZone = tokyo
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tokyo
        return cal.date(from: c)!.timeIntervalSinceReferenceDate + minute * 60
    }
    let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    func events(_ s: inout AppState, _ actions: Action..., now: Double) -> [BetaEvent] {
        var e = Dependencies(now: { now }, random: { _ in 0 })
        e.timeZone = tokyo
        return actions.flatMap { reduce(&s, $0, e) }.compactMap { (fx: Effect) -> BetaEvent? in
            if case .track(let event) = fx { return event }
            return nil
        }
    }

    /// Playing track "l0" on the main menu.
    func playing() -> AppState {
        var s = mainMenu()
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "l0"); s.isPlaying = true
        return s
    }

    @Test func positionReportsCountSongsAndSecondsInTheirTimeBand() {
        var s = playing()
        _ = events(&s, .position(1, generation: s.playGen), now: at(10))
        _ = events(&s, .position(2, generation: s.playGen), now: at(10) + 1)
        _ = events(&s, .position(3, generation: s.playGen), now: at(10) + 2.5)
        _ = events(&s, .position(4, generation: s.playGen), now: at(10) + 60)  // a long gap counts what played: 1 s
        #expect(s.today?.songs == 1 && s.today?.bands == [0, 0, 3.5, 0] && s.today?.day == 20261119 && s.today?.weekday == 5)
        #expect(s.today?.service == .spotify)
        s.isPlaying = false
        _ = events(&s, .tick, now: at(10) + 61)  // a pause
        s.isPlaying = true; s.current?.track = "l1"
        _ = events(&s, .position(1, generation: s.playGen), now: at(19) + 0)
        _ = events(&s, .position(2, generation: s.playGen), now: at(19) + 2)
        #expect(s.today?.songs == 2 && s.today?.bands == [0, 0, 3.5, 2])
        s.isPlaying = false
        _ = events(&s, .tick, now: at(19) + 3)
        s.isPlaying = true
        _ = events(&s, .position(3, generation: s.playGen), now: at(19) + 100)  // after a pause: nothing for the gap
        #expect(s.today?.bands == [0, 0, 3.5, 2])
    }

    /// Codex on #348: a gap over a band start or midnight splits.
    @Test func aGapOverABandStartOrMidnightSplits() {
        var s = playing()
        _ = events(&s, .position(1, generation: s.playGen), now: at(17, 59) + 50)
        _ = events(&s, .position(21, generation: s.playGen), now: at(18) + 10)
        #expect(s.today?.bands == [0, 0, 10, 10])
        var late = playing()
        _ = events(&late, .position(1, generation: late.playGen), now: at(23, 59) + 50)
        let sent = events(&late, .position(21, generation: late.playGen), now: at(0, day: 20) + 10)
        guard case .dayActive(let old, _)? = sent.first else { Issue.record("no day_active"); return }
        #expect(old.bands == [0, 0, 0, 10] && old.day == 20261119)
        #expect(late.today?.bands == [10, 0, 0, 0] && late.today?.day == 20261120 && late.today?.songs == 1)
    }

    /// Codex on #348: an action after midnight, before the next report, does not split the day in two.
    @Test func anActionJustAfterMidnightWaitsForTheNextReport() {
        var s = playing()
        _ = events(&s, .position(1, generation: s.playGen), now: at(23, 59) + 59)
        #expect(events(&s, .wheel(1), now: at(0, day: 20) + 0.1).isEmpty && s.today?.day == 20261119)
        let sent = events(&s, .position(2, generation: s.playGen), now: at(0, day: 20) + 1)
        #expect(sent.count == 1 && s.today?.day == 20261120 && s.today?.bands[0] == 1)
        guard case .dayActive(let old, _)? = sent.first else { Issue.record("no day_active"); return }
        #expect(old.bands[3] == 1 && old.songs == 1)
        #expect(events(&s, .tick, now: at(0, day: 20) + 2).isEmpty)  // no second day_active
    }

    /// Codex on #348: a feature used after midnight, while the day before waits, goes to the new day.
    @Test func aFeatureUsedJustAfterMidnightGoesToTheNewDay() {
        var s = playing()
        _ = events(&s, .position(1, generation: s.playGen), now: at(23, 59) + 59)
        #expect(events(&s, .used(.takeApart), now: at(0, day: 20)).isEmpty)
        #expect(s.today?.day == 20261119 && s.today?.features.isEmpty == true && s.pendingFeatures == [.takeApart])
        let sent = events(&s, .position(2, generation: s.playGen), now: at(0, day: 20) + 1)
        guard case .dayActive(let old, _)? = sent.first else { Issue.record("no day_active"); return }
        #expect(old.features.isEmpty && s.today?.day == 20261120 && s.today?.features == [.takeApart] && s.pendingFeatures.isEmpty)
        // At a quit, the waiting day ends and the feature goes to the new day.
        var quit = playing()
        _ = events(&quit, .position(1, generation: quit.playGen), now: at(23, 59) + 59)
        _ = events(&quit, .used(.aboutFlip), now: at(0, day: 20))
        let atQuit = events(&quit, .willQuit, now: at(0, day: 20) + 1)
        guard case .dayActive(let day, _)? = atQuit.first else { Issue.record("no day_active at quit"); return }
        #expect(day.day == 20261119 && day.features.isEmpty)
        #expect(quit.today?.day == 20261120 && quit.today?.features == [.aboutFlip] && quit.settings.today == quit.today)
    }

    /// The safety net: a part of a day that already went out goes to today's night band.
    @Test func aPartOfAClosedDayGoesToTodaysNightBand() {
        var s = playing()
        s.today = DayUse(day: 20261120, weekday: 6)
        (s.dayPlayAt, s.dayTrack, s.dayPosition) = (at(23, 59) + 55, "l0", 1)
        #expect(events(&s, .position(11, generation: s.playGen), now: at(0, day: 20) + 5).isEmpty)
        #expect(s.today?.day == 20261120 && s.today?.bands == [10, 0, 0, 0])
    }

    /// Jason 23:07 JST: the saved copy follows about once a minute, at a pause and at a quit.
    @Test func theDaySavesAboutOnceAMinuteAtAPauseAndAtAQuit() {
        var s = playing()
        var saves = 0
        for i in 0..<30 {
            let before = s.savedToday
            _ = events(&s, .position(Double(i + 1), generation: s.playGen), now: at(10) + Double(i))
            if s.savedToday != before { saves += 1 }
        }
        #expect(saves == 1 && s.today?.seconds == 29 && s.savedToday?.seconds == 0 && s.settings.today?.seconds == 0)
        _ = events(&s, .position(31, generation: s.playGen), now: at(10) + 30)
        _ = events(&s, .position(61, generation: s.playGen), now: at(10) + 60)  // the minute changes
        #expect(s.savedToday?.seconds == 60)
        _ = events(&s, .position(62, generation: s.playGen), now: at(10) + 61)
        #expect(s.savedToday?.seconds == 60)
        _ = events(&s, .play, now: at(10) + 61.5)  // a pause saves the exact count
        #expect(!s.isPlaying && s.savedToday == s.today && s.savedToday?.seconds == 61)
        var quit = playing()
        _ = events(&quit, .position(1, generation: quit.playGen), .position(2, generation: quit.playGen), now: at(10))
        _ = events(&quit, .position(3, generation: quit.playGen), now: at(10) + 1)
        #expect(quit.savedToday?.seconds == 0)
        _ = events(&quit, .willQuit, now: at(10) + 1)
        #expect(quit.savedToday?.seconds == 1 && quit.settings.today == quit.today)
    }

    /// App Nap can slow the reports while myPod is hidden: the position says what played.
    @Test func slowReportsCountWhatPlayedAndASeekCountsNoMore() {
        var s = playing()
        _ = events(&s, .position(1, generation: s.playGen), now: at(10))
        _ = events(&s, .position(21, generation: s.playGen), now: at(10) + 20)
        #expect(s.today?.bands[2] == 20)
        _ = events(&s, .position(121, generation: s.playGen), now: at(10) + 21)  // a seek forward in 1 s
        #expect(s.today?.bands[2] == 21)
        _ = events(&s, .position(10, generation: s.playGen), now: at(10) + 40)  // the position went back
        #expect(s.today?.bands[2] == 26)
        s.current?.track = "l1"
        _ = events(&s, .position(30, generation: s.playGen), now: at(10) + 70)  // another track
        #expect(s.today?.bands[2] == 31 && s.today?.songs == 2)
    }

    /// The day keeps the service of its music, also after a switch on a later day.
    @Test func theDaySendsItsOwnService() {
        var s = playing()
        _ = events(&s, .position(1, generation: s.playGen), .play, now: at(10))  // a switch stops the music
        s.service = .appleMusic
        let sent = events(&s, .tick, now: at(10, day: 20))
        guard case .dayActive(_, let service)? = sent.first else { Issue.record("no day_active"); return }
        #expect(service == .spotify)
    }

    @Test func theFirstActionOfALaterDaySendsTheDayBefore() {
        var s = playing()
        _ = events(&s, .position(1, generation: s.playGen), .position(2, generation: s.playGen), now: at(23, 59))
        _ = events(&s, .used(.takeApart), .play, now: at(23, 59.5))  // the music stops before midnight
        let day = s.today!
        let sent = events(&s, .tick, now: at(0, 1, day: 20))
        #expect(sent == [.dayActive(day, service: .spotify)] && s.today == nil)
        #expect(events(&s, .tick, now: at(9, day: 21)).isEmpty)  // a day with nothing sends nothing
        var p = BetaEvent.dayActive(day, service: .spotify).properties
        #expect(p.removeValue(forKey: "used_takeApart") == .flag(true) && p["used_coverFlow"] == .flag(false))
        #expect(p["day"] == .number(20261119) && p["songs"] == .number(1) && p["minutes"] == .decimal(0))
    }

    @Test func coverFlowSettingsAndSkinFeaturesSetTheirFlagOnce() {
        var s = mainMenu()
        #expect(events(&s, .wheel(1), now: at(12)).isEmpty && s.today == nil)  // nothing to count: no day yet
        s.stack.append(Frame(screen: .coverFlow))
        _ = events(&s, .tick, now: at(12))
        _ = events(&s, .used(.aboutFlip), .used(.aboutFlip), now: at(12))
        #expect(s.today?.features == [.coverFlow, .aboutFlip] && s.today?.seconds == 0)
        // CTO 00:08 JST: a day with features and no music goes out too, with minutes 0.
        let sent = events(&s, .tick, now: at(12, day: 20))
        guard case .dayActive(let day, _)? = sent.first else { Issue.record("no day_active"); return }
        #expect(day.features == [.coverFlow, .aboutFlip] && day.songs == 0 && day.hadUse)
        #expect(!DayUse(day: 20261119, weekday: 5).hadUse)
        var set = mainMenu()
        set.stack.append(Frame(screen: .settings))
        _ = events(&set, .tick, now: at(12))
        #expect(set.today == nil)
        _ = events(&set, .wheel(1), now: at(12))
        #expect(set.today == nil)
        _ = events(&set, .select, now: at(12))  // Shuffle changes
        #expect(set.today?.features == [.settings])
    }

    @Test func theDaySavesAndLoads() {
        var d = DayUse(day: 20261119, weekday: 5)
        d.songs = 3; d.bands = [0, 1.5, 1200.25, 0]; d.features = [.settings, .coverFlow]
        d.service = .appleMusic; d.views = [12.5, 0, 3]
        #expect(d.saved == "20261119|5|3|0.0,1.5,1200.25,0.0|coverFlow,settings|Apple Music|12.5,0.0,3.0|"
            + "0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0;0;")
        d.areas[4] = 60; d.screens = ["1x1512x982x1": 50, "0x2560x1440x2": 10]; d.screenCount = 2
        #expect(DayUse(saved: d.saved) == d)
        // A day saved before the window part reads with no window time.
        #expect(DayUse(saved: "20261119|5|3|0,0,0,0||Spotify|1,2,3")?.areas == Array(repeating: 0, count: 9))
        #expect(DayUse(saved: d.saved) == d && DayUse(saved: "20261119|5|x|0,0,0,0||") == nil)
        // A day saved before the 3D views reads with views 0.
        #expect(DayUse(saved: "20261119|5|3|0,0,0,0||Spotify")?.views == [0, 0, 0])
        #expect(DayUse(saved: "20261119|5|3|0,0,0,0||Spotify|1,2") == nil)
        let store = FakeSettings()
        var saved = Settings()
        saved.today = d
        saved.save(to: store)
        #expect(Settings(from: store).today == d)
    }

    /// Jason 23:58 JST: the time of each 3D view, its flag, the 30 min cap and the quit.
    @Test func the3DViewsCountTheirSecondsAndFlags() {
        var s = playing()
        _ = events(&s, .position(1, generation: s.playGen), now: at(10))
        _ = events(&s, .view3D(.turn, open: true), now: at(10) + 1)
        #expect(s.today?.features.contains(.turn3D) == true && s.viewOpen[.turn] == at(10) + 1)
        _ = events(&s, .view3D(.turn, open: true), now: at(10) + 2)  // already open: the first start stays
        _ = events(&s, .view3D(.turn, open: false), now: at(10) + 4.5)
        #expect(s.today?.views == [3.5, 0, 0] && s.viewOpen.isEmpty && s.savedToday?.views == [3.5, 0, 0])
        _ = events(&s, .view3D(.turn, open: false), now: at(10) + 9)  // not open: nothing
        _ = events(&s, .view3D(.apart, open: true), now: at(11))
        _ = events(&s, .view3D(.apart, open: false), now: at(12))  // a window left open: 30 min at most
        _ = events(&s, .view3D(.aboutFlip, open: true), now: at(12) + 5)
        #expect(s.today?.features.isSuperset(of: [.takeApart, .aboutFlip]) == true)
        _ = events(&s, .willQuit, now: at(12) + 15)  // a quit closes the open About flip
        #expect(s.today?.views == [3.5, 1800, 10] && s.viewOpen.isEmpty)
        let p = BetaEvent.dayActive(s.today!, service: .spotify).properties
        #expect(p["seconds_3d"] == .decimal(3.5) && p["seconds_apart"] == .decimal(1800) && p["seconds_about_flip"] == .decimal(10))
        #expect(p["used_turn3D"] == .flag(true))
    }

    /// CLA-162: window reports count visible seconds by area and screen, at most 90 s a gap.
    @Test func windowReportsCountWhereTheWindowIs() {
        var s = playing()
        _ = events(&s, .position(1, generation: s.playGen), now: at(10))
        let center = WindowSpot(area: 4, mainScreen: true, screens: 2, width: 1512, height: 982, display: 1)
        let side = WindowSpot(area: 2, mainScreen: false, screens: 2, width: 2560, height: 1440, display: 2)
        _ = events(&s, .window(center), now: at(10) + 1)
        #expect(s.windowSpot == center && s.today?.visible == 0)
        _ = events(&s, .window(center), now: at(10) + 61)
        _ = events(&s, .window(nil), now: at(10) + 121)  // covered: the minute before still counts
        _ = events(&s, .window(side), now: at(11))  // not visible since: nothing
        _ = events(&s, .window(side), now: at(12))  // a Mac sleep: 90 s at most
        _ = events(&s, .willQuit, now: at(12) + 30)
        #expect(s.today?.areas == [0, 0, 120, 0, 120, 0, 0, 0, 0] && s.windowSpot == nil && s.windowAt == nil)
        #expect(s.today?.screens == ["1x1512x982x1": 120, "0x2560x1440x2": 120] && s.today?.screenCount == 2)
        s.today?.areas[2] += 1; s.today?.screens["0x2560x1440x2"]? += 1
        let p = BetaEvent.dayActive(s.today!, service: .spotify).properties
        #expect(p["spot"] == .text("top_right") && p["minutes_visible"] == .decimal(241.0 / 60) && p["screens"] == .number(2))
        #expect(p["main_screen"] == .flag(false) && p["screen_width"] == .number(2560) && p["screen_height"] == .number(1440))
        let none = BetaEvent.dayActive(DayUse(day: 20261119, weekday: 5), service: .spotify).properties
        #expect(none["spot"] == nil && none["screens"] == nil && none["minutes_visible"] == .decimal(0))
        // Codex on #360: two screens of one size count apart.
        let a = WindowSpot(area: 0, mainScreen: false, screens: 3, width: 1920, height: 1080, display: 3)
        var b = a; b.display = 4
        #expect(a.screenKey != b.screenKey)
        // An area off the grid goes to the nearest edge.
        #expect(WindowSpot(area: 12, mainScreen: true, screens: 1, width: 1, height: 1).area == 8)
    }

    /// A 3D view open over midnight: each part goes to its own day.
    @Test func a3DViewOverMidnightSplitsAtMidnight() {
        var s = playing()
        _ = events(&s, .position(1, generation: s.playGen), .play, now: at(23, 59))  // music, then a pause
        _ = events(&s, .view3D(.apart, open: true), now: at(23, 59) + 50)
        let sent = events(&s, .view3D(.apart, open: false), now: at(0, day: 20) + 20)
        guard case .dayActive(let old, _)? = sent.first else { Issue.record("no day_active"); return }
        #expect(old.day == 20261119 && old.views == [0, 10, 0])
        #expect(s.today?.day == 20261120 && s.today?.views == [0, 20, 0])
    }

    /// Codex on #352: an action after midnight, while a view is open, sends the day before once,
    /// with its part of the view; with music the same at the next report.
    @Test func aViewOpenOverMidnightSendsTheDayBeforeOnceWhole() {
        var s = playing()
        _ = events(&s, .position(1, generation: s.playGen), .play, now: at(23, 59))
        _ = events(&s, .view3D(.apart, open: true), now: at(23, 59) + 50)
        let sent = events(&s, .tick, now: at(0, day: 20) + 1)
        guard case .dayActive(let old, _)? = sent.first else { Issue.record("no day_active"); return }
        #expect(sent.count == 1 && old.views == [0, 10, 0])
        #expect(events(&s, .view3D(.apart, open: false), now: at(0, day: 20) + 20).isEmpty)
        #expect(s.today?.day == 20261120 && s.today?.views == [0, 20, 0])
        var music = playing()
        _ = events(&music, .position(1, generation: music.playGen), now: at(23, 59) + 50)
        _ = events(&music, .view3D(.apart, open: true), now: at(23, 59) + 50)
        let atReport = events(&music, .position(12, generation: music.playGen), now: at(0, day: 20) + 1)
        guard case .dayActive(let day, _)? = atReport.first else { Issue.record("no day_active"); return }
        #expect(atReport.count == 1 && day.views == [0, 10, 0])
        _ = events(&music, .view3D(.apart, open: false), now: at(0, day: 20) + 20)
        #expect(music.today?.views == [0, 20, 0])
    }

    /// Codex on #352: two views open over two midnights: each day gets the part of both.
    @Test func twoViewsOpenOverTwoMidnightsGiveEachDayItsPart() {
        var s = playing()
        _ = events(&s, .position(1, generation: s.playGen), .play, now: at(23, 59))
        _ = events(&s, .view3D(.turn, open: true), .view3D(.apart, open: true), now: at(23, 59) + 50)
        let sent = events(&s, .tick, now: at(9, day: 21))
        let days = sent.compactMap { e -> DayUse? in if case .dayActive(let d, _) = e { d } else { nil } }
        #expect(days.map(\.day) == [20261119, 20261120])
        #expect(days.first?.views == [10, 10, 0] && days.last?.views == [1790, 1790, 0])
    }
}
