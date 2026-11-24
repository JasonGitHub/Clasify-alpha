import AVFoundation
import ClasifyCore
import Foundation

/// CLA-179: plays local songs (the Music app library) inside myPod with `AVQueuePlayer`. Spotify and
/// Apple Music order their own queues; here `LocalQueue` does it. The player holds the song that
/// plays and the one after it, so the next song starts with no gap. Nothing is written to disk.
///
/// It reports like the other players: `.trackChanged`, `.position`, `.trackEnded`, `.loadFailed`
/// and `.playbackFailed`, each with the newest generation. A song whose file cannot open is
/// skipped: the next one that opens plays, and "That song can’t play here" shows once.
final class LocalPlayer: Player {
    /// Runs reported actions. Set it once the `Store` exists.
    var send: (Action) -> Void = { _ in }

    private let source: any LocalSource
    private let player = AVQueuePlayer()
    private static let cantPlay = "That song can’t play here"

    /// The newest generation of a load, seek, next or prev. Every report carries it.
    private var generation = 0
    /// Bumped by each load, skip and stop. An open that is not the newest stops at its next step.
    private var openID = 0
    /// The songs of the loaded context and their play order. nil: nothing loaded.
    private var items: [LocalItem] = []
    private var queue: LocalQueue?
    /// A load reads its songs. Next and Prev pressed then wait in `pendingSkips`, a seek in `pendingSeek`.
    private var loading = false
    private var pendingSkips: [Bool] = []
    private var pendingSeek: Double?
    /// The newest play or pause the user asked for. An open applies it when the song is ready.
    private var wantsPlay = false
    /// The play or pause from before a load, kept until the user presses Play or Pause: a load
    /// that fails leaves the old song as it was.
    private var playBeforeLoad: Bool?
    private var shuffle = false
    private var repeatMode = RepeatMode.off
    /// The player item of the current song, and the next song's item, already queued after it.
    private var currentItem: AVPlayerItem?
    private var upcoming: (index: Int, item: AVPlayerItem)?
    /// Bumped by each `prepareUpcoming`, so only the newest one queues a song.
    private var upcomingID = 0
    /// A song is being opened: the old song's state must not be reported with the new generation.
    private var opening = false
    private var observers: [NSObjectProtocol] = []
    private var timeObserver: Any?

