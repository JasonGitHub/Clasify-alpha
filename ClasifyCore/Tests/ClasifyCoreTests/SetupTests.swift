import Testing
@testable import ClasifyCore

/// The first launch setup (Round 13, CLA-50): Hello, the color pick, the login, the Spotify app
/// (only when it is missing) and the first library read, then the main menu.
@Suite struct SetupTests {
    /// The first launch, on the color pick, after the restore found no stored login.
    func onColor() -> AppState {
        var s = AppState()
        send(&s, .spotifyAppFound(true), .launch, .restored(token: 1, ok: false), .select)  // the app is found
        return s
    }
    /// A library of 100 liked songs: the first read takes the full time (changes 266 and 267).
    let big = Playlist(id: Playlist.likedSongsID, name: "Liked Songs", tracks: tracks("b", 100, 10))

    /// Changes 266 and 267: a small first read goes faster. 20 songs or fewer: the names take
    /// 1 s and "You’re all set" 1.5 s; 100 or more, or no count yet: 2.5 s each, as before.
    @Test func theSetupPaceFollowsTheSongCount() {
        let close = { (a: Double, b: Double) in abs(a - b) < 1e-9 }
        // Six names: 2.5 s at most (CLA-80).
        for (songs, time) in [(0, 1.0), (1, 1.0), (20, 1.0), (60, 1.75), (100, 2.5), (5000, 2.5)] {
            #expect(close(AppState.namesTime(names: 6, songs: songs), time))
        }
        #expect(close(AppState.namesTime(names: 6, songs: nil), 2.5))
        // Never longer than today's time for that many names: one name shows at 0.8 s.
        #expect(close(AppState.namesTime(names: 1, songs: 5000), 0.8) && close(AppState.namesTime(names: 1, songs: 1), 0.8))
        #expect(AppState.namesTime(names: 0, songs: 60) == 0)
        for (songs, time) in [(0, 1.5), (1, 1.5), (20, 1.5), (60, 2.0), (100, 2.5), (5000, 2.5)] {
            #expect(close(AppState.allSetTime(songs: songs), time))
        }
        #expect(AppState.allSetTime(songs: nil) == 2.5)
        // The names keep their order and all show inside the time. A count that comes later
        // only moves them on.
        for names in [1, 6] {
            for songs in [nil, 1, 60, 5000] as [Int?] {
                let end = AppState.namesTime(names: names, songs: songs)
                #expect(AppState.nameOpacity(names - 1, of: names, at: end, songs: songs, late: nil) > 1 - 1e-9)
                #expect(AppState.nameOpacity(0, of: names, at: 0, songs: songs, late: nil) == 0)
                for t in stride(from: 0.0, through: 3, by: 0.05) {
                    #expect(AppState.nameOpacity(names - 1, of: names, at: t, songs: songs, late: nil) <= AppState.nameOpacity(0, of: names, at: t, songs: songs, late: nil))
                    #expect(AppState.nameOpacity(names - 1, of: names, at: t, songs: nil, late: nil) <= AppState.nameOpacity(names - 1, of: names, at: t, songs: songs, late: nil))
                }
            }
        }
    }

