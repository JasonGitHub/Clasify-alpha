import Testing
@testable import ClasifyCore

/// Round 14 card BA.2, change 238: the first-run hints as a queue right after setup. Play, then
/// Next, then MENU. Other input hides a hint, and it shows again after 3 s of rest.
@Suite struct TourTests {
    /// "You’re all set" at the end of a first setup, with Liked Songs read, at 110 s.
    func allSet(_ songs: [Track] = liked.tracks) -> AppState {
        var s = activatedMac()
        send(&s, .spotifyAppFound(true), .launch, .restored(token: 1, ok: false), .select)  // the color pick
        send(&s, .select, .select, .select, .authDone(token: 2, ok: true))
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

    /// A scrub bar keeps the Next hint away until it goes back to the time bar, 6 s later.
    @Test func aScrubKeepsTheNextHintAway() {
        var s = started()
        send(&s, .play, now: 112)
        send(&s, .select, now: 113)  // the scrub bar, until 119
        #expect(s.nowMode == .scrub && s.hint == nil && s.hintDue == 0)
        send(&s, .tick, now: 116)
        #expect(s.hint == nil)
        send(&s, .tick, now: 119.1)  // back to the time bar: the hint shows
        #expect(s.nowMode == .volume && s.hint == .tourNext && s.hintTip)
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

    /// CLA-163, card CE.1: the tour up to the MENU hint, at 208 s, with the hints trial on.
    func atMenuWithTrial(menuBar: Bool = true) -> AppState {
        var s = allSet()
        send(&s, .hintsTrial(true), now: 110.5)
        s.menuBar = menuBar
        send(&s, .select, now: 111)
        send(&s, .play, now: 201)
        send(&s, .next, now: 205)
        send(&s, .tick, now: 208)
        return s
    }

    /// CE.1 (Jason 00:32 JST 11-21): with the trial on, the turn hint comes after MENU. It
    /// shows after 3 s of rest under the device (not on it), and no timer ends it. Other input
    /// hides it, and it comes back after 3 s of rest. The first ⌘ turn ends it for good. The
    /// menu bar hint comes last: the icon glows 0.6 s after the turn lands, and its device label
    /// shows at 3 s (card CE look A), until the icon's first click.
    @Test func theTurnHintThenTheMenuBarHintComeAfterMenu() {
        var s = atMenuWithTrial()
        #expect(s.hintsTrial && s.hint == .tourMenu)
        #expect(s.tourSteps == [.tourPlay, .tourNext, .tourMenu, .tourTurn, .tourMenuBar])
        send(&s, .menu, now: 209)
        #expect(s.top.screen == .main && s.tourOn && s.tour == .tourTurn && s.hint == nil && s.hintDue == 212)
        send(&s, .tick, now: 212)
        #expect(s.hint == .tourTurn && s.hintTip && s.hintDue == 0 && !Hint.tourTurn.onDevice)
        send(&s, .tick, now: 400)
        #expect(s.hint == .tourTurn)  // no timer ends it, and the menu bar hint waits
        send(&s, .wheel(1), now: 401)
        #expect(s.hint == nil && s.tourHides[.tourTurn] == 1)
        send(&s, .tick, now: 404)
        #expect(s.hint == .tourTurn)
        send(&s, .deviceTurned(true), now: 405)
        #expect(s.tourOn && s.tour == .tourMenuBar && s.hint == nil && s.hintsDone.contains(.tourTurn))
        #expect(s.settings.hintsDone.contains(.tourTurn) && s.settings.tourOn)
        send(&s, .deviceTurned(false), now: 406)
        #expect(s.hint == nil && s.hintDue == 406.6)  // the turn is input: the hint waits for rest after it lands
        send(&s, .tick, now: 406.6)
        #expect(s.hint == .tourMenuBar && !s.hintTip && s.hintDue == 409 && !Hint.tourMenuBar.onDevice && s.hintOnDevice)
        send(&s, .tick, now: 409)
        #expect(s.hintTip && s.hintTipAt == 409 && s.hintDue == 0)
        send(&s, .tick, now: 500)
        #expect(s.hint == .tourMenuBar)  // no timer ends it
        #expect(send(&s, .menuBarClick(shown: true), now: 501) == [.hideWindow])  // 388: it hides myPod as always
        #expect(!s.tourOn && s.tour == nil && s.hint == nil && s.hintsDone.isSuperset(of: [.tourTurn, .tourMenuBar]))
        #expect(s.settings.hintsDone.contains(.tourMenuBar) && !s.settings.tourOn)
    }

    /// CE.1: other input hides the menu bar hint, and it comes back after 3 s of rest. After
    /// 3 hides while its label shows, it is done.
    @Test func theMenuBarHintHidesThreeTimes() {
        var s = atMenuWithTrial()
        send(&s, .menu, now: 209)
        send(&s, .deviceTurned(true), now: 210)
        send(&s, .tick, now: 214)  // a long turn: no hint while the device is turned (Codex on #375)
        #expect(s.tour == .tourMenuBar && s.hint == nil && s.hintDue == 0)
        send(&s, .deviceTurned(false), now: 215)
        #expect(s.tour == .tourMenuBar && s.hintDue == 215.6 && s.tourHides[.tourMenuBar] == nil)
        var t = 215.0
        for n in 1...3 {
            send(&s, .tick, now: t + 0.6)
            send(&s, .tick, now: t + 3)
            #expect(s.hint == .tourMenuBar && s.hintTip)
            t += 4
            send(&s, .wheel(1), now: t)
            #expect(s.hint == nil && s.tourHides[.tourMenuBar] == n)
        }
        #expect(!s.tourOn && s.tour == nil && s.hintsDone.contains(.tourMenuBar))
    }

    /// 389: with the Menu Bar setting off there is no icon, so the tour ends with the turn
    /// hint. With the trial off, it is as before.
    @Test func noMenuBarHintWithTheIconOffOrTheTrialOff() {
        var s = atMenuWithTrial(menuBar: false)
        #expect(s.tourSteps == [.tourPlay, .tourNext, .tourMenu, .tourTurn])
        send(&s, .menu, now: 209)
        #expect(s.tourOn && s.tour == .tourTurn)
        var off = s
        send(&s, .deviceTurned(true), now: 210)
        #expect(!s.tourOn && s.tour == nil && !s.hintsDone.contains(.tourMenuBar))
        send(&off, .hintsTrial(false), now: 210)
        #expect(!off.hintsTrial && off.tourSteps == [.tourPlay, .tourNext, .tourMenu])
        #expect(!off.tourOn && off.tour == nil)
    }

    /// CE.1: a tour that ended before the trial goes on with the turn step when the trial is
    /// on, then the menu bar step. A click on the icon before its hint shows ends it too.
    @Test func aDoneTourGoesOnWithTheTrial() {
        var s = mainMenu()
        s.hintsDone = [.tourPlay, .tourNext, .tourMenu, .menu, .playPause, .next]
        send(&s, .hintsTrial(true), now: 150)
        #expect(s.tourOn && s.tour == .tourTurn && s.hintDue == 153)
        send(&s, .deviceTurned(true), now: 151)
        send(&s, .deviceTurned(false), now: 152)
        #expect(s.tour == .tourMenuBar && s.hint == nil && s.hintsDone.contains(.tourTurn))
        send(&s, .menuBarClick(shown: true), now: 153)
        #expect(!s.tourOn && s.hint == nil && s.hintsDone.contains(.tourMenuBar))
        send(&s, .tick, now: 160)
        #expect(!s.tourOn && s.hint == nil)
    }

    /// Card CE look A (the default, Jason 16:23 JST 11-21): the menu bar hint also has a device
    /// label. Like Play, the icon glows first and the words come 2.4 s later. Other input hides
    /// both, and they come back. The first icon click ends it.
    @Test func theMenuBarHintHasADeviceLabelLikePlay() {
        var s = mainMenu()
        s.hintsDone = [.tourPlay, .tourNext, .tourMenu, .tourTurn, .menu, .playPause, .next]
        send(&s, .hintsTrial(true), now: 150)
        #expect(s.tour == .tourMenuBar && s.hintDue == 150.6)
        send(&s, .tick, now: 150.6)  // the glow at 0.6 s of rest
        #expect(s.hint == .tourMenuBar && !s.hintTip && s.hintOnDevice && s.hintDue == 153)
        send(&s, .tick, now: 153)  // the label at 3.0 s
        #expect(s.hintTip && s.hintTipAt == 153 && s.hintDue == 0)
        send(&s, .wheel(1), now: 154)
        #expect(s.hint == nil && s.tourHides[.tourMenuBar] == 1 && s.hintDue == 154.6)
        send(&s, .tick, now: 154.6)
        send(&s, .tick, now: 157)
        #expect(s.hint == .tourMenuBar && s.hintTip)
        send(&s, .menuBarClick(shown: true), now: 158)
        #expect(!s.tourOn && s.hint == nil && s.hintsDone.contains(.tourMenuBar) && !s.hintOnDevice)
        #expect(s.glowsFirst(.tourMenuBar) && s.glowsFirst(.tourPlay) && !s.glowsFirst(.tourNext))
    }

    /// The menu bar label waits for a Shuffle or Repeat slider to hide (Codex on #377): the glow
    /// comes 2.4 s before the slider's end, and the label when it ends.
    @Test func theMenuBarLabelWaitsForTheSlider() {
        var s = mainMenu()
        s.hintsDone = [.tourPlay, .tourNext, .tourMenu, .tourTurn, .menu, .playPause, .next]
        s.overlayUntil = 160
        send(&s, .hintsTrial(true), now: 150)
        #expect(s.tour == .tourMenuBar && s.tourShowAt == 157.6)
        s.overlayUntil = 0
        #expect(s.tourShowAt == 150.6)
    }

    /// CE.1: after 3 hides the turn hint is done. It does not show on About.
    @Test func theTurnHintHidesThreeTimesAndWaitsOffAbout() {
        var s = atMenuWithTrial(menuBar: false)
        send(&s, .menu, now: 209)
        var t = 209.0
        for n in 1...3 {
            send(&s, .tick, now: t + 3)
            #expect(s.hint == .tourTurn)
            t += 4
            send(&s, .wheel(1), now: t)
            #expect(s.hint == nil && s.tourHides[.tourTurn] == n)
        }
        #expect(!s.tourOn && s.hintsDone.contains(.tourTurn))

        // With the icon on, 3 hides end the turn hint too, and then the menu bar hint comes.
        var m = atMenuWithTrial()
        send(&m, .menu, now: 209)
        t = 209.0
        for _ in 1...3 {
            send(&m, .tick, now: t + 3)
            t += 4
            send(&m, .wheel(1), now: t)
        }
        #expect(m.tourHides[.tourTurn] == 3 && m.tour == .tourMenuBar && m.hint == nil)
        send(&m, .tick, now: t + 3)
        #expect(m.hint == .tourMenuBar)

        var a = atMenuWithTrial(menuBar: false)
        send(&a, .menu, now: 209)
        a.stack.append(Frame(screen: .about))
        send(&a, .tick, now: 230)
        #expect(a.tour == .tourTurn && !a.tourPlace && a.hint == nil)
    }
}
