import AVFoundation
import ClasifyCore
import Foundation

/// CLA-179: plays local songs (the Music app library) inside myPod with `AVQueuePlayer`.
/// #436: every decision is in `LocalPlayback` (ClasifyCore, unit tested). This class only runs
/// the audio and the file checks: it sends what happened to `LocalPlayback` and runs the
/// commands that come back. Nothing is written to disk.
final class LocalPlayer: Player {
    /// Runs reported actions. Set it once the `Store` exists.
    var send: (Action) -> Void = { _ in }
    /// The store's `isPlaying`, which `.play` toggles. Set it with `send`. Until then, what the
    /// audio does (Codex on #445: not `wantsPlay`, which stays true after the end).
    var isPlaying: (() -> Bool)?

    private let source: any LocalSource
    private let player = AVQueuePlayer()
    private var playback = LocalPlayback()
    /// The media keys and Now Playing, only while Local is the active service. Made at the first
    /// `setActive(true)`: before that nothing touches `MPRemoteCommandCenter` or
    /// `MPNowPlayingInfoCenter`, so with Spotify active the hidden Spotify app keeps the keys.
    private var controls: LocalSystemControls?
    private var nowPlaying = LocalNowPlaying()
    /// Holds the Mac awake (no idle sleep) while `nowPlaying.keepsAwake`. nil: it may sleep.
    private var awake: NSObjectProtocol?
    /// The item of the song that plays, and the next song's item, queued after it.
    private var currentItem: AVPlayerItem?
    private var nextItem: AVPlayerItem?
    private var observers: [NSObjectProtocol] = []
    private var timeObserver: Any?

    init(source: any LocalSource) {
        self.source = source
        player.actionAtItemEnd = .advance
        let center = NotificationCenter.default
        observers = [
            // The queue is .main, so these run on the main actor. Only the item's identity (Sendable)
            // goes in: `Notification` is not Sendable.
            center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] note in
                let item = (note.object as? AVPlayerItem).map(ObjectIdentifier.init)
                MainActor.assumeIsolated { self?.ended(item, broke: false) }
            },
            center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] note in
                let item = (note.object as? AVPlayerItem).map(ObjectIdentifier.init)
                MainActor.assumeIsolated { self?.ended(item, broke: true) }
            },
        ]
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
    }

    func load(trackID: String, context: String?, autoplay: Bool, generation: Int) {
        handle(.load(track: trackID, context: context, autoplay: autoplay, generation: generation))
    }
    func pause() { handle(.pause) }
    func resume() { handle(.play) }
    func stop() { handle(.stop) }
    func next(generation: Int) { handle(.skip(forward: true, generation: generation)) }
    func prev(generation: Int) { handle(.skip(forward: false, generation: generation)) }
    func setShuffle(_ on: Bool) { handle(.shuffle(on)) }
    func setRepeat(_ mode: RepeatMode) { handle(.repeatMode(mode)) }
    func seek(to seconds: Double, generation: Int) { handle(.seek(seconds, generation: generation)) }

    /// CLA-168: `ServicePlayer` calls this at start and on each switch. The keys are myPod's
    /// only while Local is active.
    func setActive(_ on: Bool) {
        nowPlaying.active = on
        if on && controls == nil {
            let made = LocalSystemControls()
            // A key goes in as the skin's button: the same action, through the store.
            made.onCommand = { [weak self] command in
                guard let self, let action = LocalNowPlaying.action(for: command, playing: isPlaying?() ?? nowPlaying.playing) else { return }
                send(action)
            }
            controls = made
        }
        if on { controls?.activate() } else { controls?.deactivate() }
        controls?.show(nowPlaying)
        holdAwake()
    }

    /// The player's own volume, not the Mac's.
    func setVolume(_ percent: Int) {
        player.volume = Float(min(max(percent, 0), 100)) / 100
    }

    private func handle(_ event: LocalPlayback.Event) {
        let commands = playback.handle(event)
        for command in commands { run(command) }
        let before = nowPlaying
        let time = player.currentTime().seconds
        nowPlaying.follow(commands, of: playback, time: time.isFinite ? max(0, time) : 0)
        if nowPlaying != before { controls?.show(nowPlaying) }
        holdAwake()
    }

    /// The display may still sleep; only idle system sleep waits. A quit ends the hold with the app.
    private func holdAwake() {
        if nowPlaying.keepsAwake, awake == nil {
            awake = ProcessInfo.processInfo.beginActivity(options: .idleSystemSleepDisabled, reason: "Playing a song from this Mac")
        } else if !nowPlaying.keepsAwake, let held = awake {
            ProcessInfo.processInfo.endActivity(held)
            awake = nil
        }
    }

    private func run(_ command: LocalPlayback.Command) {
        switch command {
        case .read(let context, let track, let id):
            Task {
                var list = await source.items(context: context, track: track)
                if list?.contains(where: { $0.id == track }) != true, context != nil {
                    list = await source.items(context: nil, track: track)  // not in the list: plays alone
                }
                handle(.read(id: id, items: list))
            }
        case .check(let url, let id):
            Task { handle(.checked(id: id, ok: await Self.canPlay(url))) }
        case .prepare(let url, let id):
            Task { handle(.prepared(id: id, ok: await Self.canPlay(url))) }
        case .start(let url, let seek, let play):
            player.removeAllItems()
            nextItem = nil
            let item = AVPlayerItem(url: url)
            player.insert(item, after: nil)
            currentItem = item
            if let seek { player.seek(to: CMTime(seconds: seek, preferredTimescale: 600)) }
            if play { player.play() } else { player.pause() }
        case .queueNext(let url):
            guard let now = currentItem, player.currentItem === now else { return }
            let item = AVPlayerItem(url: url)
            player.insert(item, after: now)
            nextItem = item
        case .dropNext:
            if let item = nextItem, item !== player.currentItem { player.remove(item) }
            nextItem = nil
        case .adoptNext:
            currentItem = nextItem
            nextItem = nil
            if let item = currentItem, player.currentItem !== item { player.advanceToNextItem() }
        case .play: player.play()
        case .pause: player.pause()
        case .seek(let seconds): player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        case .stopAudio:
            player.pause()
            player.removeAllItems()
            currentItem = nil
            nextItem = nil
        case .report(let action): send(action)
        }
    }

    /// The song that plays ended, or stopped with an error (its file went away, its drive was disconnected).
    private func ended(_ item: ObjectIdentifier?, broke: Bool) {
        guard let item, item == currentItem.map(ObjectIdentifier.init) else { return }
        handle(broke ? .songBroke : .songEnded(queued: nextItem != nil))
    }

    private func tick(_ seconds: Double) {
        guard playback.reportsPosition, currentItem != nil, player.currentItem === currentItem,
              player.timeControlStatus == .playing, seconds.isFinite else { return }
        send(.position(seconds, generation: playback.generation))
    }

    /// The file opens and holds no protected (DRM) audio.
    private static func canPlay(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let loaded = try? await asset.load(.isPlayable, .hasProtectedContent) else { return false }
        return loaded.0 && !loaded.1
    }
}
