import Testing
@testable import ClasifyCore

/// Card BM (CLA-103): the Settings "Service" row, and the switch between Spotify and Apple Music.
@Suite struct ServiceSwitchTests {
    /// Opens Settings from the main menu. The Service row is the first row (change 256).
    func openSettings(_ s: inout AppState) {
        for _ in 0..<8 where s.top.screen != .main { send(&s, .menu) }
        s.top.sel = s.rows(for: s.top).firstIndex(of: .settings) ?? -1
        send(&s, .select)
    }

    /// Change 256: each Select flips the shown value, like Shuffle. Nothing switches until
    /// the user leaves Settings, and back on the old value nothing happens.
    @Test func serviceRowFlipsAndNothingHappensOnTheOldValue() {
        var s = playing()
        openSettings(&s)
        #expect(s.top.screen == .settings && s.rows(for: s.top).first == .service && s.top.sel == 0)
        #expect(send(&s, .select) == [])
        #expect(s.pendingService == .appleMusic && s.service == .spotify && s.isPlaying)
        send(&s, .select)
        #expect(s.pendingService == .spotify)
        #expect(send(&s, .menu) == [])  // back on Spotify: nothing happens
        #expect(s.top.screen == .main && s.pendingService == nil && s.isPlaying && s.service == .spotify)
    }

    /// Change 260: leaving Settings with the other service stops the old one and clears its
    /// library. The new service is set before its login, and nothing plays by itself. With
    /// its stored login, its main menu opens at the top.
    @Test func leavingSettingsSwitchesTheService() {
        var s = playing()
        openSettings(&s)
        send(&s, .select)
        let fx = send(&s, .menu)
        #expect(fx == [.stop, .setService(.appleMusic), .restoreSession(token: s.authAttempt)])
        #expect(s.service == .appleMusic && s.pendingService == nil)
        #expect(s.current == nil && !s.isPlaying)
        #expect(s.library.isEmpty && !s.signedIn)
        #expect(s.top.screen == .login && s.restoring)  // "Signing in…"
        send(&s, .restored(token: s.authAttempt, ok: true))
        #expect(s.stack.count == 1 && s.top.screen == .main && s.top.sel == 0)
        #expect(s.current == nil && !s.isPlaying && s.signedIn)  // no empty Now Playing
        // Back to Spotify the same way.
        openSettings(&s)
        send(&s, .select)
        #expect(send(&s, .menu) == [.setService(.spotify), .restoreSession(token: s.authAttempt)])
        #expect(s.service == .spotify)
    }

    /// Change 256: a service with no stored login shows its login screen after the switch.
    @Test func aServiceWithNoLoginShowsItsLogin() {
        var s = mainMenu()
        openSettings(&s)
        send(&s, .select, .menu)
        send(&s, .restored(token: s.authAttempt, ok: false))
        #expect(s.stack.count == 1 && s.top.screen == .login && !s.restoring && !s.signedIn)
        #expect(s.service == .appleMusic)
    }

    /// A press that was not applied does not stay for the next time Settings opens.
    @Test func anOldPressDoesNotStay() {
        var s = mainMenu()
        openSettings(&s)
        send(&s, .select)
        send(&s, .expire)  // the session ended while Settings showed
        #expect(s.pendingService == nil && s.service == .spotify)
        s = mainMenu()
        s.pendingService = .appleMusic  // as if left from before
        openSettings(&s)
        #expect(s.pendingService == nil)
    }

    /// Change 257: the first run picks the service after the color. Apple Music asks macOS at
    /// once, over this screen (258); after Allow, "You’re in" as after a Spotify login.
    @Test func pickYourMusicAsksMacOSForAppleMusic() {
        var s = afterSetup()
        s.setupDone = false
        send(&s, .launch, .restored(token: 1, ok: false), .select, .select)  // Hello, the color
        #expect(s.top.screen == .pickMusic)
        #expect(s.rows(for: s.top) == [.pickService(.spotify), .pickService(.appleMusic)])
        #expect(s.top.sel == 0)
        #expect(send(&s, .wheel(1), .select) == [.setService(.appleMusic), .logIn(token: 2)])
        #expect(s.service == .appleMusic && s.top.screen == .pickMusic)
        #expect(s.top.token == 2 && s.top.sel == 1)
        send(&s, .authDone(token: 2, ok: false))  // the prompt failed: a press asks again
        #expect(s.top.screen == .pickMusic && s.top.token == 0)
        #expect(send(&s, .select) == [.logIn(token: 3)])  // the service is set already
        send(&s, .authDone(token: 3, ok: true))
        #expect(s.top.screen == .loggedIn && s.signedIn)
    }

    /// Change 258: after "Don't Allow", Access is off. MENU does nothing; "Open Settings"
    /// opens System Settings, and "Use Spotify" switches to Spotify (262).
    @Test func accessOffOpensSettingsOrUsesSpotify() {
        var s = afterSetup()
        s.setupDone = false
        send(&s, .launch, .restored(token: 1, ok: false), .select, .select, .wheel(1), .select)
        send(&s, .accessDenied(token: 1))  // an older attempt
        #expect(s.top.screen == .pickMusic)
        #expect(send(&s, .accessDenied(token: 2)) == [])
        #expect(s.stack == [Frame(screen: .accessOff)])
        #expect(s.rows(for: s.top) == [.openPrivacy, .useSpotify])
        #expect(send(&s, .menu) == [] && s.top.screen == .accessOff)
        #expect(send(&s, .select) == [.openPrivacy])
        #expect(send(&s, .wheel(1), .select) == [.setService(.spotify), .restoreSession(token: 4)])
        #expect(s.service == .spotify && s.top.screen == .login && s.restoring)
    }

