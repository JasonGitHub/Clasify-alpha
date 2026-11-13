import Testing
@testable import ClasifyCore

/// Card BM (CLA-103): the Settings "Service" row, and the switch between Spotify and Apple Music.
@Suite struct ServiceSwitchTests {
    /// Opens Settings from the main menu. The Service row is the first row (change 256).
    func openSettings(_ s: inout AppState) {
        while s.top.screen != .main { send(&s, .menu) }
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
        #expect(s.current == nil && !s.isPlaying && s.library.isEmpty && !s.signedIn)
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
    #expect(spotify.calls == ["restoreSession"] && spotify.fetches.isEmpty)
    #expect(apple.calls == ["logIn", "logOut"] && apple.fetches == ["playlists"])
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
    #expect(apple.calls == ["restoreSession"] && spotify.calls.isEmpty)
}
