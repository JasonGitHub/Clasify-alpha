import Testing
@testable import ClasifyCore

/// CLA-179, card CR: On This Mac, the third service, behind the `local.on` test switch.
@Suite struct LocalServiceTests {
    func openSettings(_ s: inout AppState) {
        for _ in 0..<8 where s.top.screen != .main { send(&s, .menu) }
        s.top.sel = s.rows(for: s.top).firstIndex(of: .settings) ?? -1
        send(&s, .select)
    }

    @Test func theServiceRowLoopsThroughThreeOnlyWithTheSwitch() {
        #expect(MusicService.spotify.next(localOn: true) == .appleMusic)
        #expect(MusicService.appleMusic.next(localOn: true) == .local)
        #expect(MusicService.local.next(localOn: true) == .spotify)
        #expect(MusicService.appleMusic.next(localOn: false) == .spotify)
        var s = playing()
        s.localOn = true
        openSettings(&s)
        send(&s, .select, .select)
        #expect(s.pendingService == .local)
        send(&s, .select)
        #expect(s.pendingService == .spotify)
        send(&s, .select, .select)
        let fx = send(&s, .menu)
        #expect(fx == [.stop, .setService(.local), .restoreSession(token: s.authAttempt)])
        #expect(s.service == .local)
    }

    @Test func pickYourMusicHasOnThisMacThirdWithTheSwitch() {
        var s = afterSetup()
        s.setupDone = false
        send(&s, .spotifyAppFound(true), .launch, .restored(token: 1, ok: false), .select, .select)
        #expect(s.rows(for: s.top) == [.pickService(.spotify), .pickService(.appleMusic)])
        s.localOn = true
        #expect(s.rows(for: s.top) == [.pickService(.spotify), .pickService(.appleMusic), .pickService(.local)])
        s.appleMusicFirst = true
        #expect(s.rows(for: s.top).last == .pickService(.local))
        // A pick logs in at once: there is no account, and the library answers .ok.
        #expect(send(&s, .wheel(2), .select) == [.setService(.local), .logIn(token: 2)])
        send(&s, .authDone(token: 2, ok: true))
        #expect(s.service == .local && s.signedIn && s.top.screen == .loggedIn)
    }

    @Test func onThisMacHasNoLogOutAndNoFavoriteSongsRow() {
        var s = mainMenu()
        s.words = .local
        #expect(s.rows(for: Frame(screen: .playlists)).first == .playlist(Playlist.likedSongsID))  // still Spotify
        s.service = .local
        #expect(!s.rows(for: Frame(screen: .settings)).contains(.logOut))
        #expect(!s.rows(for: Frame(screen: .playlists)).contains(.playlist(Playlist.likedSongsID)))
        #expect(s.rows(for: Frame(screen: .main)).contains(.songs))  // today's Apple Music menu
        s.service = .appleMusic
        #expect(s.rows(for: Frame(screen: .settings)).last == .logOut)
    }

    @Test func theSwitchIsReadOnlyAndOffKeepsSpotify() {
        let store = FakeSettings()
        store.values = ["settings.service": "On This Mac"]
        #expect(Settings(from: store).service == .spotify && !Settings(from: store).localOn)
        store.values["local.on"] = "1"  // defaults write … -bool YES
        #expect(Settings(from: store).service == .local && Settings(from: store).localOn)
        store.values["local.on"] = "true"
        let settings = Settings(from: store)
        #expect(settings.localOn)
        let saved = FakeSettings()
        settings.save(to: saved)
        #expect(saved.values["local.on"] == nil && saved.values["settings.service"] == "On This Mac")
        var s = AppState()
        s.settings = settings
        #expect(s.localOn && s.service == .local)
    }

    @Test func onThisMacTakesTheMacVolumeAndItsEventNameIsLocal() {
        var s = mainMenu()
        s.service = .local
        send(&s, .volumeReported(20))
        #expect(s.volume == 20)
        #expect(MusicService.local.eventName == "local")
    }
}

