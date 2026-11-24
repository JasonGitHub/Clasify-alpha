import Foundation

/// #436: every decision of the local player, as a plain value. `LocalPlayer` runs the audio
/// (AVQueuePlayer) and the file checks; it sends each thing that happened here as a
/// `LocalPlayback.Event` and runs the `Command`s that come back, in their order.
///
/// The rule that keeps overlapping loads, skips and failures apart: `now` is what the audio plays
/// (or, after the end, the song that rests on screen). A load or a skip never changes `now`; it
/// works on `pending`, and only a song that opens moves `pending` into `now`. So a load that
/// fails, or a skip that a newer one drops, leaves `now` as it is, with its own songs and order.
public struct LocalPlayback: Sendable, Equatable {
    public enum Event: Sendable, Equatable {
        case load(track: String, context: String?, autoplay: Bool, generation: Int)
        /// The songs that read `id` found, or nil when the read failed or the song is not in them.
        case read(id: Int, items: [LocalItem]?)
        /// The file check `id` of `Command.check`: the file opens and holds no protected audio.
        case checked(id: Int, ok: Bool)
        /// The file check `id` of `Command.prepare`.
        case prepared(id: Int, ok: Bool)
        case skip(forward: Bool, generation: Int)
        /// The song the audio plays now ended by itself. `queued`: the next file was queued after
        /// it (`Command.queueNext` ran), so the audio goes on to it.
        case songEnded(queued: Bool)
        /// The song the audio plays now stopped with an error.
        case songBroke
        case play, pause, stop
        case seek(Double, generation: Int)
        case shuffle(Bool), repeatMode(RepeatMode)
    }

    public enum Command: Sendable, Equatable {
        /// Read the songs of `context` to play `track` from (`LocalSource.items`). Answer `.read(id:)`.
        case read(context: String?, track: String, id: Int)
        /// Check that the file opens. Answer `.checked(id:)`.
        case check(URL, id: Int)
        /// Play this file alone: remove all items, apply the seek, then play or pause.
        case start(URL, seek: Double?, play: Bool)
        /// Check the file of the next song. Answer `.prepared(id:)`.
        case prepare(URL, id: Int)
        /// Queue this file after the song that plays, so it starts with no gap.
        case queueNext(URL)
        /// Remove the queued next file, unless it already plays.
        case dropNext
        /// The audio moved on to the queued file: it is now the song that plays.
        case adoptNext
        case play, pause, seek(Double)
        /// Pause and remove all items.
        case stopAudio
        case report(Action)
    }

    /// The songs of one context and the play order in them.
    public struct Context: Sendable, Equatable {
        public var items: [LocalItem]
        public var queue: LocalQueue
        var song: LocalItem? { queue.current.map { items[$0] } }
    }

    enum Pending: Sendable, Equatable {
        /// The songs are being read. Next and Prev pressed meanwhile wait in `skips`.
        case load(id: Int, track: String, skips: [Bool])
        /// The song at `context.queue.current` is being checked. `tries` songs did not open before it.
        case open(id: Int, context: Context, tries: Int)
    }

    /// While a load or an open runs, the audio of `now` went on: what to show when the load fails.
    enum Missed: Sendable, Equatable { case advance, end }

    public static let cantPlay = "That song can’t play here"

    public private(set) var now: Context?
    /// The audio holds `now`'s current song (playing or paused).
    public private(set) var audioOn = false
    /// The index in `now` of the song queued after the current one, and the newest prepare.
    public private(set) var upcoming: Int?
    var prepareID: Int?
    var pending: Pending?
    var missed: Missed?
    public private(set) var wantsPlay = false
    /// The play or pause from before a load, kept until Play or Pause: a load that fails leaves the old song as it was.
    var playBeforeLoad: Bool?
    var pendingSeek: Double?
    public private(set) var generation = 0
    var shuffle = false
    var repeatMode = RepeatMode.off
    var lastID = 0

    public init() {}

    /// `.position` goes out only while the audio plays the song on screen.
    public var reportsPosition: Bool { audioOn && pending == nil }

