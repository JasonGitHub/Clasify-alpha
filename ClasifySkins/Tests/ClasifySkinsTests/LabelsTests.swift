import AppKit
import ClasifyCore
import CoreGraphics
import SwiftUI
import Testing

@testable import ClasifySkins

/// A signed-in state with two playlists and Liked Songs.
func sampleState() -> AppState {
    var s = AppState()
    s.signedIn = true
    s.stack = [Frame(screen: .main)]
    s.library = [
        Playlist(id: Playlist.likedSongsID, name: "Liked Songs", tracks: [
            Track(id: "spotify:track:1", title: "Paper Planes", artist: "M.I.A.", duration: 205),
            Track(id: "spotify:track:2", title: "Hey Ya!", artist: "OutKast", duration: 235,
                  coverID: String(repeating: "ab", count: 20)),
        ]),
        Playlist(id: "spotify:playlist:a", name: "Road Trip", tracks: (1...12).map {
            Track(id: "spotify:track:r\($0)", title: "Song \($0)", artist: "Band \($0)", duration: 180)
        }),
        Playlist(id: "spotify:playlist:b", name: "Empty", tracks: []),
    ]
    return s
}

@Suite struct LabelsTests {
    @Test func titlesFollowTheMockup() {
        let s = sampleState()
        #expect(Labels.title(.login, in: s) == "Log In")  // card AX
        #expect(Labels.title(.main, in: s) == "Clasify")
        #expect(Labels.title(.auth, in: s) == "Log In")
        #expect(Labels.title(.tracks(playlist: "spotify:playlist:a"), in: s) == "Road Trip")
        #expect(Labels.title(.confirm, in: s) == "Log out?")
        #expect(Labels.title(.now, in: s) == "Now Playing")
    }

    /// Card BN: Apple Music's library rows, lists and empty messages.
    @Test func appleMusicLibraryRowsUseTheCardWords() {
        var s = sampleState()
        s.words = .appleMusic
        let artist = "applemusic:artist:1"
        s.artists = [Playlist(id: artist, name: "The Lowlights", tracks: [])]
        #expect(Labels.row(.artists, on: .main, in: s).label == "Artists")
        #expect(Labels.row(.songs, on: .main, in: s).label == "Songs")
        #expect(Labels.row(.artist(artist), on: .artists, in: s).label == "The Lowlights")
        #expect(Labels.row(.playlist(Playlist.likedSongsID), on: .playlists, in: s).label == "Favorite Songs")
        #expect(Labels.title(.artists, in: s) == "Artists")
        #expect(Labels.title(.tracks(playlist: Playlist.songsID), in: s) == "Songs")
        #expect(Labels.title(.tracks(playlist: artist), in: s) == "The Lowlights")
        s.artists = []
        s.stack.append(Frame(screen: .artists))
        #expect(Labels.message(for: s.top, in: s)?.title == "No artists")
        s.stack = [Frame(screen: .main), Frame(screen: .tracks(playlist: Playlist.songsID))]
        #expect(Labels.message(for: s.top, in: s)?.body == "Add songs to your library in Apple Music. Press MENU to go back.")
    }

    /// CLA-103: the liked list's row and title use the name that the `Library` gives.
    @Test func likedListUsesTheLibraryName() {
        var s = sampleState()
        s.likedSongsName = "Favorite Songs"
        s.library.removeFirst()  // not read yet: the title falls back to the name
        #expect(Labels.row(.likedSongs, on: .main, in: s).label == "Favorite Songs")
        #expect(Labels.title(.tracks(playlist: Playlist.likedSongsID), in: s) == "Favorite Songs")
    }

    /// Card BM (CLA-103): the Service row shows the value of the last press, and the texts
    /// that name the service follow the active library.
    @Test func serviceRowAndTextsFollowTheService() {
        var s = sampleState()
        #expect(Labels.row(.service, on: .settings, in: s) == Labels.RowText(label: "Service", value: "Spotify"))
        s.pendingService = .appleMusic
        #expect(Labels.row(.service, on: .settings, in: s).value == "Apple Music")
        s.words = .appleMusic
        var error = Frame(screen: .playlists)
        error.error = true
        #expect(Labels.message(for: error, in: s)?.title == "Can’t reach Apple Music")
        s.library = []
        s.stack.append(Frame(screen: .albums))
        #expect(Labels.message(for: s.top, in: s)?.body == "Favorite songs in Apple Music to see their albums. Press MENU to go back.")
    }

