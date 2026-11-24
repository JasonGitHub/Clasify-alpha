import Foundation
import Testing
@testable import ClasifyCore

/// #436: the decisions of the local player. Each test names the case from Codex's reviews of #435.
@Suite struct LocalPlaybackTests {
    typealias Command = LocalPlayback.Command

    static func song(_ i: Int) -> LocalItem { LocalItem(id: "s\(i)", url: URL(fileURLWithPath: "/Music/s\(i).m4a")) }
    static func songs(_ n: Int) -> [LocalItem] { (0..<n).map(song) }
    static let cant = LocalPlayback.cantPlay

    /// Drives a `LocalPlayback` with a fixed random source, and remembers the ids it asked for.
    struct Driver {
        var p = LocalPlayback()
        var random = SeededRandom(state: 7)
        var readID = 0, checkID = 0, prepareID = 0

        @discardableResult mutating func on(_ event: LocalPlayback.Event) -> [Command] {
            let commands = p.handle(event, using: &random)
            for command in commands {
                switch command {
                case .read(_, _, let id): readID = id
                case .check(_, let id): checkID = id
                case .prepare(_, let id): prepareID = id
                default: break
                }
            }
            return commands
        }
        @discardableResult mutating func load(_ track: Int, autoplay: Bool = true, generation: Int = 1) -> [Command] {
            on(.load(track: "s\(track)", context: "c", autoplay: autoplay, generation: generation))
        }
        /// Loads song `at` of `n`, it opens, and the next song is queued.
        static func playing(_ n: Int, at: Int, autoplay: Bool = true) -> Driver {
            var d = Driver()
            d.load(at, autoplay: autoplay)
            d.on(.read(id: d.readID, items: songs(n)))
            d.on(.checked(id: d.checkID, ok: true))
            d.on(.prepared(id: d.prepareID, ok: true))
            return d
        }
    }

    static func reports(_ commands: [Command]) -> [Action] {
        commands.compactMap { if case .report(let action) = $0 { action } else { nil } }
    }

