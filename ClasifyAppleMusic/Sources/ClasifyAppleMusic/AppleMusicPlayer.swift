import ClasifyCore
import Foundation
// MusicKit's request and item types are not Sendable in the macOS 15 SDK. This file uses them
// only on the main actor.
@preconcurrency import MusicKit

/// Plays Apple Music inside Clasify with MusicKit's `ApplicationMusicPlayer` (CLA-103). No
/// other app opens: the spike (CLA-102, build 164) showed no Music.app window and no Dock icon.
/// It needs the build signed with the Team ID, and MusicKit access that the user gave.
///
/// MusicKit has no callback for position or track end, so it polls the player every 0.5 s
/// while it has a queue, and reports `.position`, `.trackChanged` and `.trackEnded`.
public final class AppleMusicPlayer: Player {
    /// Runs reported actions. Set it once the `Store` exists.
    public var send: (Action) -> Void = { _ in } {
        didSet { if active, let percent = volume?.read() { send(.volumeReported(percent)) } }  // CLA-168
    }

    private var player: ApplicationMusicPlayer { ApplicationMusicPlayer.shared }
    /// The generation of the newest load, seek, next or prev. Every report carries it.
    private var generation = 0
    /// Bumped by each load and stop. A load that is not the newest stops at its next step.
    private var loadID = 0
    /// Set by `stop()` and cleared by the next load: nothing may play until then.
    private var stopped = true
    /// A load has not reported yet. The poller then reports nothing, because the old queue's
    /// state with the new generation would end the reducer's pending load too early.
    private var loading = false
    /// The newest play or pause the user asked for. A load applies it when it is ready, so a
    /// pause pressed during a load is kept.
    private var wantsPlay = false
    /// Next (true) and Prev (false) pressed during a load, in order, run once the queue is ready.
    private var pendingSkips: [Bool] = []
    /// The newest seek pressed during a load, run after the skips.
    private var pendingSeek: Double?
    private var poller: Timer?
    /// CLA-97: a playback error happened, and no song has played since.
    private var lostControl = false
    /// What the last poll saw, so that only changes are reported.
    private var lastTrack: String?
    private var lastPlaying = false
    private var shuffle = false
    private var repeatMode = RepeatMode.off
    /// A load set a queue. Before that, nothing here touches MusicKit, so a Spotify user never
    /// starts it.
    private var hasQueue = false
    /// The queued songs by their keys, to the store IDs that the library gave them. The queue's
    /// entries can carry other IDs than the library songs that we queued (build 177: a catalog
    /// ID, not checked on a Mac), so a poll finds the song by any of its keys.
    private var queued = QueueMatch()
    /// CLA-168: the device's output volume (the Mac's, from the app; nil where there is none),
    /// and whether Apple Music is the active service.
    private let volume: (any OutputVolume)?
    private var active = false
    private static let settle = 0.5
    private var quietUntil = Date.distantPast
    private var settling: Task<Void, Never>?

    public init(volume: (any OutputVolume)?) { self.volume = volume }

    public func load(trackID: String, context: String?, autoplay: Bool, generation: Int) {
        self.generation = generation
        loadID += 1
        stopped = false
        loading = true
        wantsPlay = autoplay
        pendingSkips = []
        pendingSeek = nil
        let id = loadID
        Task {
            guard let song = await AppleMusicReads.song(trackID) else {
                return fail("That song can’t play here", id: id, load: true)
            }
            var tracks: [Song]?
            if let context { tracks = await AppleMusicReads.songs(for: context) }
            guard id == loadID else { return }
            let list = tracks?.map { (id: AppleMusicID.song($0.id), keys: Self.keys($0)) } ?? []
            let start = QueueMatch.start(of: trackID, keys: Self.keys(song), in: list)
            if let tracks, let start {
                player.queue = ApplicationMusicPlayer.Queue(for: tracks, startingAt: tracks[start.index])
                queued = QueueMatch(list)
            } else {
                player.queue = ApplicationMusicPlayer.Queue(for: [song])  // not in the list: plays alone
                queued = QueueMatch([(id: trackID, keys: Self.keys(song))])
            }
            hasQueue = true
            applyModes()
            do {
                try await player.prepareToPlay()
                guard id == loadID else { return }
                if wantsPlay { try await player.play() }
            } catch {
                return fail("That song can’t play here", id: id, load: true, code: (error as NSError).code)
            }
            guard id == loadID else {
                // stop() ran during play(), for example on a service switch: play must not go on.
                // A newer load replaces the queue itself, so stop only when nothing newer started.
                if stopped { player.stop() }
                return
            }
            if !wantsPlay && player.state.playbackStatus == .playing { player.pause() }  // paused during play()
            let skips = pendingSkips, seek = pendingSeek
            pendingSkips = []
            pendingSeek = nil
            for forward in skips {
                if forward { _ = try? await player.skipToNextEntry() } else { _ = try? await player.skipToPreviousEntry() }
            }
            guard id == loadID else { return }
            if let seek { player.playbackTime = seek }
            loading = false
            lastPlaying = wantsPlay
            if skips.isEmpty {
                lastTrack = trackID
                send(.trackChanged(trackID, playing: wantsPlay, generation: self.generation))
            } else {
                lastTrack = nil  // the first poll reports the track that the skips reached
            }
            startPolling()
        }
    }

    public func pause() {
        wantsPlay = false
        guard hasQueue, !loading else { return }  // a load in flight applies it
        player.pause()
        lastPlaying = false
    }