    public mutating func handle(_ event: Event) -> [Command] {
        var random = SystemRandomNumberGenerator()
        return handle(event, using: &random)
    }

    public mutating func handle(_ event: Event, using random: inout some RandomNumberGenerator) -> [Command] {
        switch event {
        case .load(let track, let context, let autoplay, let generation):
            self.generation = generation
            playBeforeLoad = playBeforeLoad ?? wantsPlay
            wantsPlay = autoplay
            pendingSeek = nil
            let id = newID()
            pending = .load(id: id, track: track, skips: [])
            return [.read(context: context, track: track, id: id)]

        case .read(let id, let items):
            guard case .load(id, let track, let skips) = pending else { return [] }
            pending = nil
            let before = playBeforeLoad
            playBeforeLoad = nil
            guard let items, let start = items.firstIndex(where: { $0.id == track }) else {
                if let before { wantsPlay = before }
                return [.report(.loadFailed(Self.cantPlay, generation: generation))] + catchUp()
            }
            // `missed` stays until a song starts: a newer load can still drop this one (Codex on #441).
            var queue = LocalQueue(count: items.count, start: start, shuffle: shuffle, repeatMode: repeatMode, using: &random)
            var ended = false
            for forward in skips {  // as they would run after the read
                if forward {
                    if !ended { ended = queue.next() == nil }
                } else {
                    _ = queue.prev()
                    ended = false
                }
            }
            let context = Context(items: items, queue: queue)
            if ended { return end(at: context) }
            return open(context, tries: 0)

        case .checked(let id, let ok):
            guard case .open(id, var context, let tries) = pending else { return [] }
            if ok { return start(context, skipped: tries > 0) }
            // The song does not open: the next one, once round the context at most.
            guard tries + 1 < context.items.count, context.queue.next() != nil else {
                pending = nil
                now = context
                missed = nil
                return stopAudio() + [.report(.playbackFailed(Self.cantPlay, generation: generation))]
            }
            return open(context, tries: tries + 1)

        case .prepared(let id, let ok):
            guard id == prepareID, ok, audioOn, let index = upcoming, let now else { return [] }
            prepareID = nil
            return [.queueNext(now.items[index].url)]

        case .skip(let forward, let generation):
            self.generation = generation
            pendingSeek = nil
            switch pending {
            case .load(let id, let track, let skips):
                pending = .load(id: id, track: track, skips: skips + [forward])
                return []
            case .open(_, var context, _):
                guard (forward ? context.queue.next() : context.queue.prev()) != nil else { return end(at: context) }
                return open(context, tries: 0)
            case nil:
                guard var context = now else { return [] }
                guard (forward ? context.queue.next() : context.queue.prev()) != nil else { return end(at: context, show: false) }
                return open(context, tries: 0)
            }

        case .songEnded(let queued):
            guard audioOn, var context = now else { return [] }
            guard let index = context.queue.trackEnded() else {
                guard pending == nil else { missed = .end; return stopAudio() }
                return stopAudio() + [.report(.trackEnded(generation: generation))]
            }
            now = context
            if queued && index == upcoming {  // the queued file plays already
                upcoming = nil
                var commands: [Command] = [.adoptNext]
                if pending == nil {
                    commands.append(.report(.trackChanged(context.items[index].id, playing: wantsPlay, generation: generation)))
                } else {
                    missed = .advance
                }
                return commands + planNext()
            }
            guard pending == nil else { missed = .advance; return stopAudio() }
            return stopAudio() + open(context, tries: 0)

        case .songBroke:
            guard audioOn, var context = now else { return [] }
            guard pending == nil else {
                missed = context.queue.next() == nil ? .end : .advance
                now = context
                return stopAudio()
            }
            let failed = Command.report(.playbackFailed(Self.cantPlay, generation: generation))
            guard context.queue.next() != nil else { return stopAudio() + [failed] }
            return stopAudio() + [failed] + open(context, tries: 0)

        case .play:
            wantsPlay = true
            playBeforeLoad = nil
            if pending != nil { return [] }  // the open plays when the song is ready
            if audioOn { return [.play] }
            guard let now else { return [] }  // the context ended: the song on screen again
            return open(now, tries: 0)

        case .pause:
            wantsPlay = false
            playBeforeLoad = nil
            return [.pause]

        case .stop:
            pending = nil
            now = nil
            missed = nil
            wantsPlay = false
            playBeforeLoad = nil
            pendingSeek = nil
            return stopAudio()

        case .seek(let seconds, let generation):
            self.generation = generation
            guard audioOn, pending == nil else { pendingSeek = seconds; return [] }  // the open runs it
            return [.seek(max(0, seconds))]

        case .shuffle(let on):
            shuffle = on
            now?.queue.setShuffle(on, using: &random)
            if case .open(let id, var context, let tries) = pending {
                context.queue.setShuffle(on, using: &random)
                pending = .open(id: id, context: context, tries: tries)
            }
            return planNext()

        case .repeatMode(let mode):
            repeatMode = mode
            now?.queue.repeatMode = mode
            if case .open(let id, var context, let tries) = pending {
                context.queue.repeatMode = mode
                pending = .open(id: id, context: context, tries: tries)
            }
            return planNext()
        }
    }

