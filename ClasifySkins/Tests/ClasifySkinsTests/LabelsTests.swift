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

    @Test func settingsRowsShowTheirValues() {
        var s = sampleState()
        s.shuffle = true
        s.repeatMode = .one
        s.showArt = false
        #expect(Labels.row(.shuffle, on: .settings, in: s) == .init(label: "Shuffle", value: "Songs"))
        #expect(Labels.row(.repeatMode, on: .settings, in: s) == .init(label: "Repeat", value: "One"))
        #expect(Labels.row(.skin, on: .settings, in: s) == .init(label: "Skin", value: "Pocket"))
        #expect(Labels.row(.albumArt, on: .settings, in: s) == .init(label: "Album Art", value: "Off"))
        #expect(Labels.row(.clicker, on: .settings, in: s) == .init(label: "Clicker", value: "On"))
        #expect(Labels.row(.logOut, on: .settings, in: s) == .init(label: "Log out", opens: true))
    }

    @Test func thePlayingTrackRowShowsThePlayState() {
        var s = sampleState()
        let screen = Screen.tracks(playlist: "spotify:playlist:a")
        s.current = TrackRef(playlist: "spotify:playlist:a", track: "spotify:track:r2")
        s.isPlaying = true
        #expect(Labels.row(.track("spotify:track:r2"), on: screen, in: s) == .init(label: "Song 2", mark: .playing))
        #expect(Labels.row(.track("spotify:track:r3"), on: screen, in: s) == .init(label: "Song 3"))
        s.isPlaying = false
        #expect(Labels.row(.track("spotify:track:r2"), on: screen, in: s).mark == .paused)
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
        #expect(Labels.message(for: Frame(screen: .about), in: s)?.body == "Open source · MIT. Not affiliated with Spotify.")
        s.restoring = true
        #expect(Labels.message(for: Frame(screen: .login), in: s)?.title == "Signing in…")
    }

    @Test func nowPlayingTextShowsThePlaceInTheList() throws {
        var s = sampleState()
        s.current = TrackRef(playlist: "spotify:playlist:a", track: "spotify:track:r3")
        let now = try #require(Labels.now(in: s))
        #expect(now == .init(title: "Song 3", artist: "Band 3", list: "Road Trip", count: "3 of 12", duration: 180))
        s.current?.track = "spotify:track:unknown"  // not in Clasify's copy of the list
        #expect(Labels.now(in: s)?.title == "spotify:track:unknown")
        #expect(Labels.now(in: s)?.count == "")
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

    @Test func flagsAndTimes() {
        var s = sampleState()
        #expect(Labels.flags(in: s) == "")
        s.shuffle = true
        s.repeatMode = .all
        #expect(Labels.flags(in: s) == "SHUFFLE REPEAT")
        s.repeatMode = .one
        #expect(Labels.flags(in: s) == "SHUFFLE REPEAT 1")
        #expect(Labels.time(0) == "0:00")
        #expect(Labels.time(65.9) == "1:05")
        #expect(Labels.time(-3) == "0:00")
        #expect(Labels.time(.nan) == "0:00")
    }

    @Test func coverColorUsesTheMockupHash() {
        #expect(Labels.cover(for: "") == 0x6a54b0)  // h = 0
        #expect(Labels.cover(for: "A") == 0x2f6f99)  // h = 65, 65 % 8 = 1
        #expect(Labels.cover(for: "OutKast") == Labels.cover(for: "OutKast"))
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
        #expect(ClickWheel.zone(at: CGPoint(x: 98, y: 98)) == .center)
        #expect(ClickWheel.zone(at: CGPoint(x: 98, y: 25)) == .menu)
        #expect(ClickWheel.zone(at: CGPoint(x: 25, y: 98)) == .prev)
        #expect(ClickWheel.zone(at: CGPoint(x: 170, y: 98)) == .next)
        #expect(ClickWheel.zone(at: CGPoint(x: 98, y: 170)) == .play)
        #expect(ClickWheel.zone(at: CGPoint(x: 60, y: 40)) == nil)  // the ring between buttons
        #expect(ClickWheel.zone(at: CGPoint(x: 2, y: 2)) == nil)  // outside the circle
    }

    @Test func clockwiseAnglesGrow() {
        let right = ClickWheel.angle(of: CGPoint(x: 190, y: 98))
        let below = ClickWheel.angle(of: CGPoint(x: 98, y: 190))
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
}