    /// Card BM: the titles, rows and words of Pick Your Music, Access is off and Not subscribed.
    @Test func appleMusicSetupScreensUseTheCardWords() {
        var s = sampleState()
        #expect(Labels.title(.pickMusic, in: s) == "Pick Your Music" && Labels.title(.accessOff, in: s) == "Log In")
        #expect(Labels.row(.pickService(.appleMusic), on: .pickMusic, in: s).label == "Apple Music")
        #expect(Labels.row(.openPrivacy, on: .accessOff, in: s).label == "Open Settings")
        #expect(Labels.row(.useSpotify, on: .accessOff, in: s).label == "Use Spotify")
        #expect(Labels.setupWords(for: Frame(screen: .accessOff), in: s)?.headline == "Access is off")
        #expect(Labels.row(.getPremium, on: .premium, in: s).label == "Get Premium")
        s.words = .appleMusic
        #expect(Labels.row(.getPremium, on: .premium, in: s).label == "Get Apple Music")
        let words = Labels.setupWords(for: Frame(screen: .premium), in: s)
        #expect(words == Labels.SetupWords(headline: "Not subscribed", line: "To play music, we need Apple Music."))
    }

    /// Card BI v2: the beta screens' words (233, 234), the tag (279) and About's version (235).
    @Test func betaScreensUseTheCardWords() throws {
        var s = sampleState()
        let end = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 14, hour: 12)))
        s.beta = BetaBuild(signed: end.timeIntervalSinceReferenceDate - 30 * BetaBuild.day)
        #expect(Labels.title(.betaSoon, in: s) == "Beta" && Labels.title(.betaEnded, in: s) == "Beta")
        #expect(Labels.message(for: Frame(screen: .betaSoon), in: s) == nil)  // its rows show
        #expect(Labels.setupWords(for: Frame(screen: .betaSoon), in: s)
            == .init(headline: "Time for a fresh beta", line: "Get it any time before 14 Dec."))
        #expect(Labels.setupWords(for: Frame(screen: .betaEnded), in: s)
            == .init(headline: "This beta has ended", line: "Get the new beta to keep listening."))
        #expect(Labels.row(.getNewBeta, on: .betaSoon, in: s) == .init(label: "Get New Beta"))
        #expect(Labels.row(.later, on: .betaSoon, in: s) == .init(label: "Later"))
        #expect(Labels.row(.quit, on: .betaEnded, in: s) == .init(label: "Quit"))
        #expect(Labels.aboutVersion(in: s, build: "209") == "\(Labels.version) Beta 209")
        for screen in [Screen.tracks(playlist: Playlist.likedSongsID), .now, .about] {
            #expect(Labels.betaTag(on: screen, in: s))
        }
        for screen in [Screen.main, .playlists, .albums, .artists, .settings, .betaSoon, .betaEnded, .login] {
            #expect(!Labels.betaTag(on: screen, in: s))
        }
        s.beta = nil  // an ad-hoc build
        #expect(Labels.aboutVersion(in: s, build: "209") == Labels.version)
        #expect(!Labels.betaTag(on: .now, in: s))
    }

    /// Round 13 setup: the titles, the color rows, and the words that show until each screen is drawn.
    @Test func setupScreensUseTheBoardWords() {
        let s = sampleState()
        #expect(Labels.title(.color, in: s) == "Pick Your Color" && Labels.title(.yourMusic, in: s) == "Your Music")
        #expect(Labels.title(.spotifyApp, in: s) == "Spotify App" && Labels.title(.hello, in: s) == "")
        #expect(Labels.row(.color(.black), on: .color, in: s) == Labels.RowText(label: "Black"))
        #expect(Labels.message(for: Frame(screen: .hello), in: s) == nil)  // PocketHello draws it
        #expect(Labels.message(for: Frame(screen: .spotifyApp), in: s) == nil)  // card BB: its row shows
        let bb = Labels.setupWords(for: Frame(screen: .spotifyApp), in: s)
        #expect(bb == .init(headline: "One more thing", line: "We also need the Spotify app on this Mac."))
        #expect(Labels.row(.getSpotifyApp, on: .spotifyApp, in: s) == .init(label: "Get Spotify App"))
        // Card AX, screen 135 (CLA-66): no chevrons, and the login's title.
        #expect(Labels.title(.premium, in: s) == "Log In" && Labels.message(for: Frame(screen: .premium), in: s) == nil)
        let premium = Labels.setupWords(for: Frame(screen: .premium), in: s)
        #expect(premium == .init(headline: "Premium needed", line: "To play music, we need Spotify Premium."))
        #expect(Labels.row(.checkPremium, on: .premium, in: s) == .init(label: "Check again"))
        #expect(Labels.row(.getPremium, on: .premium, in: s) == .init(label: "Get Premium"))
        #expect(Labels.row(.premiumLogOut, on: .premium, in: s) == .init(label: "Log out"))
        #expect(PreviewScreen.of(.premium, in: s)?.screen == .mark(ok: false, word: "No Premium"))
        #expect(PreviewScreen.of(.premium, in: s)?.cable == .on)  // plugged in, the light resting
        #expect(SyncCable.lightOnce(at: -0.1).opacity == 0 && SyncCable.lightOnce(at: 1.1).opacity == 0)
        #expect(SyncCable.lightOnce(at: 0.5).opacity == 1 && abs(SyncCable.lightOnce(at: 0.5).distance - 75) < 0.5)
        // Card AY: the read, then "You’re all set" with the count.
        #expect(Labels.message(for: Frame(screen: .yourMusic, loading: true), in: s) == nil)
        #expect(Labels.setupWords(for: Frame(screen: .yourMusic, loading: true), in: s)?.headline == "Getting your music")
        #expect(Labels.setupWords(for: Frame(screen: .yourMusic), in: s)?.headline == "You’re all set")
        // Change 189: the same line for any library, with no song count.
        #expect(Labels.setupWords(for: Frame(screen: .yourMusic), in: s)?.line == "Enjoy your music.")
        // Card AY, change 188: three counts. Each shows when its number is known.
        func words(_ c: [(number: String, words: String)?]) -> [String?] { c.map { $0.map { "\($0.number) \($0.words)" } } }
        #expect(words(SetupProgress.counts(done: 0, total: 0, playlists: nil, albums: 0)) == [nil, nil, nil])
        #expect(SetupProgress.label(SetupProgress.counts(done: 0, total: 0, playlists: nil, albums: 0)) == "Getting your music")
        let counts = SetupProgress.counts(done: 1300, total: 1240, playlists: 107, albums: 84)
        #expect(words(counts) == ["107 playlists", "84 albums", "\(1240.formatted()) liked songs"])
        #expect(words(SetupProgress.counts(done: 1, total: 2, playlists: 1, albums: 1)) == ["1 playlist", "1 album", "1 liked song"])
        #expect(SetupProgress.label(counts) == "107 playlists, 84 albums, \(1240.formatted()) liked songs")
        // On Apple Music the count is the whole library: "songs", as Apple's own library says.
        let apple = (one: LibraryWords.appleMusic.oneSong, many: LibraryWords.appleMusic.manySongs)
        #expect(words(SetupProgress.counts(done: 631, total: 631, playlists: 3, albums: 52, songWords: apple)) == ["3 playlists", "52 albums", "631 songs"])
        #expect(words(SetupProgress.counts(done: 1, total: 1, playlists: 1, albums: 1, songWords: apple)) == ["1 playlist", "1 album", "1 song"])
        let spotify = (one: LibraryWords.spotify.oneSong, many: LibraryWords.spotify.manySongs)
        #expect(words(SetupProgress.counts(done: 1300, total: 1240, playlists: 107, albums: 84, songWords: spotify)) == words(counts))
        // CLA-84: the number column is as wide as the largest final count from the start.
        #expect(SetupProgress.widest(playlists: 107, albums: 84, total: 1240) == 1240.formatted())
        #expect(SetupProgress.widest(playlists: 2100, albums: 84, total: 455) == 2100.formatted())
        #expect(SetupProgress.widest(playlists: nil, albums: 0, total: 0) == "0")
        // Change 197: the bar and the counts grow steadily over the name time: 0.5 + 0.34 × 5 + 0.3 = 2.5 s for 6 names (CLA-80),
        // with 100 songs or more, or before the count is known (change 266).
        for songs in [nil, 100, 5000] as [Int?] {
            #expect(SetupProgress.grow(at: -1, names: 6, songs: songs) == 0 && abs(SetupProgress.grow(at: 1.25, names: 6, songs: songs) - 0.5) < 1e-9)
            #expect(SetupProgress.grow(at: 2.4, names: 6, songs: songs) < 1 && SetupProgress.grow(at: 2.51, names: 6, songs: songs) == 1)
        }
        #expect(SetupProgress.grow(at: 0.4, names: 1, songs: nil) == 0.5 && SetupProgress.grow(at: 0, names: 0, songs: nil) == 1)  // no names: the real values
        // Change 266: 20 songs or fewer take 1 s; 60 songs take 1.75 s.
        #expect(abs(SetupProgress.grow(at: 0.5, names: 6, songs: 15) - 0.5) < 1e-9 && SetupProgress.grow(at: 1.01, names: 6, songs: 15) == 1)
        #expect(abs(SetupProgress.grow(at: 0.875, names: 6, songs: 60) - 0.5) < 1e-9)
        let half = SetupProgress.shown(done: 455, total: 455, playlists: 107, albums: 84, grow: 0.5)
        #expect(half.done == 227 && half.playlists == 53 && half.albums == 42)  // rounded down
        let full = SetupProgress.shown(done: 455, total: 455, playlists: 107, albums: 84, grow: 1)
        #expect(full.done == 455 && full.playlists == 107 && full.albums == 84)  // they end at the real totals
        #expect(SetupProgress.shown(done: 100, total: 455, playlists: nil, albums: 30, grow: 0.5).done == 100)  // a slower read
        // Change 265: the bar fills smoothly, not in whole songs; the count stays a whole number.
        #expect(abs(SetupProgress.fill(done: 15, total: 15, grow: 0.53) - 0.53) < 1e-9)
        #expect(SetupProgress.shown(done: 15, total: 15, playlists: nil, albums: 0, grow: 0.53).done == 7)
        #expect(abs(SetupProgress.fill(done: 100, total: 400, grow: 0.5) - 0.25) < 1e-9)  // a slower read
        #expect(SetupProgress.fill(done: 0, total: 0, grow: 1) == 0 && SetupProgress.fill(done: 9, total: 8, grow: 1) == 1)
        // Liked Songs read before the list came: 0 until the list comes, then it grows from 0.
        #expect(SetupProgress.grow(now: 100, namesFrom: nil, names: 0, songs: 15, waiting: true) == 0)
        #expect(SetupProgress.grow(now: 101, namesFrom: 101, names: 6, songs: nil, waiting: false) == 0)
        #expect(abs(SetupProgress.grow(now: 102.25, namesFrom: 101, names: 6, songs: nil, waiting: false) - 0.5) < 1e-9)
        #expect(abs(SetupProgress.grow(now: 101.5, namesFrom: 101, names: 6, songs: 15, waiting: false) - 0.5) < 1e-9)
        // A count that comes 1.5 s after the names: the rest in 0.2 s.
        #expect(abs(SetupProgress.grow(now: 102.6, namesFrom: 101, names: 6, songs: 15, late: 1.5, waiting: false) - 0.8) < 1e-9)
        #expect(SetupProgress.grow(now: 100, namesFrom: nil, names: 0, songs: nil, waiting: false) == 1)  // the list read failed: the real values
        #expect(Labels.message(for: Frame(screen: .color), in: s) == nil)
    }

    /// Card AX: each login screen has its own headline, and only the first has the footnote.
    @Test func theLoginScreensUseTheBoardWords() {
        var s = sampleState()
        let words = { (screen: Screen) in Labels.setupWords(for: Frame(screen: screen), in: s) }
        #expect(words(.login) == .init(headline: "Your music is on Spotify", line: "We’ll open your browser.", footnote: "We never see your password."))
        #expect(words(.auth) == .init(headline: "Take your time", line: "Your browser is open.\nLog in there."))
        #expect(words(.loginFailed) == .init(headline: "That didn’t work", line: "No problem, it happens."))
        #expect(words(.loggedIn) == .init(headline: "You’re in", line: "Nice to meet you."))
        s.sessionEnded = true  // change 181: the same screen after the session expired
        #expect(words(.login) == .init(headline: "Log in again", line: "Your Spotify session ended.", footnote: "We never see your password."))
        #expect(words(.auth)?.headline == "Take your time" && words(.loginFailed)?.headline == "That didn’t work")
        s.sessionEnded = false
        #expect(words(.main) == nil && words(.color) == nil)
        #expect(Labels.row(.logIn, on: .login, in: s) == .init(label: "Log in with Spotify"))  // no chevron
        #expect(Labels.row(.openBrowser, on: .auth, in: s).label == "Open browser again")
        #expect(Labels.row(.tryAgain, on: .loginFailed, in: s).label == "Try again")
        s.restoring = true  // "Signing in…" shows on the whole screen, as before
        #expect(words(.login) == nil && Labels.title(.login, in: s) == "Clasify")
    }

    @Test func theSongPanelShowsTheAlbumAndItsSongs() {
        var s = sampleState()
        let album = Album(id: "spotify:album:n", name: "Nevermind", artist: "Nirvana")
        s.library[0].tracks[0].album = album
        s.library[0].tracks[0].duration = 219
        let title = s.library[0].tracks[0].title
        #expect(Labels.panel(album.id, in: s) == .init(album: "Nevermind", artist: "Nirvana", songs: [.init(title: title, length: "3:39")]))
        #expect(Labels.title(.albumPanel(album: album.id), in: s) == "Cover Flow")  // the title bar stays
        let row = Labels.row(.track(s.library[0].tracks[0].id), on: .albumPanel(album: album.id), in: s)
        #expect(row.label == title)
        #expect(Labels.panel("spotify:album:gone", in: s).songs.isEmpty)
    }

    @Test func albumRowsShowTheAlbumAndItsArtist() {
        var s = sampleState()
        let album = Album(id: "spotify:album:n", name: "Nevermind")  // no album artist from Spotify
        s.library[0].tracks[0].album = album
        #expect(Labels.title(.albums, in: s) == "Albums")
        #expect(Labels.row(.albums, on: .main, in: s) == .init(label: "Albums", opens: true))
        // Two lines, like a song row; the artist of its first song stands in.
        #expect(Labels.row(.album(album.id), on: .albums, in: s) == .init(label: "Nevermind", detail: "M.I.A."))
        #expect(Labels.title(.tracks(playlist: album.id), in: s) == "Nevermind")  // the album's song list
        s.current = TrackRef(playlist: album.id, track: "spotify:track:1")
        #expect(Labels.now(in: s)?.list == "Nevermind" && Labels.now(in: s)?.count == "1 of 1")
        s.stack = [Frame(screen: .main), Frame(screen: .albums), Frame(screen: .tracks(playlist: album.id))]
        s.library[0].tracks[0].album = nil  // its last song left Liked Songs
        #expect(Labels.message(for: s.top, in: s)?.body.hasPrefix("Spotify has no songs for this album") == true)
        s.stack.removeLast()
        #expect(Labels.message(for: s.top, in: s)?.title == "No albums")
        // Cover Flow shows the same albums, so it has the same words.
        #expect(Labels.title(.coverFlow, in: s) == "Cover Flow")
        #expect(Labels.row(.coverFlow, on: .main, in: s) == .init(label: "Cover Flow", opens: true))
        s.stack[s.stack.count - 1] = Frame(screen: .coverFlow)
        #expect(Labels.message(for: s.top, in: s)?.title == "No albums")
    }

    @Test func settingsRowsShowTheirValues() {
        var s = sampleState()
        s.shuffle = true
        s.repeatMode = .one
        s.albumArt = .off
        #expect(Labels.row(.shuffle, on: .settings, in: s) == .init(label: "Shuffle", value: "Songs"))
        #expect(Labels.row(.repeatMode, on: .settings, in: s) == .init(label: "Repeat", value: "One"))
        #expect(Labels.row(.skin, on: .settings, in: s) == .init(label: "Skin", value: "Pocket"))
        #expect(Labels.row(.albumArt, on: .settings, in: s) == .init(label: "Album Art", value: "Off"))
        s.albumArt = .nowPlaying
        #expect(Labels.row(.albumArt, on: .settings, in: s) == .init(label: "Album Art", value: "Now Playing"))
        s.albumArt = .all
        #expect(Labels.row(.albumArt, on: .settings, in: s) == .init(label: "Album Art", value: "All"))
        #expect(Labels.row(.deviceColor, on: .settings, in: s) == .init(label: "Color", value: "Silver"))  // change 169
        s.deviceColor = .black
        #expect(Labels.row(.deviceColor, on: .settings, in: s) == .init(label: "Color", value: "Black"))
        #expect(Labels.row(.clicker, on: .settings, in: s) == .init(label: "Clicker", value: "On"))
        #expect(Labels.row(.nowPlayingBar, on: .settings, in: s) == .init(label: "Now Playing Bar", value: "Off"))  // card AK
        #expect(Labels.row(.logOut, on: .settings, in: s) == .init(label: "Log out", opens: true))
    }

    @Test func thePlayingTrackRowShowsThePlayState() {
        var s = sampleState()
        let screen = Screen.tracks(playlist: "spotify:playlist:a")
        s.current = TrackRef(playlist: "spotify:playlist:a", track: "spotify:track:r2")
        s.isPlaying = true
        #expect(Labels.row(.track("spotify:track:r2"), on: screen, in: s) == .init(label: "Song 2", detail: "Band 2", playing: true))
        #expect(Labels.row(.track("spotify:track:r3"), on: screen, in: s) == .init(label: "Song 3", detail: "Band 3"))
        s.isPlaying = false
        #expect(Labels.row(.track("spotify:track:r2"), on: screen, in: s).playing)  // paused: still the speaker
    }

    @Test func messagesCoverTheScreensWithNoList() {
        var s = sampleState()
        var frame = Frame(screen: .playlists, loading: true)
        #expect(Labels.message(for: frame, in: s) == .init(title: "Loading…", spinner: true))
        frame.loading = false
        frame.error = true
        #expect(Labels.message(for: frame, in: s)?.title == "Can’t reach Spotify")
        #expect(Labels.message(for: Frame(screen: .playlists), in: s) == nil)
        #expect(Labels.message(for: Frame(screen: .tracks(playlist: "spotify:playlist:b")), in: s)?.title == "No songs")
        #expect(Labels.message(for: Frame(screen: .auth), in: s) == nil)  // card AX: its rows show
        #expect(Labels.message(for: Frame(screen: .about), in: s) == nil)  // About draws its own screen
        s.restoring = true
        #expect(Labels.message(for: Frame(screen: .login), in: s)?.title == "Signing in…")
    }

    @Test func nowPlayingTextShowsThePlaceInTheList() throws {
        var s = sampleState()
        s.current = TrackRef(playlist: "spotify:playlist:a", track: "spotify:track:r3")
        let now = try #require(Labels.now(in: s))
        #expect(now == .init(title: "Song 3", artist: "Band 3", list: "Road Trip", count: "3 of 12", duration: 180))
        s.current?.track = "spotify:track:unknown"  // not in Clasify's copy of the list
        #expect(Labels.now(in: s)?.title == "Spotify")  // never the raw ID
        #expect(Labels.now(in: s)?.artist == "")
        #expect(Labels.now(in: s)?.count == "")
        // After `.trackRead`, the details show, still with no place in the list.
        s.extraTracks = [Track(id: "spotify:track:unknown", title: "Radio", artist: "Band 9", duration: 200, coverID: "ab")]
        #expect(Labels.now(in: s) == .init(title: "Radio", artist: "Band 9", list: "Road Trip", count: "", duration: 200, coverID: "ab"))
    }

    @Test func playMarkFollowsThePlayState() {
        var s = sampleState()
        #expect(Labels.playMark(in: s) == nil)
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "spotify:track:1")
        #expect(Labels.playMark(in: s) == .paused)
        s.isPlaying = true
        #expect(Labels.playMark(in: s) == .playing)
    }

    @Test func slidersFollowTheNowPlayingMode() {
        var s = sampleState()
        #expect(Labels.slider(in: s) == nil)
        s.nowMode = .shuffle
        #expect(Labels.slider(in: s) == .init(name: "Shuffle", stops: ["Off", "Songs"], index: 0))
        s.nowMode = .repeatMode
        s.repeatMode = .all
        #expect(Labels.slider(in: s) == .init(name: "Repeat", stops: ["Off", "One", "All"], index: 2))
    }

    @Test func batteryShowsItsLevelColorAndMark() {
        var s = sampleState()
        #expect(Labels.battery(in: s) == nil)  // no battery: no icon
        s.battery = Battery(level: 0.45, charging: false, onPower: false)
        #expect(Labels.battery(in: s) == .init(level: 0.45, red: false, mark: nil, label: "Battery 45%"))
        s.battery = Battery(level: 0.1, charging: true, onPower: true)
        #expect(Labels.battery(in: s) == .init(level: 0.1, red: true, mark: .bolt, label: "Battery 10%, charging"))
        s.battery = Battery(level: 1, charging: false, onPower: true)
        #expect(Labels.battery(in: s) == .init(level: 1, red: false, mark: .plug, label: "Battery 100%, on power"))
    }

    @Test func times() {
        #expect(Labels.time(0) == "0:00")
        #expect(Labels.time(65.9) == "1:05")
        #expect(Labels.time(-3) == "0:00")
        #expect(Labels.time(.nan) == "0:00")
    }
}

