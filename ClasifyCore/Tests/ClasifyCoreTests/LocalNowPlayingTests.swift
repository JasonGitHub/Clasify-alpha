import Foundation
import Testing
@testable import ClasifyCore

/// CLA-179: the media keys and Now Playing state for local songs.
@Suite struct LocalNowPlayingTests {
    static func song(_ i: Int, title: String = "", artist: String = "", album: String = "", duration: Double = 0) -> LocalItem {
        LocalItem(id: "s\(i)", url: URL(fileURLWithPath: "/Music/Song \(i).m4a"), title: title, artist: artist, album: album, duration: duration)
    }
    static let songs = [
        song(0, title: "Zero", artist: "Band", album: "Record", duration: 200),
        song(1, title: "One", artist: "Band", album: "Record", duration: 180),
    ]

    /// Drives a `LocalPlayback` and the Now Playing state that follows it.
    struct Driver {
        var p = LocalPlayback()
        var now = LocalNowPlaying()
        var random = SeededRandom(state: 7)
        var readID = 0, checkID = 0, prepareID = 0
        /// Where the audio is, for Play and Pause.
        var time = 0.0

        mutating func on(_ event: LocalPlayback.Event) {
            let commands = p.handle(event, using: &random)
            for command in commands {
                switch command {
                case .read(_, _, let id): readID = id
                case .check(_, let id): checkID = id
                case .prepare(_, let id): prepareID = id
                default: break
                }
            }
            now.follow(commands, of: p, time: time)
        }

        /// Loads song `at` of `items`; it opens and the next one is queued.
        static func playing(_ items: [LocalItem] = LocalNowPlayingTests.songs, at: Int = 0, autoplay: Bool = true, active: Bool = true) -> Driver {
            var d = Driver()
            d.now.active = active
            d.on(.load(track: items[at].id, context: "c", autoplay: autoplay, generation: 1))
            d.on(.read(id: d.readID, items: items))
            d.on(.checked(id: d.checkID, ok: true))
            d.on(.prepared(id: d.prepareID, ok: true))
            return d
        }
    }

    @Test func itIsStoppedUntilLocalIsActiveAndASongIsOn() {
        var d = Driver.playing(active: false)
        #expect(d.now.state == .stopped && d.now.info == nil)  // Local is not the active service: the keys stay with other apps
        d.now.active = true
        #expect(d.now.state == .playing)
        d.on(.pause)
        #expect(d.now.state == .paused)
        d.on(.play)
        #expect(d.now.state == .playing)
        d.on(.stop)
        #expect(d.now.state == .stopped && d.now.song == nil && d.now.info == nil)
    }

    @Test func aStartThatDoesNotPlayIsPaused() {
        let d = Driver.playing(autoplay: false)
        #expect(d.now.state == .paused && d.now.info?.rate == 0)
    }

    @Test func theInfoComesFromTheLibrary() {
        let d = Driver.playing()
        #expect(d.now.info == LocalNowPlaying.Info(title: "Zero", artist: "Band", album: "Record", duration: 200, elapsed: 0, rate: 1))
    }

    @Test func emptyLibraryFieldsAreLeftOutAndTheTitleIsTheFileName() {
        let d = Driver.playing([Self.song(0), Self.song(1)])
        #expect(d.now.info == LocalNowPlaying.Info(title: "Song 0", artist: nil, album: nil, duration: nil, elapsed: 0, rate: 1))
    }

    @Test func theTimeFollowsPausePlayAndSeek() {
        var d = Driver.playing()
        d.time = 42
        d.on(.pause)
        #expect(d.now.info?.elapsed == 42 && d.now.info?.rate == 0)
        d.time = 42.5
        d.on(.play)
        #expect(d.now.info?.elapsed == 42.5 && d.now.info?.rate == 1)
        d.on(.seek(90, generation: 1))
        #expect(d.now.info?.elapsed == 90)
    }

    @Test func aLoadWithASeekStartsThere() {
        var d = Driver()
        d.now.active = true
        d.on(.load(track: "s1", context: "c", autoplay: true, generation: 1))
        d.on(.seek(30, generation: 1))
        d.on(.read(id: d.readID, items: Self.songs))
        d.on(.checked(id: d.checkID, ok: true))
        #expect(d.now.info?.title == "One" && d.now.info?.elapsed == 30)
    }

    @Test func theNextSongShowsWhenTheQueuedFileGoesOn() {
        var d = Driver.playing()
        d.time = 199
        d.on(.songEnded(queued: true))
        #expect(d.now.info == LocalNowPlaying.Info(title: "One", artist: "Band", album: "Record", duration: 180, elapsed: 0, rate: 1))
    }

    /// Codex on #447: Repeat One plays the same song again from 0, so the Mac gets a new time.
    @Test func aRepeatOfTheSameSongIsANewTime() {
        var d = Driver()
        d.now.active = true
        d.on(.repeatMode(.one))
        d.on(.load(track: "s0", context: "c", autoplay: true, generation: 1))
        d.on(.read(id: d.readID, items: Self.songs))
        d.on(.checked(id: d.checkID, ok: true))
        d.on(.prepared(id: d.prepareID, ok: true))
        let before = d.now
        d.on(.songEnded(queued: true))
        #expect(d.now.song?.id == "s0" && d.now.info?.elapsed == 0)
        #expect(d.now != before)  // so `LocalPlayer` shows it again
        let again = d.now
        d.on(.seek(0, generation: 1))
        #expect(d.now != again)
    }