    /// Change 266 with a late count (Apple Music gives it only at the end of the read): the
    /// old pace until it comes, then on to the end of the new time, or in 0.2 s when that has
    /// passed. Nothing jumps back.
    @Test func aLateCountFinishesTheNames() {
        let close = { (a: Double, b: Double) in abs(a - b) < 1e-9 }
        #expect(AppState.namesEnd(names: 6, songs: 15, late: nil) == 1)
        #expect(AppState.namesEnd(names: 6, songs: 15, late: 0.5) == 1)
        #expect(close(AppState.namesEnd(names: 6, songs: 15, late: 1.5), 1.7))
        #expect(AppState.namesEnd(names: 6, songs: 15, late: 3) == 3)  // every name had shown
        #expect(AppState.namesEnd(names: 6, songs: 15, late: 2.4) == 2.5)  // never later than before
        #expect(close(AppState.namesEnd(names: 2, songs: 100, late: 1), 1.14))
        #expect(close(AppState.namesProgress(at: 1, names: 6, songs: 15, late: 1.5), 0.4))  // the old pace
        #expect(close(AppState.namesProgress(at: 1.5, names: 6, songs: 15, late: 1.5), 0.6))
        #expect(close(AppState.namesProgress(at: 1.6, names: 6, songs: 15, late: 1.5), 0.8))
        #expect(close(AppState.namesProgress(at: 1.7, names: 6, songs: 15, late: 1.5), 1))
        #expect(close(AppState.namesProgress(at: 0.75, names: 6, songs: 15, late: 0.5), 0.6))
        for late in [0.3, 1.5, 2.4, 3] {
            var last = 0.0
            for t in stride(from: 0.0, through: 4, by: 0.01) {
                let p = AppState.namesProgress(at: t, names: 6, songs: 15, late: late)
                #expect(p >= last - 1e-9)
                last = p
            }
            #expect(last == 1 && AppState.nameOpacity(5, of: 6, at: AppState.namesEnd(names: 6, songs: 15, late: late), songs: 15, late: late) > 1 - 1e-9)
        }
        // In the reducer: the names came at 200, the count and the songs at 201.5.
        var s = onColor()
        send(&s, .select, .select, .select, .authDone(token: 2, ok: true), .select)
        let names = (1...8).map { Playlist(id: "p\($0)", name: "P\($0)", tracks: [], trackCount: 1) }
        send(&s, .playlistsRefreshed(names), now: 200)
        #expect(s.namesLate == nil)
        send(&s, .readProgress(Playlist.likedSongsID, done: 2, total: 2, albums: 1), .tracksLoaded(token: 1, playlist: Playlist.likedSongsID, tracks: liked.tracks), now: 201.5)
        #expect(s.namesLate == 1.5 && s.top.loading && abs(s.namesHold - 201.7) < 1e-9)
        send(&s, .tick, now: 201.8)
        #expect(!s.top.loading && s.setupDone && abs(s.beatUntil - 203.3) < 1e-9)
    }

    /// Changes 266 and 267 in the reducer: a small library waits 1 s for six names and shows
    /// "You’re all set" for 1.5 s. The count is the read's first total, and stays.
    @Test func aSmallFirstReadGoesFaster() {
        var s = onColor()
        send(&s, .select, .select, .select, .authDone(token: 2, ok: true), .select)
        send(&s, .readProgress(Playlist.likedSongsID, done: 0, total: liked.tracks.count, albums: 0), now: 199)
        #expect(s.firstReadSongs == liked.tracks.count)
        let names = (1...8).map { Playlist(id: "p\($0)", name: "P\($0)", tracks: [], trackCount: 1) }
        send(&s, .playlistsRefreshed(names), now: 200)
        send(&s, .readProgress(Playlist.likedSongsID, done: 1, total: 500, albums: 0), now: 200.2)
        #expect(s.firstReadSongs == liked.tracks.count)  // the pace never slows down
        send(&s, .tracksLoaded(token: 1, playlist: Playlist.likedSongsID, tracks: liked.tracks), now: 200.5)
        #expect(s.top.loading && abs(s.namesHold - 201) < 1e-9)
        send(&s, .tick, now: 201)
        #expect(!s.top.loading && s.setupDone && abs(s.beatUntil - 202.5) < 1e-9)
    }

    @Test func aFirstLaunchShowsHelloThenTheColorPick() {
        var s = AppState()
        #expect(send(&s, .launch) == [.restoreSession(token: 1)])
        #expect(s.stack == [Frame(screen: .hello)] && s.restoring && s.navSeq == 0)  // the first screen does not slide in
        #expect(s.helloAt == 100)  // the skin times the hello from here
        #expect(send(&s, .wheel(1), .menu, .restored(token: 1, ok: false)).isEmpty)
        #expect(s.stack == [Frame(screen: .hello)])  // a turn and MENU do nothing on Hello
        let whole = s.wholeSeq
        send(&s, .select)  // a press begins setup
        #expect(s.stack == [Frame(screen: .color)] && s.navForward)
        // CLA-62: Hello has no title bar, so the whole screen pushes, title bar and all.
        #expect(s.wholeSeq == whole + 1 && s.navMove == .push)
        #expect(s.rows(for: s.top) == [.color(.silver), .color(.black)] && s.top.sel == 0)
        // CLA-62: MENU on the color pick goes back to Hello, which starts again. The whole
        // screen moves back. A color turned to but not pressed is dropped.
        let back = s.wholeSeq
        send(&s, .wheel(1), .menu, now: 130)
        #expect(s.stack == [Frame(screen: .hello)] && s.helloAt == 130 && !s.navForward)
        #expect(s.wholeSeq == back + 1 && s.deviceColor == .silver && s.shownColor == .silver)
        send(&s, .select)  // a press begins setup again, on the saved color
        #expect(s.top.screen == .color && s.top.sel == 0)
    }