@Suite @MainActor struct InputTests {
    @Test func keysMapToTheMockupActions() {
        #expect(PocketSkin.action(for: .upArrow) == .wheel(-1))
        #expect(PocketSkin.action(for: .downArrow) == .wheel(1))
        #expect(PocketSkin.action(for: .return) == .select)
        #expect(PocketSkin.action(for: .escape) == .menu)
        #expect(PocketSkin.action(for: .delete) == .menu)
        #expect(PocketSkin.action(for: .space) == .play)
        #expect(PocketSkin.action(for: .rightArrow) == .next)
        #expect(PocketSkin.action(for: "s") == .toggleShuffle)
        #expect(PocketSkin.action(for: "R") == .cycleRepeat)
        #expect(PocketSkin.action(for: .leftArrow) == .prev)
        #expect(PocketSkin.action(for: "x") == nil)
        #expect(PocketSkin.repeats(.wheel(1)))
        #expect(!PocketSkin.repeats(.play) && !PocketSkin.repeats(.select) && !PocketSkin.repeats(.next))
    }

    @Test func windowKeysMapToTheDeviceKeys() {
        #expect(KeyCatcher.key(keyCode: 126, characters: nil) == .upArrow)
        #expect(KeyCatcher.key(keyCode: 125, characters: nil) == .downArrow)
        #expect(KeyCatcher.key(keyCode: 123, characters: nil) == .leftArrow)
        #expect(KeyCatcher.key(keyCode: 124, characters: nil) == .rightArrow)
        #expect(KeyCatcher.key(keyCode: 36, characters: "\r") == .return)
        #expect(KeyCatcher.key(keyCode: 76, characters: "\u{3}") == .return)
        #expect(KeyCatcher.key(keyCode: 53, characters: nil) == .escape)
        #expect(KeyCatcher.key(keyCode: 51, characters: nil) == .delete)
        #expect(KeyCatcher.key(keyCode: 49, characters: " ") == .space)
        #expect(KeyCatcher.key(keyCode: 1, characters: "s") == "s")
        #expect(KeyCatcher.key(keyCode: 15, characters: "R") == "R")
        #expect(KeyCatcher.key(keyCode: 0, characters: nil) == nil)
        #expect(KeyCatcher.key(keyCode: 0, characters: "") == nil)
        #expect(PocketSkin.action(for: KeyCatcher.key(keyCode: 15, characters: "r")!) == .cycleRepeat)
    }

