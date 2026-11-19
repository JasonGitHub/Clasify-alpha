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
        #expect(s.today?.bands == [0, 0, 3.5, 2] && s.settings.today == s.today)
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
        _ = events(&s, .position(1, generation: s.playGen), now: at(10))
        s.service = .appleMusic
        let sent = events(&s, .tick, now: at(10, day: 20))
        guard case .dayActive(_, let service)? = sent.first else { Issue.record("no day_active"); return }
        #expect(service == .spotify)
    }

    @Test func theFirstActionOfALaterDaySendsTheDayBefore() {
        var s = playing()
        _ = events(&s, .position(1, generation: s.playGen), .position(2, generation: s.playGen), now: at(23, 59))
        _ = events(&s, .used(.takeApart), now: at(23, 59.5))
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
        #expect(s.today?.features == [.coverFlow, .aboutFlip] && s.today?.hadMusic == false)
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
        d.service = .appleMusic
        #expect(d.saved == "20261119|5|3|0.0,1.5,1200.25,0.0|coverFlow,settings|Apple Music")
        #expect(DayUse(saved: d.saved) == d && DayUse(saved: "20261119|5|x|0,0,0,0||") == nil)
        let store = FakeSettings()
        var saved = Settings()
        saved.today = d
        saved.save(to: store)
        #expect(Settings(from: store).today == d)
    }
}