    public func resume() {
        wantsPlay = true
        guard hasQueue, !stopped, !loading else { return }  // a load in flight applies it
        let id = loadID
        Task {
            guard id == loadID, wantsPlay else { return }  // a pause or stop came first
            do { try await player.play() } catch {
                fail("Apple Music can’t play now", id: id, load: false, code: (error as NSError).code)
            }
            if id != loadID && stopped { player.stop() }  // stop() ran during play()
            else if !wantsPlay { player.pause() }  // a pause came during play()
        }
    }

    public func stop() {
        loadID += 1  // a load or resume in flight must not report or play after this
        stopped = true
        loading = false
        wantsPlay = false
        guard hasQueue else { return }
        player.stop()
        poller?.invalidate()
        poller = nil
        lastTrack = nil
        lastPlaying = false
    }

    public func next(generation: Int) {
        self.generation = generation
        if loading { pendingSkips.append(true); pendingSeek = nil; return }  // the load runs it
        guard hasQueue else { return }
        Task { _ = try? await player.skipToNextEntry() }  // the next poll reports the new track
    }

    public func prev(generation: Int) {
        self.generation = generation
        if loading { pendingSkips.append(false); pendingSeek = nil; return }  // the load runs it
        guard hasQueue else { return }
        Task { _ = try? await player.skipToPreviousEntry() }
    }

    public func setShuffle(_ on: Bool) {
        shuffle = on
        applyModes()
    }

    public func setRepeat(_ mode: RepeatMode) {
        repeatMode = mode
        applyModes()
    }

    public func seek(to seconds: Double, generation: Int) {
        self.generation = generation
        if loading { pendingSeek = seconds; return }  // the load runs it
        guard hasQueue else { return }
        player.playbackTime = seconds
    }

    /// CLA-168: MusicKit has no volume control on the Mac (`MPVolumeView` does not work with
    /// `ApplicationMusicPlayer`), so the wheel sets the Mac's own output volume. The reports of
    /// our own writes wait until the wheel rests for `settle` seconds, then the real volume is
    /// reported once: a late echo of an older step must not move the bar back.
    public func setVolume(_ percent: Int) {
        volume?.write(percent)
        quietUntil = Date.now.addingTimeInterval(Self.settle)
        settling?.cancel()
        settling = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.settle))
            guard !Task.isCancelled, let self, self.active, let percent = self.volume?.read() else { return }
            self.send(.volumeReported(percent))
        }
    }

    /// CLA-168: Apple Music is the active service (or not). Active, the bar follows the Mac's
    /// volume: now, and on each change by the volume keys, the menu bar or a new output device.
    public func setActive(_ on: Bool) {
        active = on
        settling?.cancel()
        if on {
            volume?.onChange = { [weak self] percent in self?.heard(percent) }
            volume?.start()
        } else {
            volume?.stop()
        }
    }

    private func heard(_ percent: Int) {
        guard active, Date.now >= quietUntil else { return }
        send(.volumeReported(percent))
    }

    private func applyModes() {
        guard hasQueue else { return }
        player.state.shuffleMode = shuffle ? .songs : .off
        player.state.repeatMode = switch repeatMode {
        case .off: MusicPlayer.RepeatMode.none
        case .one: .one
        case .all: .all
        }
    }

    /// Reports with the newest generation: a Next or Prev during the load moved it on.
    /// CLA-203: `code` is MusicKit's error code, for the problem timeline. Only the number;
    /// nil when the song was not found (no error).
    private func fail(_ message: String, id: Int, load: Bool, code: Int? = nil) {
        guard id == loadID else { return }
        if let code { send(.note(.musicKitError(code))) }
        if load {  // the old queue, if any, plays on and reports again
            loading = false
            if hasQueue && !wantsPlay { player.pause() }  // the user paused during the load
        }
        send(load ? .loadFailed(message, generation: generation) : .playbackFailed(message, generation: generation))
        if !load {  // CLA-97: back at the next play
            lostControl = true
            send(.controlLost(.appleMusicError))
        }
    }

    private func startPolling() {
        guard poller == nil else { return }
        poller = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        guard !stopped, !loading else { return }  // stop() also ends the timer; this is a second guard
        let status = player.state.playbackStatus
        let playing = status == .playing
        if lastPlaying && status == .stopped {  // the queue ran out; Repeat All and One never end
            lastPlaying = false
            return send(.trackEnded(generation: generation))
        }
        // A song that we did not queue (none should come) keeps the last one: never report an
        // ID that the library did not give.
        let track = player.queue.currentEntry.flatMap(storeID) ?? lastTrack
        if let track, track != lastTrack || playing != lastPlaying {
            lastTrack = track
            lastPlaying = playing
            send(.trackChanged(track, playing: playing, generation: generation))
        }
        if playing && lostControl {  // CLA-97
            lostControl = false
            send(.controlBack)
        }
        if playing { send(.position(player.playbackTime, generation: generation)) }
    }

    /// The store ID of the song that a queue entry plays, or nil if it is not one that we queued.
    private func storeID(_ entry: ApplicationMusicPlayer.Queue.Entry) -> String? {
        if case .song(let song) = entry.item, let id = queued.id(for: Self.keys(song)) { return id }
        // Not resolved yet, or no known key: the title and artist that the entry shows.
        return entry.subtitle.flatMap { queued.id(title: entry.title, artist: $0) }
    }

    /// The keys that can name one song: its MusicKit ID, its catalog ID, its ISRC, and last its
    /// title with its artist.
    private static func keys(_ song: Song) -> SongKeys {
        SongKeys(
            ids: [song.id.rawValue] + (AppleMusicReads.catalogID(song).map { [$0] } ?? []),
            isrc: song.isrc, title: song.title, artist: song.artistName)
    }
}