    @Test func menuShortcutKeysPassOn() {
        #expect(KeyCatcher.takes([]))
        #expect(KeyCatcher.takes([.shift, .capsLock]))
        #expect(KeyCatcher.takes([.numericPad, .function]))  // arrow keys carry these
        #expect(!KeyCatcher.takes([.command]))
        #expect(!KeyCatcher.takes([.option]))
        #expect(!KeyCatcher.takes([.control]))
        #expect(!KeyCatcher.takes([.shift, .command]))
    }

    /// CLA-79: keys for the device window, or for no window while the device is in front.
    @Test func windowKeysGoToTheDeviceOnly() {
        let device = NSObject(), help = NSObject()
        #expect(KeyCatcher.isForDevice(event: device, device: device, front: device, active: true))
        #expect(KeyCatcher.isForDevice(event: device, device: device, front: help, active: false))  // its own key event
        #expect(KeyCatcher.isForDevice(event: nil, device: device, front: device, active: true))  // the plain window is not key
        #expect(!KeyCatcher.isForDevice(event: nil, device: device, front: device, active: false))  // another app
        #expect(!KeyCatcher.isForDevice(event: nil, device: device, front: help, active: true))  // How to Use in front
        #expect(!KeyCatcher.isForDevice(event: nil, device: device, front: nil, active: true))
        #expect(!KeyCatcher.isForDevice(event: help, device: device, front: device, active: true))  // How to Use is key
    }