    @Test func theColorPickSavesTheColorAndMenuOnTheLoginGoesBack() {
        var s = onColor()
        let whole = s.wholeSeq
        send(&s, .wheel(1), .select)
        #expect(s.deviceColor == .black && s.top.screen == .pickMusic && s.top.sel == 0)  // card BM, change 257
        #expect(s.wholeSeq == whole)  // between two setup screens, only the content slides
        send(&s, .select)  // Spotify
        #expect(s.top.screen == .login && s.rows(for: s.top) == [.logIn])
        send(&s, .menu, .menu)  // back to Pick Your Music, then to the color pick, with Black selected (card AX, change 172)
        #expect(s.top.screen == .color && s.top.sel == 1 && !s.navForward)
        #expect(s.colorAt == 100 && s.colorTurnAt == 100)  // it keeps its times: the center glows, no waiting comet
        send(&s, .reset, .launch, .restored(token: 2, ok: false), .select)  // a reset keeps the settings
        #expect(s.top.screen == .color && s.top.sel == 1)  // the pick starts on the color that is set
    }

    /// Card AW: a turn tries the color on the device at once. A press saves it.
    @Test func theColorPickTriesAColorOnAtTheFirstTurn() {
        var s = onColor()
        #expect(s.colorAt == 100 && s.colorTurnAt == 0 && s.shownColor == .silver)
        send(&s, .wheel(1), now: 105)
        #expect(s.colorTurnAt == 105 && s.shownColor == .black && s.deviceColor == .silver)
        send(&s, .wheel(-1), now: 107)  // only the first turn counts
        #expect(s.colorTurnAt == 105 && s.shownColor == .silver)
        send(&s, .wheel(-1), now: 107.5)  // at the top: no color change
        #expect(s.shownColor == .silver)
        send(&s, .menu, .select, now: 108)  // back to Hello and in again
        #expect(s.top.screen == .color)
        send(&s, .wheel(1), .select, now: 108)
        #expect(s.top.screen == .pickMusic && s.deviceColor == .black && s.shownColor == .black)
        #expect(mainMenu().shownColor == .silver)  // off the color pick, the setting shows
    }

    @Test func aLoginInSetupReadsTheLibraryThenOpensTheMainMenu() {
        var s = onColor()
        #expect(send(&s, .select, .select, .select) == [.logIn(token: 2)])  // the color, Spotify (card BM), Log In
        #expect(send(&s, .authDone(token: 2, ok: true)) == [.prefetch])
        #expect(s.top.screen == .loggedIn && s.navForward)  // "You’re in" (card AX, change 175)
        // Card AY: Liked Songs, and the playlist names for the small screen (change 141).
        #expect(send(&s, .tick, now: 101.5) == [.fetchTracks(token: 1, playlist: Playlist.likedSongsID), .refreshPlaylists])
        #expect(s.stack == [Frame(screen: .yourMusic, loading: true, token: 1)] && s.signedIn && s.navForward)
        #expect(s.toast == "" && !s.setupDone && s.namesAt == 0)
        send(&s, .playlistsRefreshed([focusInfo]), now: 106)  // a slow read: they still fill in one by one from now
        #expect(s.top.loading && s.library.map(\.id) == ["focus"] && s.namesAt == 106)  // the read goes on
        send(&s, .tracksLoaded(token: 1, playlist: Playlist.likedSongsID, tracks: liked.tracks), now: 110)
        // "You’re all set" (change 140), 1.5 s for a small library (change 267), then the main menu.
        #expect(s.stack == [Frame(screen: .yourMusic, token: 1)] && s.setupDone && s.loadedTracks == [Playlist.likedSongsID])
        #expect(s.beatUntil == 111.5 && send(&s, .menu, .wheel(1), now: 111).isEmpty && s.top.screen == .yourMusic)
        send(&s, .tick, now: 111.5)
        #expect(s.stack == [Frame(screen: .main)] && s.beatUntil == 0)
    }

