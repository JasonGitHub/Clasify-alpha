import Foundation
import Testing
@testable import ClasifyCore

/// CLA-186: `songs_cut` in `day_active`, the songs that ended by themselves under 5 s after their start.
extension DayActiveTests {
    /// "l0" plays from 0 at 10:00 and reports up to `t` seconds, one report a second.
    func started(upTo t: Double = 2) -> AppState {
        var s = playing()
        var p = 0.5
        while p <= t {
            _ = events(&s, .position(p, generation: s.playGen), now: at(10) + p)
            p += 1
        }
        return s
    }

    @Test func aSongThatTheEngineMovesOnFromUnder5SecondsCounts() {
        var s = started()
        _ = events(&s, .trackChanged("l1", playing: true, generation: s.playGen), now: at(10) + 2)
        #expect(s.today?.songsCut == 1)
        // The next song's reports start it; it plays on: no more.
        _ = events(&s, .position(0.5, generation: s.playGen), .position(9, generation: s.playGen), now: at(10) + 11)
        #expect(s.today?.songsCut == 1 && s.today?.songs == 2)
    }

    @Test func anEndOrAFailureUnder5SecondsCountsOnce() {
        var s = started()
        _ = events(&s, .trackEnded(generation: s.playGen), now: at(10) + 3)
        #expect(s.today?.songsCut == 1)
        s = started()
        // Local: a broken file reports the failure, then the next song: one cut.
        _ = events(&s, .playbackFailed("x", generation: s.playGen), now: at(10) + 2)
        _ = events(&s, .trackChanged("l1", playing: true, generation: s.playGen), now: at(10) + 2)
        #expect(s.today?.songsCut == 1)
    }

    @Test func aSongThatPlayed5SecondsOrMoreDoesNotCount() {
        var s = started(upTo: 4.5)
        _ = events(&s, .trackChanged("l1", playing: true, generation: s.playGen), now: at(10) + 5)  // 4.5 + 0.5
        #expect(s.today?.songsCut == 0)
        // Sparse reports (App Nap): the time since the last report counts as play.
        s = started(upTo: 1)
        _ = events(&s, .trackChanged("l1", playing: true, generation: s.playGen), now: at(10) + 30)
        #expect(s.today?.songsCut == 0)
    }

    @Test func aPersonsNextPrevPausePickOrSwitchDoesNotCount() {
        for stop: Action in [.next, .prev, .play] {
            var s = started()
            _ = events(&s, stop, now: at(10) + 2)
            _ = events(&s, .trackChanged("l1", playing: true, generation: s.playGen), .trackEnded(generation: s.playGen), now: at(10) + 2.5)
            #expect(s.today?.songsCut == 0, "\(stop)")
        }
        var s = started()
        // A service switch stops the song first (`stop()`): the old engine's late report finds no song.
        (s.service, s.current, s.isPlaying) = (.appleMusic, nil, false)
        _ = events(&s, .trackEnded(generation: s.playGen), now: at(10) + 3)
        #expect(s.today?.songsCut == 0)
    }

    @Test func aQuitOrALateReportOfAnOlderLoadDoesNotCount() {
        var s = started()
        _ = events(&s, .willQuit(openSeconds: nil), now: at(10) + 2)
        #expect(s.today?.songsCut == 0)
        s = started()
        _ = events(&s, .trackChanged("l1", playing: true, generation: s.playGen - 1), now: at(10) + 2)
        #expect(s.today?.songsCut == 0)
    }

    @Test func aSongShorterThan5SecondsDoesNotCountOneWithNoKnownLengthDoes() {
        var s = started()
        s.extraTracks.append(Track(id: "l0", title: "Intro", artist: "a", duration: 3))
        _ = events(&s, .trackChanged("l1", playing: true, generation: s.playGen), now: at(10) + 3)
        #expect(s.today?.songsCut == 0)
        s = started()  // "l0" is not in the read library: its length is not known
        _ = events(&s, .trackChanged("l1", playing: true, generation: s.playGen), now: at(10) + 3)
        #expect(s.today?.songsCut == 1)
    }

    /// Codex on #474: a song that starts just before midnight and ends just after it counts in
    /// the day it played, and that day goes out with the cut.
    @Test func aCutJustAfterMidnightCountsInTheDayItPlayed() {
        var s = playing()
        _ = events(&s, .position(0.5, generation: s.playGen), now: at(23, 59.95))  // 23:59:57
        // The music stopped, so the end itself rolls the day before out, with its cut.
        let sent = events(&s, .trackEnded(generation: s.playGen), now: at(0, 0.02, day: 20))  // 00:00:01
        guard case .dayActive(let day, _, _, _)? = sent.first else { Issue.record("no day_active"); return }
        #expect(day.day == 20261119 && day.songsCut == 1 && s.today == nil)
    }

    @Test func aDayWithOnlyACutStillHasUse() {
        var d = DayUse(day: 20261119, weekday: 5)
        d.songsCut = 1
        #expect(d.hadUse)
    }

    @Test func theCutCountGoesOutAndSaves() {
        var d = DayUse(day: 20261119, weekday: 5)
        d.songs = 2; d.songsCut = 1
        #expect(DayUse(saved: d.saved) == d && d.saved.hasSuffix("|0,0,1"))
        let p = BetaEvent.dayActive(d, service: .local, color: .silver).properties
        #expect(p["songs_cut"] == .number(1))
    }
}