    @Test func wheelZonesFollowTheMockup() {
        // The 225 point wheel: its center is at 112.5, and the center button's radius is 40.8.
        #expect(ClickWheel.zone(at: CGPoint(x: 112.5, y: 112.5)) == .center)
        #expect(ClickWheel.zone(at: CGPoint(x: 140, y: 140)) == .center)
        #expect(ClickWheel.zone(at: CGPoint(x: 112.5, y: 18)) == .menu)
        #expect(ClickWheel.zone(at: CGPoint(x: 24, y: 112.5)) == .prev)
        #expect(ClickWheel.zone(at: CGPoint(x: 201, y: 112.5)) == .next)
        #expect(ClickWheel.zone(at: CGPoint(x: 112.5, y: 206)) == .play)
        #expect(ClickWheel.zone(at: CGPoint(x: 70, y: 45)) == nil)  // the ring between buttons
        #expect(ClickWheel.zone(at: CGPoint(x: 2, y: 2)) == nil)  // outside the circle
    }

    @Test func clockwiseAnglesGrow() {
        let right = ClickWheel.angle(of: CGPoint(x: 220, y: 112.5))
        let below = ClickWheel.angle(of: CGPoint(x: 112.5, y: 220))
        #expect(abs(right) < 0.001)
        #expect(abs(below - 90) < 0.001)  // a quarter turn clockwise
    }