    @Test func aLoadOpensThePickedSongAndQueuesTheNext() {
        var d = Driver()
        #expect(d.load(1) == [.read(context: "c", track: "s1", id: d.readID)])
        #expect(!d.p.reportsPosition)
        #expect(d.on(.read(id: d.readID, items: Self.songs(3))) == [.check(Self.song(1).url, id: d.checkID)])
        #expect(d.on(.checked(id: d.checkID, ok: true)) == [
            .start(Self.song(1).url, seek: nil, play: true), .report(.trackChanged("s1", playing: true, generation: 1)),
            .prepare(Self.song(2).url, id: d.prepareID),
        ])
        #expect(d.p.reportsPosition)
        #expect(d.on(.prepared(id: d.prepareID, ok: true)) == [.queueNext(Self.song(2).url)])
        #expect(d.on(.songEnded(queued: true)) == [.adoptNext, .report(.trackChanged("s2", playing: true, generation: 1))])
    }

    @Test func case1PlayAfterTheEndStartsTheSongOnScreen() {
        var d = Driver.playing(2, at: 1)
        #expect(d.on(.songEnded(queued: false)) == [.stopAudio, .report(.trackEnded(generation: 1))])
        #expect(d.on(.play) == [.check(Self.song(1).url, id: d.checkID)])
    }

    @Test func case2AnEndDuringAFailedLoadShowsAfterIt() {
        var d = Driver.playing(2, at: 1)
        d.load(0, generation: 2)
        #expect(d.on(.songEnded(queued: false)) == [.stopAudio])  // nothing reported during the load
        #expect(Self.reports(d.on(.read(id: d.readID, items: nil))) == [
            .loadFailed(Self.cant, generation: 2), .trackChanged("s1", playing: false, generation: 2), .trackEnded(generation: 2),
        ])
    }

    @Test func case2AnAdvanceDuringAFailedLoadShowsTheNewSong() {
        var d = Driver.playing(3, at: 0)
        d.load(2, generation: 2)
        #expect(d.on(.songEnded(queued: true)) == [.adoptNext, .prepare(Self.song(2).url, id: d.prepareID)])
        #expect(Self.reports(d.on(.read(id: d.readID, items: nil))) == [
            .loadFailed(Self.cant, generation: 2), .trackChanged("s1", playing: true, generation: 2),
        ])
    }

    @Test func case3NextDuringALoadRunsAfterIt() {
        var d = Driver()
        d.load(0)
        #expect(d.on(.skip(forward: true, generation: 2)) == [])
        #expect(d.on(.read(id: d.readID, items: Self.songs(3))) == [.check(Self.song(1).url, id: d.checkID)])
    }

    @Test func case3And10NextOnTheLastSongDuringALoadEndsAndShowsIt() {
        var d = Driver()
        d.load(1)
        d.on(.skip(forward: true, generation: 2))
        #expect(d.on(.read(id: d.readID, items: Self.songs(2))) == [
            .stopAudio, .report(.trackChanged("s1", playing: false, generation: 2)), .report(.trackEnded(generation: 2)),
        ])
        #expect(d.on(.play) == [.check(Self.song(1).url, id: d.checkID)])
    }

    @Test func case4AFailedLoadKeepsThePlayStateFromBefore() {
        var d = Driver.playing(2, at: 0)
        d.load(1, autoplay: false, generation: 2)
        #expect(d.on(.read(id: d.readID, items: nil)) == [
            .report(.loadFailed(Self.cant, generation: 2)), .play, .report(.trackChanged("s0", playing: true, generation: 2)),
        ])
    }

    @Test func case5SkipsAfterTheEndGoOnAndPrevClearsTheEnd() {
        var d = Driver()
        d.load(1)
        for forward in [true, true, false] { d.on(.skip(forward: forward, generation: 2)) }
        #expect(d.on(.read(id: d.readID, items: Self.songs(2))) == [.check(Self.song(0).url, id: d.checkID)])
    }

    @Test func case6AnOlderOpenChangesNothing() {
        var d = Driver.playing(3, at: 0)
        d.on(.skip(forward: true, generation: 2))
        let older = d.checkID
        d.on(.skip(forward: true, generation: 3))
        #expect(d.on(.checked(id: older, ok: true)) == [])
        #expect(d.on(.checked(id: d.checkID, ok: true)).first == .start(Self.song(2).url, seek: nil, play: true))
    }

    @Test func case7AFailedLoadReportsTheOldSongPaused() {
        var d = Driver.playing(2, at: 0)
        d.on(.pause)
        d.load(1, autoplay: true, generation: 2)
        #expect(d.on(.read(id: d.readID, items: nil)) == [
            .report(.loadFailed(Self.cant, generation: 2)), .pause, .report(.trackChanged("s0", playing: false, generation: 2)),
        ])
    }

    @Test func case8PauseDuringAFailedLoadAppliesToTheOldSong() {
        var d = Driver.playing(2, at: 0)
        d.load(1, generation: 2)
        d.on(.pause)
        #expect(Self.reports(d.on(.read(id: d.readID, items: nil))).last == .trackChanged("s0", playing: false, generation: 2))
    }

    @Test func case9ADroppedSkipLeavesTheQueueAtTheSongThatPlays() {
        var d = Driver.playing(3, at: 0)
        d.on(.skip(forward: true, generation: 2))  // s1 is checked
        d.load(2, generation: 3)  // drops that open
        #expect(Self.reports(d.on(.read(id: d.readID, items: nil))).last == .trackChanged("s0", playing: true, generation: 3))
        #expect(d.on(.songEnded(queued: true)).contains(.report(.trackChanged("s1", playing: true, generation: 3))))
    }

    @Test func case11AFailedLoadAfterAReadKeepsTheOldSongsWithTheOldQueue() {
        var d = Driver.playing(5, at: 4)
        d.load(9, generation: 2)
        d.on(.read(id: d.readID, items: [Self.song(9)]))  // read; its open runs
        d.load(8, generation: 3)  // drops it, then fails
        #expect(Self.reports(d.on(.read(id: d.readID, items: nil))) == [
            .loadFailed(Self.cant, generation: 3), .trackChanged("s4", playing: true, generation: 3),
        ])
        #expect(d.p.now?.items == Self.songs(5))
    }

    @Test func case12NextThatEndsAnOpenShowsTheSongItReached() {
        var d = Driver.playing(2, at: 0)
        #expect(d.on(.skip(forward: true, generation: 2)) == [.check(Self.song(1).url, id: d.checkID)])
        #expect(d.on(.skip(forward: true, generation: 3)) == [
            .stopAudio, .report(.trackChanged("s1", playing: false, generation: 3)), .report(.trackEnded(generation: 3)),
        ])
        #expect(d.on(.play) == [.check(Self.song(1).url, id: d.checkID)])
    }

    @Test func case13ShuffleRequeuesTheNextSongOfTheOrderThatPlays() {
        var d = Driver.playing(6, at: 0)
        let commands = d.on(.shuffle(true))
        #expect(commands.first == .dropNext)
        guard case .prepare(let url, _) = commands.last, let next = d.p.upcoming else { Issue.record("no prepare"); return }
        #expect(url == Self.song(next).url)
        d.on(.prepared(id: d.prepareID, ok: true))
        d.load(5, generation: 2)
        d.on(.read(id: d.readID, items: nil))
        #expect(d.on(.songEnded(queued: true)).contains(.report(.trackChanged("s\(next)", playing: true, generation: 2))))
    }

    @Test func aSongThatDoesNotOpenIsSkippedOnceAndReported() {
        var d = Driver()
        d.load(0)
        d.on(.read(id: d.readID, items: Self.songs(3)))
        #expect(d.on(.checked(id: d.checkID, ok: false)) == [.check(Self.song(1).url, id: d.checkID)])
        #expect(Self.reports(d.on(.checked(id: d.checkID, ok: true))) == [
            .playbackFailed(Self.cant, generation: 1), .trackChanged("s1", playing: true, generation: 1),
        ])
    }

    @Test func whenNoSongOpensItStopsAndShowsThePickedSong() {
        var d = Driver()
        d.load(0)
        d.on(.read(id: d.readID, items: Self.songs(2)))
        d.on(.checked(id: d.checkID, ok: false))
        #expect(d.on(.checked(id: d.checkID, ok: false)) == [.stopAudio, .report(.playbackFailed(Self.cant, generation: 1))])
        #expect(!d.p.audioOn)
    }

    @Test func aBrokenSongIsReportedAndTheNextPlays() {
        var d = Driver.playing(2, at: 0)
        #expect(d.on(.songBroke) == [.stopAudio, .report(.playbackFailed(Self.cant, generation: 1)), .check(Self.song(1).url, id: d.checkID)])
    }

    @Test func aSeekDuringALoadRunsWhenTheSongStarts() {
        var d = Driver()
        d.load(0)
        #expect(d.on(.seek(30, generation: 2)) == [])
        d.on(.read(id: d.readID, items: Self.songs(1)))
        #expect(d.on(.checked(id: d.checkID, ok: true)).first == .start(Self.song(0).url, seek: 30, play: true))
    }

    @Test func stopClearsEverything() {
        var d = Driver.playing(2, at: 0)
        #expect(d.on(.stop) == [.stopAudio])
        #expect(d.p.now == nil && !d.p.audioOn)
        #expect(d.on(.play) == [])
    }

    @Test func repeatOneQueuesTheSameSongAgain() {
        var d = Driver.playing(2, at: 0)
        #expect(d.on(.repeatMode(.one)) == [.dropNext, .prepare(Self.song(0).url, id: d.prepareID)])
    }
}
