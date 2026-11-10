import Testing
@testable import ClasifyCore

/// Round 14 card BA: first-time hints. A wheel label glows, then a tip shows after 3 pulses.
@Suite struct HintTests {
    /// Signed in on the main menu, before any hint ended.
    func fresh() -> AppState {
        var s = mainMenu()
        s.hintsDone = []
        return s
    }

    /// Changes 139, 151 and 195: the MENU label glows on the first list, the tip shows after
    /// 7.2 s, and after 10 more seconds the hint ends for good.
    @Test func theMenuHintGlowsThenShowsItsTipThenEnds() {
        var s = fresh()
        #expect(s.hint == nil && s.hintDue == 0)  // not on the main menu
        send(&s, .wheel(1), .select, now: 199)
        #expect(s.top.screen == .playlists && s.top.loading && s.hint == nil)  // not while it loads
        send(&s, .playlistsLoaded(token: 1, playlists: [focusInfo]), now: 200)
        #expect(s.hint == .menu && s.hintAt == 200 && !s.hintTip && s.hintDue == 207.2)
        send(&s, .tick, now: 207.1)
        #expect(!s.hintTip)
        send(&s, .tick, now: 207.2)
        #expect(s.hint == .menu && s.hintTip && s.hintDue == 217.2)
        send(&s, .tick, now: 217.2)
        #expect(s.hint == nil && !s.hintTip && s.hintsDone == [.menu])  // never again
        send(&s, .menu, .select, now: 220)
        #expect(s.top.screen == .playlists && s.hint == nil)
    }

    /// Change 139: going deeper, the hint starts again on the next list. MENU ends it for good.
    @Test func theMenuHintMovesDeeperAndAMenuPressEndsIt() {
        var s = fresh()
        send(&s, .wheel(1), .select, .playlistsLoaded(token: 1, playlists: [focusInfo]), now: 200)
        send(&s, .tick, now: 207.2)
        #expect(s.hintTip)
        send(&s, .select, now: 208)  // Focus loads: the hint waits
        #expect(s.hint == nil && !s.hintTip && s.hintsDone.isEmpty)
        send(&s, .tracksLoaded(token: 2, playlist: "focus", tracks: focus.tracks), now: 209)
        #expect(s.hint == .menu && s.hintAt == 209 && !s.hintTip)
        send(&s, .menu, now: 210)
        #expect(s.top.screen == .playlists && s.hint == nil && s.hintsDone == [.menu])
    }

    /// Change 139: a MENU press before the hint shows ends it too.
    @Test func anEarlyMenuPressEndsTheMenuHint() {
        var s = fresh()
        send(&s, .wheel(1), .select, .menu)  // back while Playlists loads
        #expect(s.top.screen == .main && s.hint == nil && s.hintsDone == [.menu])
    }

    /// No hint during setup, and none before the login.
    @Test func noHintOnSetupScreens() {
        var s = AppState()
        send(&s, .launch, .restored(token: 1, ok: false), .select)  // the color pick, a list
        #expect(s.top.screen == .color && s.hint == nil)
        send(&s, .select)  // the login screen
        #expect(s.top.screen == .login && s.hint == nil)
    }

    /// A status toast waits while a hint shows, and shows when the hint ends.
    @Test func aToastWaitsForTheHint() {
        var s = fresh()
        send(&s, openFocus(1))
        #expect(s.hint == .menu)
        send(&s, .offline(true), .select)  // a song, offline
        #expect(s.toast == "" && s.heldToast == "You’re offline right now")
        send(&s, .menu, now: 101)
        #expect(s.hint == nil && s.toast == "You’re offline right now" && s.toastUntil == 102.8 && s.heldToast == "")
    }

    /// A sign-out drops the hint and the toast that waited for it: no toast on the login screen.
    @Test func aSignOutDropsTheHeldToast() {
        var s = fresh()
        send(&s, openFocus(1))
        send(&s, .offline(true), .select)
        #expect(s.hint == .menu && s.heldToast == "You’re offline right now")
        send(&s, .expire, now: 101)
        #expect(s.top.screen == .login && s.hint == nil && s.heldToast == "" && s.toast == "")
    }