    private mutating func newID() -> Int {
        lastID += 1
        return lastID
    }

    /// Check the context's current song; it plays when the check says it opens.
    private mutating func open(_ context: Context, tries: Int) -> [Command] {
        guard let song = context.song else { return [] }
        let id = newID()
        pending = .open(id: id, context: context, tries: tries)
        return [.check(song.url, id: id)]
    }

    private mutating func start(_ context: Context, skipped: Bool) -> [Command] {
        guard let song = context.song else { return [] }
        pending = nil
        missed = nil
        now = context
        audioOn = true
        upcoming = nil
        prepareID = nil
        var commands: [Command] = [.start(song.url, seek: pendingSeek.map { max(0, $0) }, play: wantsPlay)]
        pendingSeek = nil
        if skipped { commands.append(.report(.playbackFailed(Self.cantPlay, generation: generation))) }
        commands.append(.report(.trackChanged(song.id, playing: wantsPlay, generation: generation)))
        return commands + planNext()
    }

    /// The end of the context (Next on the last song, Repeat Off): the song the queue reached
    /// shows, not playing, and Play starts it again. `show`: that song is not on screen yet.
    private mutating func end(at context: Context, show: Bool = true) -> [Command] {
        pending = nil
        missed = nil
        now = context
        var commands = stopAudio()
        if show, let song = context.song { commands.append(.report(.trackChanged(song.id, playing: false, generation: generation))) }
        return commands + [.report(.trackEnded(generation: generation))]
    }

    private mutating func stopAudio() -> [Command] {
        audioOn = false
        upcoming = nil
        prepareID = nil
        return [.stopAudio]
    }

    /// Queue the song that plays when this one ends. Called after each change of `now`'s order.
    private mutating func planNext() -> [Command] {
        var commands: [Command] = upcoming != nil ? [.dropNext] : []
        upcoming = nil
        prepareID = nil
        guard audioOn, var peek = now, let index = peek.queue.trackEnded() else { return commands }
        let id = newID()
        upcoming = index
        prepareID = id
        commands.append(.prepare(peek.items[index].url, id: id))
        return commands
    }

    /// A load failed: report the old song as it is now. Play or Pause pressed during the load
    /// applies to it; what its audio did during the load shows now.
    private mutating func catchUp() -> [Command] {
        defer { missed = nil }
        guard let now, let song = now.song else { return [] }
        if audioOn {
            return [wantsPlay ? .play : .pause, .report(.trackChanged(song.id, playing: wantsPlay, generation: generation))]
        }
        switch missed {
        case .end:
            return [.report(.trackChanged(song.id, playing: false, generation: generation)), .report(.trackEnded(generation: generation))]
        case .advance:
            return open(now, tries: 0)
        case nil:
            return []
        }
    }
}