    init(source: any LocalSource) {
        self.source = source
        player.actionAtItemEnd = .advance
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated { self?.ended(note.object as? AVPlayerItem) }
            },
            center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated { self?.broke(note.object as? AVPlayerItem) }
            },
        ]
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
    }

    func load(trackID: String, context: String?, autoplay: Bool, generation: Int) {
        self.generation = generation
        openID += 1
        let id = openID
        loading = true
        playBeforeLoad = playBeforeLoad ?? wantsPlay
        wantsPlay = autoplay
        pendingSkips = []
        pendingSeek = nil
        Task {
            var list = await source.items(context: context, track: trackID)
            if list?.contains(where: { $0.id == trackID }) != true, context != nil {
                list = await source.items(context: nil, track: trackID)  // not in the list: plays alone
            }
            guard id == openID else { return }
            loading = false
            let before = playBeforeLoad
            playBeforeLoad = nil
            guard let list, let start = list.firstIndex(where: { $0.id == trackID }) else {
                opening = false  // an older open stopped for this load; the old song plays on
                if let before { wantsPlay = before }
                send(.loadFailed(Self.cantPlay, generation: self.generation))
                return catchUp()
            }
            items = list
            var order = LocalQueue(count: list.count, start: start, shuffle: shuffle, repeatMode: repeatMode)
            let skips = pendingSkips
            pendingSkips = []
            var ended = false
            for forward in skips {  // Next and Prev pressed during the read, as they would run after it
                if forward {
                    if !ended { ended = order.next() == nil }  // Next on the last song, with Repeat Off
                } else {
                    _ = order.prev()
                    ended = false
                }
            }
            queue = order
            if ended { return endOfContext() }
            await open(id: id)
        }
    }

    func pause() {
        wantsPlay = false
        playBeforeLoad = nil
        player.pause()
    }

    func resume() {
        wantsPlay = true
        playBeforeLoad = nil
        guard !opening, !loading else { return }  // an open in flight plays when it is ready
        if currentItem != nil {
            player.play()
        } else if queue != nil {  // the context ended (or stopped on an error): the song on screen again
            openID += 1
            let id = openID
            Task { await open(id: id) }
        }
    }

    func stop() {
        loading = false
        wantsPlay = false
        playBeforeLoad = nil
        pendingSkips = []
        pendingSeek = nil
        stopPlayer()
        queue = nil
        items = []
    }

    func next(generation: Int) { skip(forward: true, generation: generation) }
    func prev(generation: Int) { skip(forward: false, generation: generation) }

    func setShuffle(_ on: Bool) {
        shuffle = on
        queue?.setShuffle(on)
        prepareUpcoming()
    }

    func setRepeat(_ mode: RepeatMode) {
        repeatMode = mode
        queue?.repeatMode = mode
        prepareUpcoming()
    }

    func seek(to seconds: Double, generation: Int) {
        self.generation = generation
        guard currentItem != nil, !loading, !opening else { pendingSeek = seconds; return }  // the open runs it
        player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600))
    }

    /// The player's own volume, not the Mac's.
    func setVolume(_ percent: Int) {
        player.volume = Float(min(max(percent, 0), 100)) / 100
    }

    private func skip(forward: Bool, generation: Int) {
        self.generation = generation
        pendingSeek = nil
        if loading { return pendingSkips.append(forward) }  // the load runs it
        guard var order = queue else { return }
        guard (forward ? order.next() : order.prev()) != nil else { return endOfContext() }
        queue = order
        openID += 1
        let id = openID
        Task { await open(id: id) }
    }

    /// Opens the queue's current song, or the first one after it that opens. A song that does
    /// not open is reported once, then skipped; when none opens, it all stops.
    private func open(id: Int) async {
        opening = true
        var skipped = false
        for _ in 0..<items.count {
            guard let index = queue?.current else { break }
            let ok = await Self.canPlay(items[index].url)
            guard id == openID else { return }
            if ok { return start(index, skipped: skipped) }
            skipped = true
            guard queue?.next() != nil else { break }
        }
        // No song of the context opens. Playback stops, so this is not `.loadFailed` (that shows the
        // song from before the load again, as if it played on): the picked song shows, not playing.
        stopPlayer()
        send(.playbackFailed(Self.cantPlay, generation: generation))
    }

    private func start(_ index: Int, skipped: Bool) {
        opening = false
        player.removeAllItems()
        upcoming = nil
        let item = AVPlayerItem(url: items[index].url)
        player.insert(item, after: nil)
        currentItem = item
        if let seek = pendingSeek { player.seek(to: CMTime(seconds: max(0, seek), preferredTimescale: 600)) }
        pendingSeek = nil
        if wantsPlay { player.play() } else { player.pause() }
        if skipped { send(.playbackFailed(Self.cantPlay, generation: generation)) }
        send(.trackChanged(items[index].id, playing: wantsPlay, generation: generation))
        prepareUpcoming()
    }

    /// Queues the song that plays when this one ends, so it starts with no gap. A song that does
    /// not open is not queued; at the end, `open` then skips it and says so.
    private func prepareUpcoming() {
        if let old = upcoming?.item, old !== player.currentItem { player.remove(old) }
        upcoming = nil
        upcomingID += 1
        // A copy of the queue: the real one moves only when the song really ends.
        guard var peek = queue, let now = currentItem, !opening, let index = peek.trackEnded() else { return }
        let id = upcomingID
        let url = items[index].url
        Task {
            guard await Self.canPlay(url), id == upcomingID, currentItem === now, player.currentItem === now else { return }
            let item = AVPlayerItem(url: url)
            player.insert(item, after: now)
            upcoming = (index, item)
        }
    }

    /// The current song played to its end.
    private func ended(_ item: AVPlayerItem?) {
        guard let item, item === currentItem, !loading, !opening, var order = queue else { return }
        guard let index = order.trackEnded() else { return endOfContext() }
        queue = order
        if let up = upcoming, up.index == index {
            if player.currentItem !== up.item { player.advanceToNextItem() }
            currentItem = up.item
            upcoming = nil
            send(.trackChanged(items[index].id, playing: wantsPlay, generation: generation))
            prepareUpcoming()
        } else {  // not queued yet, or it did not open
            openID += 1
            let id = openID
            Task { await open(id: id) }
        }
    }

    /// The current song stopped with an error (its file went away, its drive was disconnected).
    private func broke(_ item: AVPlayerItem?) {
        guard let item, item === currentItem, !loading, !opening, var order = queue else { return }
        send(.playbackFailed(Self.cantPlay, generation: generation))
        guard order.next() != nil else { return stopPlayer() }
        queue = order
        openID += 1
        let id = openID
        Task { await open(id: id) }
    }

    /// A load failed and the old song plays on. Its end was not handled during the load, so
    /// follow what the player did then: on to the queued song, or the end of the context.
    private func catchUp() {
        guard let item = currentItem, player.currentItem !== item else { return }
        if let up = upcoming, player.currentItem === up.item, var order = queue, order.trackEnded() == up.index {
            queue = order
            currentItem = up.item
            upcoming = nil
            send(.trackChanged(items[up.index].id, playing: wantsPlay, generation: generation))
            prepareUpcoming()
        } else {
            endOfContext()
        }
    }

    /// The last song ended (or Next on it) with Repeat Off. The queue stays, so Play starts the
    /// song on screen again.
    private func endOfContext() {
        stopPlayer()
        send(.trackEnded(generation: generation))
    }

    private func stopPlayer() {
        openID += 1
        upcomingID += 1
        opening = false
        player.pause()
        player.removeAllItems()
        currentItem = nil
        upcoming = nil
    }

    private func tick(_ seconds: Double) {
        guard !loading, !opening, currentItem != nil, player.currentItem === currentItem, player.timeControlStatus == .playing, seconds.isFinite else { return }
        send(.position(seconds, generation: generation))
    }

    /// The file opens and holds no protected (DRM) audio.
    private static func canPlay(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let loaded = try? await asset.load(.isPlayable, .hasProtectedContent) else { return false }
        return loaded.0 && !loaded.1
    }
}