    /// Back from System Settings, Access is off checks again: still no access, it stays; with
    /// access, it goes on to the main menu.
    @Test func accessOffChecksAgainWhenClasifyComesBack() {
        var s = mainMenu()
        openSettings(&s)
        send(&s, .select, .menu)
        send(&s, .accessDenied(token: s.authAttempt))
        let token = s.authAttempt + 1
        #expect(send(&s, .activated) == [.restoreSession(token: token)])
        #expect(s.restoring && send(&s, .activated) == [])  // one check at a time
        send(&s, .accessDenied(token: token))
        #expect(s.stack == [Frame(screen: .accessOff)])
        #expect(!s.restoring)
        send(&s, .activated)
        send(&s, .restored(token: s.authAttempt, ok: true))
        #expect(s.stack == [Frame(screen: .main)] && s.signedIn)
    }

    /// A switch to Apple Music with no access ends on Access is off too, never on a dead end.
    @Test func aSwitchWithNoAccessShowsAccessOff() {
        var s = mainMenu()
        openSettings(&s)
        send(&s, .select, .menu)
        send(&s, .accessDenied(token: s.authAttempt))
        #expect(s.stack == [Frame(screen: .accessOff)])
        #expect(!s.restoring && !s.signedIn)
    }

    /// Change 259: no subscription shows the Premium screen with Apple Music's words, and
    /// "Use Spotify" in place of "Log out".
    @Test func noSubscriptionOffersUseSpotify() {
        var s = mainMenu()
        openSettings(&s)
        send(&s, .select, .menu)
        send(&s, .notPremium(token: s.authAttempt))
        #expect(s.stack == [Frame(screen: .premium)])
        #expect(s.rows(for: s.top) == [.checkPremium, .getPremium, .useSpotify])
        #expect(send(&s, .wheel(2), .select).contains(.setService(.spotify)))
    }

    /// Change 263: Log out on Apple Music stops the music, clears the library and goes back
    /// to Pick Your Music, on Apple Music. Spotify there uses its stored login, if any.
    @Test func logOutOnAppleMusicGoesToPickYourMusic() {
        var s = mainMenu()
        openSettings(&s)
        send(&s, .select, .menu)
        send(&s, .restored(token: s.authAttempt, ok: true))
        openSettings(&s)
        s.top.sel = s.rows(for: s.top).firstIndex(of: .logOut) ?? -1
        #expect(send(&s, .select, .wheel(1), .select) == [.logOut])
        #expect(s.stack.count == 1 && s.top.screen == .pickMusic && s.top.sel == 1)
        #expect(!s.signedIn && s.library.isEmpty)
        let fx = send(&s, .wheel(-1), .select)
        #expect(fx == [.setService(.spotify), .restoreSession(token: s.authAttempt)])
        #expect(s.top.screen == .login && s.restoring)
    }

    /// `.libraryWords`: the texts follow the active service's library. A reset keeps them.
    @Test func libraryWordsSetTheTexts() {
        var s = mainMenu()
        #expect(s.words == .spotify && s.likedSongsName == "Liked Songs")
        #expect(send(&s, .libraryWords(.appleMusic)) == [])
        #expect(s.words == .appleMusic && s.likedSongsName == "Favorite Songs")
        send(&s, .reset)
        #expect(s.words == .appleMusic)
    }
}

/// `ServiceLibrary` sends each call to the active service's library only.
@MainActor @Test func serviceLibraryUsesTheActiveService() async {
    let spotify = FakeLibrary(), apple = FakeLibrary()
    apple.words = .appleMusic
    let libraries = ServiceLibrary(spotify: spotify, appleMusic: apple, service: .spotify)
    #expect(libraries.words == .spotify)
    _ = await libraries.restoreSession()
    libraries.service = .appleMusic
    #expect(libraries.words == .appleMusic)
    _ = await libraries.logIn()
    libraries.logOut()
    _ = await libraries.playlists()
    _ = await libraries.artists()
    #expect(spotify.calls == ["restoreSession"] && spotify.fetches.isEmpty)
    #expect(apple.calls == ["logIn", "logOut"] && apple.fetches == ["playlists", "artists"])
    libraries.onProgress = { _, _, _, _ in }
    #expect(spotify.onProgress != nil && apple.onProgress != nil)
}

/// The store runs `.setService` before the login: the app sets the service, then the state
/// gets the new library's words, and the login goes to the new service.
@MainActor @Test func storeSetsTheServiceBeforeTheLogin() async {
    let spotify = FakeLibrary(), apple = FakeLibrary()
    apple.words = .appleMusic
    let libraries = ServiceLibrary(spotify: spotify, appleMusic: apple, service: .spotify)
    let store = Store(player: FakePlayer(), library: libraries, state: mainMenu())
    store.onSetService = { service in libraries.service = service }
    store.send(.wheel(5))
    store.send(.select)  // Settings
    store.send(.select)  // Service: Apple Music
    store.send(.menu)
    #expect(libraries.service == .appleMusic && store.state.service == .appleMusic)
    #expect(store.state.words == .appleMusic && store.state.likedSongsName == "Favorite Songs")
    while apple.calls.isEmpty { await Task.yield() }
    // The words came in a nested send; the login after them still ran once, on Apple Music.
    #expect(apple.calls.filter { $0 == "restoreSession" }.count == 1 && spotify.calls.isEmpty)
}