    @Test func clickIsAShortMonoWAV() {
        let wav = Clicker.wav()
        let samples = Clicker.samples()
        #expect(samples.count == 528)  // 11.979 ms at 44.1 kHz
        let size: Int = 44 + samples.count * 2  // the header, then 16-bit samples
        #expect(wav.count == size)
        #expect(wav.prefix(4) == Data("RIFF".utf8))
    }

    /// CLA-87: the N24 click. The spot values come from the formula in the spec, worked out
    /// apart from this code.
    @Test func theN24ClickPeaksAt028AndFadesToZero() {
        let samples = Clicker.samples()
        #expect(Clicker.modes.count == 24)
        let peak = samples.map { abs(Int($0)) }.max() ?? 0
        #expect((9174...9175).contains(peak))  // peak 0.28 of 32767 (CLA-91)
        #expect(Int(samples[48]) == peak)  // the peak is at 1.09 ms
        #expect(samples.last == 0)  // the fade ends at 0
        for (i, value) in [(0, 752), (10, 218), (24, 3495), (100, -1401), (300, -85)] {
            #expect(abs(Int(samples[i]) - value) <= 1, "sample \(i)")
        }
    }

    @Test func theMarqueeLoopFollowsTheLabelLength() {
        #expect(Labels.marqueeLoop(String(repeating: "x", count: 30)) == 11)  // 222 points: round(222 / 28 + 3)
        #expect(Labels.marqueeLoop(String(repeating: "夏", count: 17)) == 11)  // a CJK character counts as 13 points
        #expect(Labels.marqueeLoop("The Longest Road Trip Playlist Ever Made") == 14)  // 296 points
        #expect(Labels.marqueeLoop("Short") == 5)  // the shortest loop
    }