    /// CTO on #445: after the end of the list the song rests, paused, so the Play key still comes
    /// to myPod (not to the Music app). Codex on #445: Play plays and Pause does nothing.
    @Test func afterTheEndTheSongRestsAsPaused() {
        var d = Driver.playing(at: 1)
        d.on(.songEnded(queued: false))
        #expect(d.now.state == .paused)
        #expect(d.now.info == LocalNowPlaying.Info(title: "One", artist: "Band", album: "Record", duration: 180, elapsed: 0, rate: 0))
        #expect(LocalNowPlaying.action(for: .play, playing: d.now.playing) == .play)
        #expect(LocalNowPlaying.action(for: .pause, playing: d.now.playing) == nil)
        d.on(.play)
        d.on(.checked(id: d.checkID, ok: true))
        #expect(d.now.state == .playing && d.now.song?.id == "s1")
    }

    @Test func nextOnTheLastSongRestsAsPaused() {
        var d = Driver.playing(at: 1)
        d.on(.skip(forward: true, generation: 2))
        #expect(d.now.state == .paused && d.now.song?.id == "s1")
    }

    /// Codex on #447: a new load whose file does not open leaves its song paused, not the old one.
    @Test func aLoadThatCannotOpenRestsOnItsOwnSong() {
        var d = Driver.playing()
        d.on(.load(track: "s1", context: nil, autoplay: true, generation: 2))
        d.on(.read(id: d.readID, items: [Self.songs[1]]))
        d.on(.checked(id: d.checkID, ok: false))
        #expect(d.now.state == .paused && d.now.song?.id == "s1")
    }

    @Test func otherCommandsChangeNothing() {
        var d = Driver.playing()
        let before = d.now
        d.on(.shuffle(false))
        d.on(.repeatMode(.off))
        d.on(.load(track: "s1", context: "c", autoplay: true, generation: 2))  // a read runs: the old song stays
        #expect(d.now == before)
    }

    /// CLA-179 keep awake: only while a song plays and Local is active.
    @Test func itKeepsTheMacAwakeOnlyWhileASongPlays() {
        var d = Driver.playing()
        #expect(d.now.keepsAwake)
        d.on(.pause)
        #expect(!d.now.keepsAwake)
        d.on(.play)
        #expect(d.now.keepsAwake)
        d.now.active = false  // a switch to another service
        #expect(!d.now.keepsAwake)
        d.now.active = true
        d.on(.songEnded(queued: true))  // the queued next song goes on
        #expect(d.now.keepsAwake)
        d.on(.songEnded(queued: false))  // the end of the list
        #expect(!d.now.keepsAwake)
        d.on(.play)
        d.on(.checked(id: d.checkID, ok: true))
        #expect(d.now.keepsAwake)
        d.on(.stop)
        #expect(!d.now.keepsAwake)
        #expect(!Driver.playing(active: false).now.keepsAwake)
        #expect(!Driver.playing(autoplay: false).now.keepsAwake)
    }

    /// The panel's cover is the shown song's library cover, the one the skins show.
    @Test func theInfoCarriesTheSongsCover() {
        let cover = LibraryCover.coverID(persistentID: 0xA1, side: 300)
        var withCover = Self.songs
        withCover[0].coverID = cover
        let d = Driver.playing(withCover)
        #expect(d.now.info?.cover == cover)
        var next = d
        next.on(.songEnded(queued: true))
        #expect(next.now.info?.cover == nil)  // the next song has none
    }

    /// The cover read is async: an image shows only while its song is still the shown one, and
    /// a song with no cover never keeps the last song's image.
    @Test func aCoverShowsOnlyForTheShownSong() {
        var cover = LocalCover()
        #expect(cover.show("a"))  // a new song: drop the old image, read "a"
        #expect(cover.wanted == "a" && cover.shown == nil)
        #expect(!cover.show("a"))  // the same song again (a pause, a seek): no new read
        #expect(cover.show("b"))  // the next song before "a" arrived
        #expect(!cover.arrived("a", found: true))  // too late: not taken
        #expect(cover.arrived("b", found: true) && cover.shown == "b")
        #expect(cover.show(nil))  // a song with no cover: the panel drops "b"
        #expect(cover.wanted == nil && cover.shown == nil)
        #expect(cover.show("c") && !cover.arrived("c", found: false))  // no image in the library
        #expect(cover.shown == nil)
    }

    @Test func eachKeyIsTheSkinsInputAction() {
        #expect(LocalNowPlaying.action(for: .play, playing: false) == .play)
        #expect(LocalNowPlaying.action(for: .play, playing: true) == nil)  // already playing: Play does not pause
        #expect(LocalNowPlaying.action(for: .pause, playing: true) == .play)
        #expect(LocalNowPlaying.action(for: .pause, playing: false) == nil)
        #expect(LocalNowPlaying.action(for: .toggle, playing: true) == .play)
        #expect(LocalNowPlaying.action(for: .toggle, playing: false) == .play)
        #expect(LocalNowPlaying.action(for: .next, playing: true) == .next)
        #expect(LocalNowPlaying.action(for: .previous, playing: false) == .prev)
    }
}