    /// Change 141: the first read counts up as the library reports how far it is. Other reads,
    /// and reports after the read, change nothing.
    @Test func theFirstReadCountsUp() {
        var s = onColor()
        send(&s, .select, .select, .select, .authDone(token: 2, ok: true), .select, .playlistsRefreshed([]))  // no names to wait for
        #expect(s.top.screen == .yourMusic && s.readDone == 0 && s.readTotal == 0)
        send(&s, .readProgress(Playlist.likedSongsID, done: 0, total: 1240, albums: 0), .readProgress(Playlist.likedSongsID, done: 300, total: 1240, albums: 84))
        #expect(s.readDone == 300 && s.readTotal == 1240 && s.readAlbums == 84)  // change 188
        send(&s, .readProgress(Playlist.likedSongsID, done: 200, total: 1240, albums: 60))  // a late report
        #expect(s.readDone == 300 && s.readAlbums == 84)
        send(&s, .readProgress("focus", done: 5, total: 8, albums: 3))  // another read
        #expect(s.readDone == 300 && s.readTotal == 1240 && s.readAlbums == 84)
        send(&s, .tracksLoaded(token: 1, playlist: Playlist.likedSongsID, tracks: liked.tracks), .readProgress(Playlist.likedSongsID, done: 1240, total: 1240, albums: 0))
        #expect(s.readDone == liked.tracks.count)  // the read has ended: full, and a late report changes nothing
    }

    /// Change 191: when Liked Songs is read before every playlist name showed, "Getting your
    /// music" stays until the last name has shown. Then "You’re all set" as before.
    @Test func theFirstReadWaitsForEveryName() {
        var s = onColor()
        send(&s, .select, .select, .select, .authDone(token: 2, ok: true), .select)
        let names = (1...8).map { Playlist(id: "p\($0)", name: "P\($0)", tracks: [], trackCount: 1) }
        send(&s, .playlistsRefreshed(names), now: 200)
        #expect(s.firstReadNames.count == 6 && s.playlistCount == 8)  // six names show; the count is all
        send(&s, .tracksLoaded(token: 1, playlist: Playlist.likedSongsID, tracks: big.tracks), now: 201)
        // The sixth name has shown at 200 + 0.5 + 5 × 0.34 + 0.3 = 202.5 s (CLA-80).
        #expect(s.top.loading && !s.setupDone && abs(s.namesHold - 202.5) < 1e-9)
        #expect(s.loadedTracks == [Playlist.likedSongsID])  // the songs are kept already
        let albums = Set(big.tracks.compactMap { $0.album?.id }).count
        #expect(s.readDone == big.tracks.count && s.readTotal == big.tracks.count && s.readAlbums == albums)  // full
        #expect(send(&s, .select, now: 202).isEmpty && s.top.loading)  // no press meanwhile
        send(&s, .readProgress(Playlist.likedSongsID, done: 1, total: 2, albums: 1), .tick, now: 202.2)
        #expect(s.top.loading && s.readDone == big.tracks.count)  // a late report changes nothing
        send(&s, .offline(true), .tick, now: 202.6)
        #expect(!s.top.loading && !s.top.error && s.setupDone && s.namesHold == 0 && abs(s.beatUntil - 205.1) < 1e-9)

        // Two names wait only for those: shown at 200 + 0.5 + 0.34 + 0.3 = 201.14 s.
        var two = onColor()
        send(&two, .select, .select, .select, .authDone(token: 2, ok: true), .select)
        send(&two, .playlistsRefreshed(Array(names.prefix(2))), now: 200)
        var late = two
        send(&two, .tracksLoaded(token: 1, playlist: Playlist.likedSongsID, tracks: big.tracks), now: 201)
        #expect(abs(two.namesHold - 201.14) < 1e-9 && !two.setupDone)
        // A read that ends after the names waits for nothing.
        send(&late, .tracksLoaded(token: 1, playlist: Playlist.likedSongsID, tracks: big.tracks), now: 201.5)
        #expect(late.setupDone && late.namesHold == 0)
    }

