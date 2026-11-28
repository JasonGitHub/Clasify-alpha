import Foundation
import Testing
@testable import ClasifyCore

/// CLA-203: `app_closed` says this launch's play use: starts and stops of the music by any way,
/// myPod skips, the longest pause, losses of control while playing or paused, and outside music.
@Suite struct LaunchUseTests {
    func events(_ s: inout AppState, _ action: Action, now: Double) -> [BetaEvent] {
        reduce(&s, action, Dependencies(now: { now }, random: { _ in 0 })).compactMap { (fx: Effect) -> BetaEvent? in
            if case .track(let event) = fx { return event }
            return nil
        }
    }

    func playing() -> AppState {
        var s = mainMenu()
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "l0"); s.isPlaying = true
        return s
    }

    @Test func pressesSkipsAndTheLongestPauseCount() {
        var s = playing()
        _ = events(&s, .play, now: 100)  // pause
        _ = events(&s, .play, now: 130)  // play: a 30 s pause
        _ = events(&s, .next, now: 131)
        _ = events(&s, .prev, now: 132)
        _ = events(&s, .play, now: 140)  // pause
        _ = events(&s, .play, now: 150)  // play: 10 s
        #expect(s.launchUse.plays == 2 && s.launchUse.pauses == 2 && s.launchUse.skips == 2)
        #expect(s.launchUse.longestPause == 30 && s.launchUse.pausedAt == nil)
    }

    /// CTO: a start or a stop on another device counts; a new song while music plays is no start;
    /// a loss of control is a stop, not a pause.
    @Test func startsAndStopsFromAnyWayCount() {
        var s = playing()
        _ = events(&s, .trackChanged("l1", playing: true, generation: s.playGen), now: 10)  // a new song: no start
        _ = events(&s, .trackChanged("l1", playing: false, generation: s.playGen), now: 20)  // paused on the phone
        _ = events(&s, .trackChanged("l1", playing: true, generation: s.playGen), now: 45)  // played on the phone
        #expect(s.launchUse.plays == 1 && s.launchUse.pauses == 1 && s.launchUse.longestPause == 25)
        _ = events(&s, .controlLost(.stoppedInSpotify), now: 50)
        #expect(s.launchUse.pauses == 1 && s.launchUse.stopsPlaying == 1)
    }

    @Test func aLossCountsAsPlayingOrPausedOnce() {
        var s = playing()
        _ = events(&s, .controlLost(.stoppedInSpotify), now: 10)
        _ = events(&s, .controlLost(.stoppedInSpotify), now: 11)  // the same loss: not again
        _ = events(&s, .controlBack, now: 12)
        s.isPlaying = false
        _ = events(&s, .controlLost(.stoppedInSpotify), now: 20)
        #expect(s.launchUse.stopsPlaying == 1 && s.launchUse.stopsPaused == 1)
    }

    @Test func theQuitEndsAnOpenPauseAndSendsTheCounts() {
        var s = playing()
        _ = events(&s, .play, now: 100)  // pause
        _ = events(&s, .outsideMusic(playing: true, song: true), now: 200)
        _ = events(&s, .outsideMusic(playing: false, song: false), now: 260)
        let sent = events(&s, .willQuit(openSeconds: 600), now: 400.4)
        guard let closed = sent.first(where: { $0.name == "app_closed" }) else { Issue.record("no app_closed"); return }
        let p = closed.properties
        #expect(p["pauses"] == .number(1) && p["plays"] == .number(0) && p["longest_pause_s"] == .number(300))
        #expect(p["outside_music_s"] == .number(60) && p["stops_playing"] == .number(0) && p["skips"] == .number(0))
    }

    @Test func aSkipWithNoSongDoesNotCount() {
        var s = mainMenu()
        _ = events(&s, .next, now: 1)
        #expect(s.launchUse.skips == 0)
    }
}