    /// Round 8 card AA: each long Now Playing line waits 1.5 s, scrolls once, then all rest 8 s.
    /// The title goes first, then the artist; a line that fits never takes a turn.
    @Test func longNowPlayingLinesScrollOnceEachInTurn() throws {
        let widths = [258.0, 166.5, 73.3]
        let room = Labels.nowRoom(art: true)
        #expect(room == 141.4 && Labels.nowRoom(art: false) == 284)
        let titleScroll = Labels.nowScrollSeconds(width: 258), artistScroll = Labels.nowScrollSeconds(width: 166.5)
        #expect(abs(titleScroll - 286.0 / 28) < 1e-9)  // the text and the 28 point gap, at 28 points a second
        let titleTurn = Labels.nowTurn(width: 258)
        #expect(abs(titleTurn - (1.5 + titleScroll + 8)) < 1e-9)
        func at(_ t: Double) -> Labels.NowScroll? { Labels.nowScroll(widths: widths, room: room, at: t) }
        #expect(at(0) == .init(line: 0, shift: 0))  // the wait
        #expect(at(1.4) == .init(line: 0, shift: 0))
        let half = try #require(at(1.5 + titleScroll / 2))
        #expect(half.line == 0 && abs(half.shift - 0.5) < 1e-9)
        #expect(at(1.5 + titleScroll + 1) == .init(line: 0, shift: 0))  // the rest
        let artist = try #require(at(titleTurn + 1.5 + artistScroll / 2))
        #expect(artist.line == 1 && abs(artist.shift - 0.5) < 1e-9)
        let total = titleTurn + Labels.nowTurn(width: 166.5)
        #expect(at(total + 0.5) == .init(line: 0, shift: 0))  // the turns start again
        // With no cover there is room for all, so nothing scrolls.
        #expect(Labels.nowScroll(widths: widths, room: Labels.nowRoom(art: false), at: 5) == nil)
        #expect(Labels.nowScroll(widths: [60, 166.5], room: room, at: 0)?.line == 1)
    }
}