    /// CLA-74: the read at login can end Liked Songs before the playlist list comes. "Getting
    /// your music" then waits for the list, and for its names as in change 191.
    @Test func aReadBeforeTheListWaitsForTheNames() {
        var s = onColor()
        send(&s, .select, .select, .select, .authDone(token: 2, ok: true), .select)
        #expect(s.namesAt == 0 && s.refreshing.contains(AppState.readKey(.playlists)))
        send(&s, .tracksLoaded(token: 1, playlist: Playlist.likedSongsID, tracks: big.tracks), now: 201)
        #expect(s.top.loading && !s.setupDone && s.namesHold == .infinity && s.loadedTracks == [Playlist.likedSongsID])
        #expect(s.readDone == big.tracks.count && s.readTotal == big.tracks.count)  // the bar is full
        send(&s, .tick, now: 300)
        #expect(s.top.loading && !s.setupDone)  // it waits for the list
        let names = (1...8).map { Playlist(id: "p\($0)", name: "P\($0)", tracks: [], trackCount: 1) }
        send(&s, .playlistsRefreshed(names), now: 302)
        // The sixth name has shown at 302 + 0.5 + 5 × 0.34 + 0.3 = 304.5 s.
        #expect(s.namesAt == 302 && abs(s.namesHold - 304.5) < 1e-9 && s.top.loading && !s.setupDone)
        send(&s, .tick, now: 304.4)
        #expect(s.top.loading && !s.setupDone)
        send(&s, .tick, now: 304.6)
        #expect(!s.top.loading && !s.top.error && s.setupDone && s.namesHold == 0 && abs(s.beatUntil - 307.1) < 1e-9)
    }

    /// CLA-74: when the list fails, or has no playlists, setup goes on at once.
    @Test func aReadBeforeAListThatFailsOrIsEmptyGoesOn() {
        let lists: [[Playlist]?] = [nil, []]
        for list in lists {
            var s = onColor()
            send(&s, .select, .select, .select, .authDone(token: 2, ok: true), .select)
            send(&s, .tracksLoaded(token: 1, playlist: Playlist.likedSongsID, tracks: liked.tracks), now: 201)
            #expect(s.top.loading && s.namesHold == .infinity)
            send(&s, .playlistsRefreshed(list), now: 202)
            #expect(!s.top.loading && !s.top.error && s.setupDone && s.namesHold == 0 && s.beatUntil == 203.5)
        }
    }

    @Test func aPressOnAllSetGoesOnAtOnce() {
        var s = onColor()
        send(&s, .select, .select, .select, .authDone(token: 2, ok: true), .select)
        #expect(s.top.screen == .yourMusic && send(&s, .select).isEmpty && s.top.screen == .yourMusic)  // no press while it reads
        send(&s, .playlistsRefreshed([]), .tracksLoaded(token: 1, playlist: Playlist.likedSongsID, tracks: liked.tracks), .select)
        #expect(s.stack == [Frame(screen: .main)] && s.beatUntil == 0)
    }

    @Test func aFailedFirstReadShowsTheErrorAndRetries() {
        var s = onColor()
        send(&s, .select, .select, .select, .authDone(token: 2, ok: true), .select)
        send(&s, .playlistsRefreshed([]))  // no names to wait for
        send(&s, .readProgress(Playlist.likedSongsID, done: 900, total: 1240, albums: 0), .tracksLoaded(token: 1, playlist: Playlist.likedSongsID, tracks: nil))
        #expect(s.top.screen == .yourMusic && s.top.error && !s.setupDone)
        #expect(send(&s, .select) == [.fetchTracks(token: 2, playlist: Playlist.likedSongsID)])
        #expect(s.readDone == 0 && s.readTotal == 0 && s.readAlbums == 0)  // the retry counts from 0 again
        send(&s, .readProgress(Playlist.likedSongsID, done: 300, total: 1240, albums: 0))
        #expect(s.readDone == 300)
        send(&s, .tracksLoaded(token: 2, playlist: Playlist.likedSongsID, tracks: liked.tracks), .select)
        #expect(s.stack == [Frame(screen: .main)] && s.setupDone)
    }

