import Testing
@testable import ClasifyCore

/// Round 14 card BA.1, change 199: the first-run tour right after setup. Play, then Next, then
/// MENU, each with a glow and a tip.
@Suite struct TourTests {
    /// "You’re all set" at the end of a first setup, with Liked Songs read, at 110 s.
    func allSet(_ songs: [Track] = liked.tracks) -> AppState {
        var s = AppState()
        send(&s, .launch, .restored(token: 1, ok: false), .select)  // the color pick
        send(&s, .select, .select, .authDone(token: 2, ok: true))
        send(&s, .tick, now: 101.5)
        send(&s, .playlistsRefreshed([focusInfo]), now: 106)
        send(&s, .tracksLoaded(token: 1, playlist: Playlist.likedSongsID, tracks: songs), now: 110)
        return s
    }

    @Test func theTourGoesPlayThenNextThenMenu() {
        var s = allSet()
        #expect(s.top.screen == .yourMusic && s.setupDone && s.tour == nil && s.hint == nil)
        send(&s, .select, now: 111)  // on to the main menu: the tour starts, once ever
        #expect(s.top.screen == .main && s.tour == .tourPlay && s.hint == .tourPlay && s.hintAt == 111)
        #expect(!s.hintTip && s.hintDue == 113.4 && s.hintsDone == [.tourPlay])
        send(&s, .tick, now: 113.4)  // the tip after 1 pulse, and no time-out
        #expect(s.hintTip && s.hintTipAt == 113.4 && s.hintDue == 0)
        send(&s, .tick, now: 200)
        #expect(s.hint == .tourPlay && s.hintTip)

        send(&s, .play, now: 201)  // Liked Songs plays on Now Playing
        #expect(s.top.screen == .now && s.isPlaying && s.tour == .tourNext && s.hint == nil)
        send(&s, .position(2.9, generation: s.playGen), now: 204)
        #expect(s.hint == nil)
        send(&s, .position(3, generation: s.playGen), now: 205)  // 3 s of music: step 2, tip at once
        #expect(s.hint == .tourNext && s.hintTip && s.hintAt == 205 && s.hintTipAt == 205 && s.hintDue == 0)

        let from = s.current
        send(&s, .next, now: 206)  // the tip stays until the new song shows
        #expect(s.tour == .tourMenu && s.tourFrom == from && s.hint == .tourNext)
        send(&s, .trackChanged("l1", playing: true, generation: s.playGen), now: 207)
        #expect(s.current != from && s.hint == .tourMenu && s.hintTip && s.hintAt == 207)

        send(&s, .menu, now: 208)  // back to the main menu: done for good, the BA hints too
        #expect(s.top.screen == .main && s.tour == nil && s.hint == nil)
        #expect(s.hintsDone == [.tourPlay, .tourNext, .menu, .playPause, .next])
    }

    /// Any other input ends the tour quietly, for good. The BA hints stay to show later.
    @Test func anotherInputEndsTheTour() {
        var s = allSet()
        send(&s, .select, .wheel(1), now: 111)
        #expect(s.top.screen == .main && s.tour == nil && s.hint == nil && s.hintsDone == [.tourPlay])

        s = allSet()
        send(&s, .select, now: 111)
        send(&s, .play, now: 112)
        send(&s, .position(5, generation: s.playGen), now: 113)
        #expect(s.hint == .tourNext)
        send(&s, .play, now: 114)  // pause, not Next
        #expect(s.tour == nil && s.hint == nil && !s.hintsDone.contains(.next) && !s.hintsDone.contains(.menu))
    }

    /// Previous after 3 s starts the same song again, so step 3 shows at once.
    @Test func previousMovesOnToo() {
        var s = allSet()
        send(&s, .select, now: 111)
        send(&s, .play, now: 112)
        send(&s, .position(5, generation: s.playGen), now: 113)
        send(&s, .prev, now: 114)
        #expect(s.t == 0 && s.tour == .tourMenu && s.tourFrom == nil && s.hint == .tourMenu)
    }

    /// Only after the first setup: not when the tour ran before, and not on a later launch.
    @Test func theTourRunsOnce() {
        var s = allSet()
        s.hintsDone = [.tourPlay]
        send(&s, .select, now: 111)
        #expect(s.top.screen == .main && s.tour == nil && s.hint == nil)
        #expect(mainMenu().tour == nil)
    }

    /// The tour's Play starts Liked Songs, also when Spotify already had a song at the start.
    @Test func playStartsLikedSongsOverAnAdoptedSong() {
        var s = allSet()
        send(&s, .adopted(track: "x9", playlist: nil, playing: true, position: 30, generation: s.playGen), now: 110.5)
        send(&s, .select, now: 111)
        #expect(s.tour == .tourPlay && s.current != nil)
        send(&s, .play, now: 112)
        #expect(s.top.screen == .now && s.isPlaying && s.current?.playlist == Playlist.likedSongsID && s.tour == .tourNext)
    }

    /// With no liked songs, Play has nothing to start, so the tour ends.
    @Test func noLikedSongsEndsTheTour() {
        var s = allSet([])
        send(&s, .select, now: 111)
        #expect(s.tour == .tourPlay)
        send(&s, .play, now: 112)
        #expect(s.top.screen == .main && s.tour == nil && s.hint == nil)
    }

    /// Offline, a press shows its toast. The step stays, and its hint comes back after the toast.
    /// A sign-out ends the tour.
    @Test func offlineTheStepStaysAndASignOutEndsTheTour() {
        var s = allSet()
        send(&s, .select, now: 111)
        send(&s, .offline(true), .play, now: 112)
        #expect(s.tour == .tourPlay && s.hint == nil && !s.toast.isEmpty)
        send(&s, .tick, now: 120)
        #expect(s.tour == .tourPlay && s.hint == .tourPlay)
        send(&s, .offline(false), .play, now: 121)
        send(&s, .position(5, generation: s.playGen), now: 122)
        #expect(s.hint == .tourNext)
        send(&s, .offline(true), .next, now: 123)
        #expect(s.tour == .tourNext && s.hint == nil && !s.toast.isEmpty)
        send(&s, .tick, now: 130)
        #expect(s.tour == .tourNext && s.hint == .tourNext)
        send(&s, .offline(false), .next, now: 131)
        #expect(s.tour == .tourMenu)

        // Spotify closed: the tip gives way to the toast and comes back after it.
        send(&s, .playbackFailed("Spotify closed", generation: s.playGen), now: 132)
        #expect(s.tour == .tourMenu && s.hint == nil && s.toast == "Spotify closed")
        send(&s, .tick, now: 140)
        #expect(s.hint == .tourNext)

        s = allSet()
        send(&s, .select, now: 111)
        send(&s, .expire, now: 112)
        #expect(s.tour == nil && s.hint == nil)
    }
}