@MainActor @Test func servicePlayerAndLibraryUseOnThisMac() async {
    let spotify = FakePlayer(), apple = FakePlayer(), local = FakePlayer()
    let player = ServicePlayer(spotify: spotify, appleMusic: apple, local: local, service: .spotify)
    player.service = .local
    player.load(trackID: "local:track:1", context: nil, autoplay: true, generation: 1)
    player.setShuffle(true)
    #expect(spotify.calls == ["stop", "shuffle true"] && local.active == true)
    #expect(local.calls == ["load local:track:1 - true", "shuffle true"])
    let none = ServicePlayer(spotify: FakePlayer(), appleMusic: FakePlayer(), service: .local)
    none.load(trackID: "local:track:1", context: nil, autoplay: true, generation: 1)  // no local player yet: nothing plays

    let localLibrary = FakeLibrary()
    let only = ServiceLibrary(spotify: FakeLibrary(), appleMusic: FakeLibrary(), local: localLibrary, service: .local)
    _ = await only.playlists()
    only.onProgress = { _, _, _, _ in }
    #expect(localLibrary.fetches == ["playlists"] && localLibrary.onProgress != nil)
}

/// Card CR: "No songs yet" on On This Mac with an empty library, with "Check again" and
/// "Pick Your Music".
@Suite struct LocalNoSongsTests {
    func signedIn(albumArt: AlbumArt) -> AppState {
        var s = afterSetup()
        (s.service, s.words, s.localOn, s.albumArt) = (.local, .local, true, albumArt)
        send(&s, .launch)
        let fx = send(&s, .restored(token: s.authAttempt, ok: true))
        // The whole library is read when the main menu opens, also with no covers beside it.
        #expect(fx.filter { if case .readArtTracks = $0 { true } else { false } }
            == [.readArtTracks(token: s.artTok, playlist: Playlist.libraryID)])
        #expect(s.top.screen == .main)
        return s
    }

    @Test func anEmptyLibraryShowsNoSongsAndCheckAgainReadsItAgain() {
        for art in [AlbumArt.all, .nowPlaying] {
            var s = signedIn(albumArt: art)
            send(&s, .artTracksRead(token: s.artTok, playlist: Playlist.libraryID, tracks: []))
            #expect(s.localEmpty && s.stack == [Frame(screen: .noSongs)])
            #expect(s.rows(for: s.top) == [.checkLibrary, .pickYourMusic] && s.top.screen.isList)
            #expect(send(&s, .select) == [.refreshTracks(playlist: Playlist.libraryID)])
            #expect(send(&s, .select) == [])  // one read at a time
            send(&s, .tracksRefreshed(playlist: Playlist.libraryID, tracks: []))
            #expect(s.top.screen == .noSongs)  // still empty: the screen stays
            send(&s, .select)
            let song = Track(id: "local:track:1", title: "Song", artist: "Band", duration: 180)
            send(&s, .tracksRefreshed(playlist: Playlist.libraryID, tracks: [song]))
            #expect(!s.localEmpty && s.stack == [Frame(screen: .main)])
        }
    }

    @Test func pickYourMusicLeavesOnThisMac() {
        var s = signedIn(albumArt: .all)
        send(&s, .artTracksRead(token: s.artTok, playlist: Playlist.libraryID, tracks: []))
        send(&s, .wheel(1))
        #expect(send(&s, .select).contains(.logOut))
        #expect(s.top.screen == .pickMusic && !s.signedIn && s.rows(for: s.top).contains(.pickService(.local)))
    }

    @Test func aLibraryWithSongsKeepsTheMainMenu() {
        var s = signedIn(albumArt: .all)
        let song = Track(id: "local:track:1", title: "Song", artist: "Band", duration: 180)
        send(&s, .artTracksRead(token: s.artTok, playlist: Playlist.libraryID, tracks: [song]))
        #expect(!s.localEmpty && s.top.screen == .main)
        var spotify = mainMenu()  // never on Spotify
        spotify.loadedTracks.insert(Playlist.libraryID)
        #expect(!spotify.localEmpty)
    }
}
