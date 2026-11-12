import Testing
@testable import ClasifyCore

/// Round 14 card BA.2, change 238: the first-run hints as a queue right after setup. Play, then
/// Next, then MENU. Other input hides a hint, and it shows again after 3 s of rest.
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

    /// On the main menu at 111 s, with the queue started and the Play hint not shown yet.
    func started() -> AppState {
        var s = allSet()
        send(&s, .select, now: 111)
        return s
    }

    /// Picks the first song of the selected list on the main menu, with reads that end at once.
    func pickASong(_ s: inout AppState, now: Double) {
        send(&s, .select, now: now)
        if s.top.loading { send(&s, .playlistsLoaded(token: s.top.token, playlists: [focusInfo]), now: now) }
        send(&s, .select, now: now)
        if s.top.loading, case .tracks(playlist: let id) = s.top.screen {
            send(&s, .tracksLoaded(token: s.top.token, playlist: id, tracks: id == "focus" ? focus.tracks : liked.tracks), now: now)
        }
        send(&s, .select, now: now)
    }

    @Test func theQueueGoesPlayThenNextThenMenu() {
        var s = allSet()
        #expect(s.top.screen == .yourMusic && s.setupDone && !s.tourOn && s.tour == nil && s.hint == nil)
        send(&s, .select, now: 111)  // on to the main menu: the queue starts, once ever
        #expect(s.top.screen == .main && s.tourOn && s.tour == .tourPlay && s.hint == nil && s.hintDue == 111.6)
        send(&s, .tick, now: 111.6)  // Play glows at 0.6 s of rest
        #expect(s.hint == .tourPlay && s.hintAt == 111.6 && !s.hintTip && s.hintDue == 114)
        send(&s, .tick, now: 114)  // its words at 3.0 s, with no time-out
        #expect(s.hintTip && s.hintTipAt == 114 && s.hintDue == 0)
        send(&s, .tick, now: 200)
        #expect(s.hint == .tourPlay && s.hintTip)

        send(&s, .play, now: 201)  // Liked Songs plays on Now Playing
        #expect(s.top.screen == .now && s.isPlaying && s.tour == .tourNext && s.hint == nil && s.hintDue == 204)
        send(&s, .tick, now: 204)  // Next and its words at 3.0 s
        #expect(s.hint == .tourNext && s.hintTip && s.hintAt == 204 && s.hintTipAt == 204 && s.hintDue == 0)

        send(&s, .next, now: 205)
        #expect(s.tour == .tourMenu && s.hint == nil)
        send(&s, .tick, now: 208)
        #expect(s.hint == .tourMenu && s.hintTip)

        send(&s, .menu, now: 209)  // back one screen: the queue is done for good, the BA hints too
        #expect(s.top.screen == .main && !s.tourOn && s.tour == nil && s.hint == nil)
        #expect(s.hintsDone == [.tourPlay, .tourNext, .tourMenu, .menu, .playPause, .next])
        #expect(s.settings.hintsDone == s.hintsDone && !s.settings.tourOn)
    }

    /// The wheel hides the Play hint. It shows again after 3 s with no input. A turn before
    /// its words show does not count as a hide.
    @Test func theWheelHidesPlayAndItComesBack() {
        var s = started()
        send(&s, .tick, now: 111.6)
        send(&s, .tick, now: 114)
        #expect(s.hint == .tourPlay && s.hintTip)
        send(&s, .wheel(1), now: 115)
        #expect(s.hint == nil && s.tour == .tourPlay && s.tourHides == [.tourPlay: 1] && s.hintDue == 115.6)
        send(&s, .tick, now: 115.6)
        #expect(s.hint == .tourPlay && !s.hintTip)
        send(&s, .wheel(-1), now: 116)  // only the glow showed
        #expect(s.hint == nil && s.tourHides == [.tourPlay: 1])
        send(&s, .tick, now: 116.6)
        send(&s, .tick, now: 119)  // back, words and all, 3 s after the last input
        #expect(s.hint == .tourPlay && s.hintTip && s.hintTipAt == 119)
    }

    /// A Play press moves the queue to Next, also before the Play hint shows.
    @Test func aPlayPressMovesToNext() {
        var s = started()
        send(&s, .play, now: 111.2)
        #expect(s.hintsDone.contains(.tourPlay) && s.tour == .tourNext && s.top.screen == .now && s.hint == nil)
        send(&s, .tick, now: 114.2)
        #expect(s.hint == .tourNext)
    }

    /// Music that started another way, here a song picked in a list, ends the Play step too.
    /// A MENU press that went back before, early, skips the MENU hint.
    @Test func anEarlyMenuThenAPickedSongGoesToNextAndSkipsMenu() {
        var s = started()
        send(&s, .wheel(1), .select, now: 112)  // Playlists
        send(&s, .menu, now: 113)  // back one screen, early
        #expect(s.top.screen == .main && s.hintsDone.contains(.tourMenu) && s.tour == .tourPlay)
        pickASong(&s, now: 114)
        #expect(s.top.screen == .now && s.isPlaying && s.tour == .tourNext && s.hint == nil)
        send(&s, .tick, now: 117)
        #expect(s.hint == .tourNext)
        send(&s, .next, now: 118)  // Next was the last step left
        #expect(!s.tourOn && s.tour == nil && s.hint == nil && s.hintsDone.isSuperset(of: [.tourNext, .menu, .playPause, .next]))
    }

    /// A hint hidden 3 times while its words showed is done, and the queue moves on.
    @Test func playHiddenThreeTimesIsDone() {
        var s = started()
        var t = 111.0
        for n in 1...3 {
            send(&s, .tick, now: t + 0.6)
            send(&s, .tick, now: t + 3)
            #expect(s.hint == .tourPlay && s.hintTip)
            t += 4
            send(&s, .toggleShuffle, now: t)
            #expect(s.hint == nil && s.tourHides[.tourPlay] == n)
        }
        #expect(s.hintsDone.contains(.tourPlay) && s.tour == .tourNext && s.tourOn)
        #expect(s.settings.tourHides == [.tourPlay: 3])
        send(&s, .tick, now: t + 10)
        #expect(s.top.screen == .main && s.hint == nil)  // Next waits for Now Playing
    }

    /// Next and Previous both end the Next step. A MENU press that does not go back does not
    /// end the MENU step.
    @Test func previousEndsNextAndMenuMustGoBack() {
        var s = started()
        send(&s, .play, now: 112)
        send(&s, .prev, now: 113)
        #expect(s.tour == .tourMenu)
        send(&s, .select, now: 114)  // the scrub bar
        send(&s, .menu, now: 115)  // back to the volume, on the same screen
        #expect(s.top.screen == .now && s.tour == .tourMenu)
        send(&s, .tick, now: 118)
        #expect(s.hint == .tourMenu)
    }

    /// Only after the first setup: not when the tour ran before, and not on a later launch.
    @Test func theQueueStartsOnce() {
        var s = allSet()
        s.hintsDone = [.tourPlay]  // the BA.1 tour ran
        send(&s, .select, now: 111)
        #expect(s.top.screen == .main && !s.tourOn && s.tour == nil && s.hintDue == 0)
        #expect(mainMenu().tour == nil)
    }

    /// The Play step starts Liked Songs, also over a paused song that Spotify had at the start.
    /// Music that already plays ends the Play step at once.
    @Test func playStartsLikedSongsOverAnAdoptedSong() {
        var s = allSet()
        send(&s, .adopted(track: "x9", playlist: nil, playing: false, position: 30, generation: s.playGen), now: 110.5)
        send(&s, .select, now: 111)
        #expect(s.tour == .tourPlay && s.current != nil)
        send(&s, .play, now: 112)
        #expect(s.top.screen == .now && s.isPlaying && s.current?.playlist == Playlist.likedSongsID && s.tour == .tourNext)

        s = allSet()
        send(&s, .adopted(track: "x9", playlist: nil, playing: true, position: 30, generation: s.playGen), now: 110.5)
        send(&s, .select, now: 111)
        #expect(s.tourOn && s.tour == .tourNext)
    }

    /// A toast goes first: the tip gives way, and it comes back after the toast. A sign-out
    /// hides the hint, and the queue stays for the next login.
    @Test func aToastGoesFirstAndASignOutKeepsTheQueue() {
        var s = started()
        send(&s, .play, now: 112)
        send(&s, .tick, now: 115)
        #expect(s.hint == .tourNext)
        send(&s, .playbackFailed("Spotify closed", generation: s.playGen), now: 116)
        #expect(s.tour == .tourNext && s.hint == nil && s.toast == "Spotify closed")
        #expect(s.hintDue == 0)  // nothing is due while the toast shows
        send(&s, .tick, now: 118)
        #expect(s.toast.isEmpty && s.hint == .tourNext)

        send(&s, .expire, now: 119)
        #expect(s.top.screen == .login && s.hint == nil && s.tourOn && s.tour == .tourNext && s.hintDue == 0)
    }
}
