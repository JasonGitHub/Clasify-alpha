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
        #expect(Labels.title(.login, in: s) == "Clasify")
        #expect(Labels.title(.main, in: s) == "Clasify")
        #expect(Labels.title(.auth, in: s) == "Sign in")
        #expect(Labels.title(.tracks(playlist: "spotify:playlist:a"), in: s) == "Road Trip")
        #expect(Labels.title(.confirm, in: s) == "Log out?")
        #expect(Labels.title(.now, in: s) == "Now Playing")
    }

    /// Round 13 setup: the titles, the color rows, and the words that show until each screen is drawn.
    @Test func setupScreensUseTheBoardWords() {
        let s = sampleState()
        #expect(Labels.title(.color, in: s) == "Pick Your Color" && Labels.title(.yourMusic, in: s) == "Your Music")
        #expect(Labels.title(.spotifyApp, in: s) == "Spotify App" && Labels.title(.hello, in: s) == "")
        #expect(Labels.row(.color(.black), on: .color, in: s) == Labels.RowText(label: "Black"))
        #expect(Labels.message(for: Frame(screen: .hello), in: s) == nil)  // PocketHello draws it
        #expect(Labels.message(for: Frame(screen: .spotifyApp), in: s)?.title == "One more thing")
        #expect(Labels.message(for: Frame(screen: .color), in: s) == nil)
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
        #expect(Labels.row(.deviceColor, on: .settings, in: s) == .init(label: "Body", value: "Silver"))
        s.deviceColor = .black
        #expect(Labels.row(.deviceColor, on: .settings, in: s) == .init(label: "Body", value: "Black"))
        #expect(Labels.row(.clicker, on: .settings, in: s) == .init(label: "Clicker", value: "On"))
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
        #expect(Labels.message(for: Frame(screen: .auth), in: s)?.spinner == true)
        #expect(Labels.message(for: Frame(screen: .about), in: s) == nil)  // About draws its own screen
        #expect(Labels.aboutVersion == "Version \(Labels.version)")
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
        #expect(samples.count == 176)  // 4 ms at 44.1 kHz
        let size: Int = 44 + samples.count * 2  // the header, then 16-bit samples
        #expect(wav.count == size)
        #expect(wav.prefix(4) == Data("RIFF".utf8))
        #expect(samples.contains { $0 != 0 })
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