    /// A hint does not start while a toast shows. It starts when the toast goes.
    @Test func aHintWaitsForAToast() {
        var s = fresh()
        s.toast = "You’re offline right now"; s.toastUntil = 101.8
        send(&s, openFocus(1))
        #expect(s.top.screen == .tracks(playlist: "focus") && s.hint == nil)
        send(&s, .tick, now: 102)
        #expect(s.toast == "" && s.hint == .menu && s.hintAt == 102)
    }

    /// Changes 176 and 177: after a song played 10 s on Now Playing, the play/pause label glows.
    /// A press ends it for good. The next hint waits for a later visit to Now Playing.
    @Test func thePlayThenTheNextHintShowOnNowPlaying() {
        var s = mainMenu()
        s.hintsDone = [.menu]
        send(&s, openFocus(1))
        send(&s, .select)
        #expect(s.top.screen == .now && s.hint == nil)
        send(&s, .position(9.5, generation: s.playGen), now: 300)
        #expect(s.hint == nil)
        send(&s, .position(10, generation: s.playGen), now: 301)
        #expect(s.hint == .playPause && s.hintAt == 301)
        send(&s, .tick, now: 308.2)
        #expect(s.hintTip)
        send(&s, .play, now: 309)  // pause
        #expect(s.hint == nil && !s.isPlaying && s.hintsDone == [.menu, .playPause])
        send(&s, .play, .position(20, generation: s.playGen), now: 310)
        #expect(s.isPlaying && s.hint == nil)  // not in the same visit
        send(&s, .menu, .wheel(1), .select, now: 311)  // another song: Now Playing again
        send(&s, .position(10, generation: s.playGen), now: 321)
        #expect(s.top.screen == .now && s.hint == .next && s.hintAt == 321)
        send(&s, .next, now: 322)
        #expect(s.hint == nil && s.hintsDone == Set(Hint.allCases))
    }

    /// The play hint shows only while a song plays and the wheel sets the volume. A scrub stops
    /// it, and it starts again after. A failure stops it, and its message shows at once.
    @Test func thePlayHintStopsForAScrubAndWhenPlaybackStops() {
        var s = mainMenu()
        s.hintsDone = [.menu]
        send(&s, openFocus(1))
        send(&s, .select, now: 299)
        send(&s, .position(10, generation: s.playGen), now: 300)  // after the play, for its new generation
        #expect(s.hint == .playPause)
        send(&s, .select, now: 301)  // the center: scrub
        #expect(s.nowMode == .scrub && s.hint == nil && s.hintsDone == [.menu])
        send(&s, .menu, now: 302)  // back to the volume
        #expect(s.nowMode == .volume && s.hint == .playPause && s.hintAt == 302)
        send(&s, .playbackFailed("Spotify stopped", generation: s.playGen), now: 303)
        #expect(!s.isPlaying && s.hint == nil && s.toast == "Spotify stopped" && s.heldToast.isEmpty)
        #expect(!s.hintsDone.contains(.playPause))
    }

    /// Off Now Playing, the play hint waits. A press before it shows ends it, and the next hint too.
    @Test func thePlayHintWaitsOffNowPlayingAndEarlyPressesEndThem() {
        var s = mainMenu()
        s.hintsDone = [.menu]
        send(&s, openFocus(1))
        send(&s, .select, .position(12, generation: 1))
        #expect(s.hint == .playPause)
        send(&s, .menu)
        #expect(s.hint == nil && !s.hintsDone.contains(.playPause))
        send(&s, .play, .play, .next)
        #expect(s.hintsDone == Set(Hint.allCases))
        send(&s, .wheel(1), .select, .position(30, generation: s.playGen))
        #expect(s.top.screen == .now && s.hint == nil)
    }

    /// A reset keeps the ended hints, as it keeps the settings, and drops the one that shows.
    @Test func aResetKeepsTheEndedHints() {
        var s = fresh()
        send(&s, openFocus(1))
        #expect(s.hint == .menu)
        send(&s, .reset)
        #expect(s.hint == nil && s.hintsDone.isEmpty)
        s.hintsDone = [.menu]
        send(&s, .reset)
        #expect(s.hintsDone == [.menu])
    }
}
