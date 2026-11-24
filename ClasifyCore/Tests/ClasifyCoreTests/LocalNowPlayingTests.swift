import Foundation
import Testing
@testable import ClasifyCore

/// CLA-179: the media keys and Now Playing state for local songs.
@Suite struct LocalNowPlayingTests {
    let url = URL(fileURLWithPath: "/Music/s0.m4a")

    @Test func itIsStoppedUntilLocalIsActiveAndASongIsOn() {
        var now = LocalNowPlaying()
        now.apply(.start(url, seek: nil, play: true))
        now.apply(.report(.trackChanged("s0", playing: true, generation: 1)))
        #expect(now.state == .stopped)  // Local is not the active service: the keys stay with other apps
        now.active = true
        #expect(now.state == .playing)
        now.apply(.pause)
        #expect(now.state == .paused)
        now.apply(.play)
        #expect(now.state == .playing)
        now.apply(.stopAudio)
        #expect(now.state == .stopped && now.song == nil)
        now.active = false
        #expect(now.state == .stopped)
    }

    @Test func aStartThatDoesNotPlayIsPaused() {
        var now = LocalNowPlaying()
        now.active = true
        now.apply(.start(url, seek: 10, play: false))
        now.apply(.report(.trackChanged("s0", playing: false, generation: 1)))
        #expect(now.state == .paused)
    }

    @Test func otherCommandsChangeNothing() {
        var now = LocalNowPlaying()
        now.active = true
        let before = now
        for command: LocalPlayback.Command in [.read(context: nil, track: "s0", id: 1), .check(url, id: 1), .prepare(url, id: 2),
                                               .queueNext(url), .dropNext, .adoptNext, .seek(3), .report(.trackEnded(generation: 1))] {
            now.apply(command)
        }
        #expect(now == before)
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