    @Test func aStoredLoginSkipsTheLoginStep() {
        var s = AppState()
        send(&s, .launch, .restored(token: 1, ok: true))
        #expect(s.stack == [Frame(screen: .hello)] && s.signedIn)  // Hello stays until the press
        send(&s, .select, .select)
        #expect(s.top.screen == .yourMusic)
        // The restore ends while the login screen waits for it: setup goes on.
        s = AppState()
        send(&s, .spotifyAppFound(true), .launch, .select, .select, .select)
        #expect(s.top.screen == .login && s.restoring && s.rows(for: s.top).isEmpty)
        send(&s, .restored(token: 1, ok: true))
        #expect(s.top.screen == .yourMusic && s.navForward)
    }

    @Test func theSpotifyAppScreenShowsOnlyWhenTheAppIsMissing() {
        var s = onColor()
        // The color, Spotify (the second row with no Spotify app, CLA-103), Log In.
        send(&s, .spotifyAppFound(false), .select, .wheel(1), .select, .select, .authDone(token: 2, ok: true), .select)
        #expect(s.stack == [Frame(screen: .spotifyApp)] && s.spotifyApp == false)
        #expect(s.rows(for: s.top) == [.getSpotifyApp])
        #expect(send(&s, .menu, .wheel(1), .spotifyAppFound(false)).isEmpty)  // MENU does nothing, and the check goes on
        #expect(send(&s, .select) == [.getSpotifyApp])  // opens the download page
        #expect(s.stack == [Frame(screen: .spotifyApp)])
        send(&s, .spotifyAppFound(true), now: 200)  // "Linked" shows for 1.5 s (change 174)
        #expect(s.top.screen == .spotifyApp && s.spotifyApp == true && s.beatUntil == 201.5)
        send(&s, .spotifyAppFound(true), now: 201)  // the next check does not restart it
        #expect(s.beatUntil == 201.5)
        send(&s, .tick, now: 201.5)
        #expect(s.top.screen == .yourMusic && s.beatUntil == 0)
        send(&s, .reset)  // the Mac still has the app
        #expect(s.spotifyApp == true)
    }

    /// Change 131: when a play finds the Spotify app gone, the Spotify App screen opens over
    /// the screen that shows. When the app is back, it closes to that screen, with no toast.
    @Test func theSpotifyAppScreenOpensWhenTheAppGoesAway() {
        var s = playing()
        let before = s.stack
        send(&s, .spotifyAppFound(false), .playbackFailed("We need the Spotify app to play music", generation: s.playGen))
        #expect(s.stack == before + [Frame(screen: .spotifyApp)] && s.toast.isEmpty && !s.isPlaying)
        send(&s, .menu, .spotifyAppFound(false))
        #expect(s.stack == before + [Frame(screen: .spotifyApp)])
        send(&s, .spotifyAppFound(true), .tick, now: 200)
        #expect(s.top.screen == .spotifyApp)  // "Linked" first
        send(&s, .tick, now: 201.5)
        #expect(s.stack == before)
        s = AppState()
        send(&s, .spotifyAppFound(false))  // the check at launch, before the login: nothing opens
        #expect(s.stack == [Frame(screen: .login)])
    }

    /// A login after a logout, when the player then finds the Spotify app gone: the screen takes
    /// the place of "You’re in", and the app found goes on to the main menu.
    @Test func theSpotifyAppScreenReplacesYoureIn() {
        var s = afterSetup()
        send(&s, .select, .authDone(token: 1, ok: true), .spotifyAppFound(false), now: 10)
        #expect(s.stack == [Frame(screen: .spotifyApp)] && s.beatUntil == 0)
        send(&s, .spotifyAppFound(true), now: 20)
        send(&s, .tick, now: 21.5)
        #expect(s.stack == [Frame(screen: .main)])
    }

