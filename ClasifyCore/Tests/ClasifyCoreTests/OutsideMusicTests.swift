import Foundation
import Testing
@testable import ClasifyCore

/// CLA-203 (fix 5, CTO): music that the Spotify app on this Mac plays while myPod is not in
/// control counts only in `outside_songs` and `outside_minutes`, never in `songs` or the bands.
@Suite struct OutsideMusicTests {
    let day = DayActiveTests()

    @Test func outsideMusicCountsSongsAndTimeButNotTheDaysMusic() {
        var s = mainMenu()
        _ = day.events(&s, .outsideMusic(playing: true, song: true), now: day.at(10))
        _ = day.events(&s, .outsideMusic(playing: true, song: true), now: day.at(10, 3))
        _ = day.events(&s, .outsideMusic(playing: false, song: false), now: day.at(10, 4))
        #expect(s.today?.outsideSongs == 2 && s.today?.outsideSeconds == 240)
        #expect(s.today?.songs == 0 && s.today?.seconds == 0 && s.outsideAt == nil)
        // Stopped: the time until the next start does not count.
        _ = day.events(&s, .outsideMusic(playing: true, song: false), now: day.at(11))
        _ = day.events(&s, .outsideMusic(playing: false, song: false), now: day.at(11, 1))
        #expect(s.today?.outsideSongs == 2 && s.today?.outsideSeconds == 300)
    }

    /// A gap longer than `outsideGapLimit` (a sleep) counts only up to it.
    @Test func aLongGapCountsOnlyUpToTheLimit() {
        var s = mainMenu()
        _ = day.events(&s, .outsideMusic(playing: true, song: true), now: day.at(10))
        _ = day.events(&s, .outsideMusic(playing: false, song: false), now: day.at(12))
        #expect(s.today?.outsideSeconds == outsideGapLimit)
    }

    @Test func aQuitEndsTheOutsideMusicAndSendsIt() {
        var s = mainMenu()
        _ = day.events(&s, .outsideMusic(playing: true, song: true), now: day.at(10))
        let sent = day.events(&s, .willQuit(openSeconds: nil), now: day.at(10, 2))
        guard case .dayActive(let d, _, _, _)? = sent.first else { Issue.record("no day_active at quit"); return }
        #expect(d.outsideSongs == 1 && d.outsideSeconds == 120 && s.outsideAt == nil)
        #expect(sent[0].properties["outside_songs"] == .number(1) && sent[0].properties["outside_minutes"] == .decimal(2))
        #expect(sent[0].properties["songs"] == .number(0) && sent[0].properties["minutes"] == .decimal(0))
    }

    @Test func aDayWithOnlyOutsideMusicGoesOutAndTheFieldsAreAlsoZero() {
        var s = mainMenu()
        _ = day.events(&s, .outsideMusic(playing: true, song: true), now: day.at(10))
        #expect(s.today?.hadUse == true)
        var d = DayUse(day: 20261119, weekday: 5)
        d.songs = 1
        let props = BetaEvent.dayActive(d, service: .spotify, color: .silver).properties
        #expect(props["outside_songs"] == .number(0) && props["outside_minutes"] == .decimal(0))
    }

    @Test func theOutsideMusicSavesAndAnOldSavedDayReadsAsZero() {
        var d = DayUse(day: 20261119, weekday: 5)
        d.menuBarClicks = 7; d.outsideSongs = 3; d.outsideSeconds = 412.5
        #expect(d.saved.hasSuffix("|0,0,0,7|3,412.5") && DayUse(saved: d.saved) == d)
        let old = "20261119|5|3|0,0,0,0||Spotify|1,2,3|0,0,0,0,0,0,0,0,0;0;|2,1,1,7"
        #expect(DayUse(saved: old)?.outsideSongs == 0 && DayUse(saved: old)?.outsideSeconds == 0)
        #expect(DayUse(saved: old + "|3") == nil)
    }

    /// No screen, no effect: only the day's count changes.
    @Test func theReducerChangesNothingElse() {
        var s = mainMenu()
        let before = s
        let fx = reduce(&s, .outsideMusic(playing: true, song: true), Dependencies(now: { 200 }, random: { _ in 0 }))
        #expect(fx.isEmpty && s.stack == before.stack && s.isPlaying == before.isPlaying && s.outsideAt == 200)
    }
}
