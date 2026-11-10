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

    /// A hint does not start while a toast shows. It starts when the toast goes.
    @Test func aHintWaitsForAToast() {
        var s = fresh()
        s.toast = "You’re offline right now"; s.toastUntil = 101.8
        send(&s, openFocus(1))
        #expect(s.top.screen == .tracks(playlist: "focus") && s.hint == nil)
        send(&s, .tick, now: 102)
        #expect(s.toast == "" && s.hint == .menu && s.hintAt == 102)
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