    /// A first play that fails under the Spotify App screen leaves no empty Now Playing, and a
    /// read that ended under it starts again when it closes.
    @Test func closingTheSpotifyAppScreenCleansUpUnderIt() {
        var s = mainMenu()
        send(&s, openFocus(1))
        send(&s, .select)  // the first track: Now Playing opens, and the load starts
        let list = s.stack.dropLast().map(\.screen)  // the main menu's selection moves with its Now Playing row
        send(&s, .spotifyAppFound(false), .loadFailed("We need the Spotify app to play music", generation: s.playGen))
        #expect(s.current == nil && s.toast.isEmpty)
        send(&s, .spotifyAppFound(true), .select)
        #expect(s.stack.map(\.screen) == list && s.top.screen == .tracks(playlist: "focus"))  // the list, not an empty Now Playing
        s = mainMenu()
        send(&s, .wheel(1), .select)  // Playlists starts to read
        #expect(s.top.loading && s.top.token == 1)
        send(&s, .spotifyAppFound(false), .playlistsLoaded(token: 1, playlists: [focusInfo]))  // dropped under the screen
        #expect(send(&s, .spotifyAppFound(true), .select) == [.fetchPlaylists(token: 2)])  // so it reads again
        #expect(s.top == Frame(screen: .playlists, loading: true, token: 2))
        send(&s, .playlistsLoaded(token: 2, playlists: [focusInfo]))
        #expect(!s.top.loading && s.rows(for: s.top) == [.playlist("focus")])
    }

    @Test func aLaterLaunchSkipsSetupAndChecksTheSpotifyApp() {
        var s = afterSetup()
        send(&s, .spotifyAppFound(true), .launch)
        #expect(s.stack == [Frame(screen: .login)] && s.helloAt == 0)
        send(&s, .restored(token: 1, ok: true))
        #expect(s.stack == [Frame(screen: .main)])
        s = afterSetup()
        send(&s, .spotifyAppFound(false), .launch, .restored(token: 1, ok: true))
        #expect(s.stack == [Frame(screen: .spotifyApp)])
        send(&s, .spotifyAppFound(true), .select)  // a press on "Linked" goes on at once
        #expect(s.stack == [Frame(screen: .main)])  // no library read: straight to the main menu
        // A login after a logout skips setup too.
        send(&s, .wheel(5), .select, .wheel(8), .select, .wheel(1), .select, .select)
        #expect(s.top == Frame(screen: .auth, token: 2) && s.toast == "")  // change 181: no toast
        send(&s, .authDone(token: 2, ok: true), .select)
        #expect(s.stack == [Frame(screen: .main)])
    }
}

/// Waits until `done` is true, for at most 10 s, so a test cannot loop forever. With `tick`, it
/// sends `.tick` meanwhile, as the app's ticker does, so timed holds can end.
@MainActor func waitFor(_ store: Store, tick: Bool = false, until done: (AppState) -> Bool) async {
    let deadline = ContinuousClock.now + .seconds(10)
    while !done(store.state) && ContinuousClock.now < deadline {
        if tick { store.send(.tick) }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor @Test func storeSavesTheEndOfSetup() async {
    let saved = FakeSettings()
    // A real clock from 100 s: "Getting your music" holds until the playlist names have shown (CLA-74).
    let start = ContinuousClock.now
    let clock = Dependencies(now: {
        let d = ContinuousClock.now - start
        return 100 + Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18
    }, random: { _ in 0 })
    let store = Store(player: FakePlayer(), library: FakeLibrary(), env: clock, settings: saved)
    store.send(.launch)
    #expect(store.state.top.screen == .hello)
    await waitFor(store) { !$0.restoring }  // the fake restores a stored login
    store.send(.select)
    store.send(.select)
    #expect(store.state.top.screen == .yourMusic && saved.values["setup.done"] == nil)
    await waitFor(store, tick: true) { $0.setupDone }
    #expect(store.state.top.screen == .yourMusic && saved.values["setup.done"] == "true")  // "You’re all set"
    #expect(store.state.readTotal == 2 && store.state.readDone >= 1)  // the bar ends full, or at the last report
    store.send(.select)
    #expect(store.state.top.screen == .main)
    #expect(Settings(from: saved).setupDone)
}

/// Change 188: the library's progress reports reach the store.
@MainActor @Test func storePassesTheReadProgressOn() {
    var s = AppState()
    send(&s, .launch, .restored(token: 1, ok: true), .select, .select)  // "Getting your music"
    let lib = FakeLibrary()
    let store = Store(player: FakePlayer(), library: lib, state: s, env: Dependencies(now: { 100 }, random: { _ in 0 }))
    #expect(store.state.top.screen == .yourMusic && store.state.top.loading)
    lib.onProgress?(Playlist.likedSongsID, 1, 2, 1)
    #expect(store.state.readDone == 1 && store.state.readTotal == 2 && store.state.readAlbums == 1)
}
