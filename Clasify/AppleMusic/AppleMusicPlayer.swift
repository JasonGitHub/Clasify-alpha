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
final class AppleMusicPlayer: Player {
    /// Runs reported actions. Set it once the `Store` exists.
    var send: (Action) -> Void = { _ in }

    private var player: ApplicationMusicPlayer { ApplicationMusicPlayer.shared }
    /// The generation of the newest load, seek, next or prev. Every report carries it.
    private var generation = 0
    /// Bumped by each load and stop. A load that is not the newest stops at its next step.
    private var loadID = 0
    /// Set by `stop()` and cleared by the next load: nothing may play until then.
    private var stopped = true
    private var poller: Timer?
    /// What the last poll saw, so that only changes are reported.
    private var lastTrack: String?
    private var lastPlaying = false
    private var shuffle = false
    private var repeatMode = RepeatMode.off
    /// A load set a queue. Before that, nothing here touches MusicKit, so a Spotify user never
    /// starts it.
    private var hasQueue = false

    func load(trackID: String, context: String?, autoplay: Bool, generation: Int) {
        self.generation = generation
        loadID += 1
        stopped = false
        let id = loadID
        Task {
            guard let song = await Self.song(trackID) else {
                return fail("That song can’t play here", id: id, generation: generation, load: true)
            }
            var tracks: [Song]?
            if let context { tracks = await Self.playlistTracks(context) }
            guard id == loadID else { return }
            if let tracks, let start = tracks.first(where: { $0.id == song.id }) {
                player.queue = ApplicationMusicPlayer.Queue(for: tracks, startingAt: start)
            } else {
                player.queue = ApplicationMusicPlayer.Queue(for: [song])  // not in the list: plays alone
            }
            hasQueue = true
            applyModes()
            do {
                try await player.prepareToPlay()
                guard id == loadID else { return }
                if autoplay { try await player.play() }
            } catch {
                return fail("That song can’t play here", id: id, generation: generation, load: true)
            }
            guard id == loadID else {
                // stop() ran during play(), for example on a service switch: play must not go on.
                // A newer load replaces the queue itself, so stop only when nothing newer started.
                if stopped { player.stop() }
                return
            }
            lastTrack = trackID
            lastPlaying = autoplay
            send(.trackChanged(trackID, playing: autoplay, generation: generation))
            startPolling()
        }
    }

    func pause() {
        guard hasQueue else { return }
        player.pause()
        lastPlaying = false
    }

    func resume() {
        guard hasQueue, !stopped else { return }
        let id = loadID
        Task {
            do { try await player.play() } catch {
                fail("Apple Music can’t play now", id: id, generation: generation, load: false)
            }
            if id != loadID && stopped { player.stop() }  // stop() ran during play()
        }
    }

    func stop() {
        loadID += 1  // a load or resume in flight must not report or play after this
        stopped = true
        guard hasQueue else { return }
        player.stop()
        poller?.invalidate()
        poller = nil
        lastTrack = nil
        lastPlaying = false
    }

    func next(generation: Int) {
        self.generation = generation
        guard hasQueue else { return }
        Task { _ = try? await player.skipToNextEntry() }  // the next poll reports the new track
    }

    func prev(generation: Int) {
        self.generation = generation
        guard hasQueue else { return }
        Task { _ = try? await player.skipToPreviousEntry() }
    }

    func setShuffle(_ on: Bool) {
        shuffle = on
        applyModes()
    }

    func setRepeat(_ mode: RepeatMode) {
        repeatMode = mode
        applyModes()
    }

    func seek(to seconds: Double, generation: Int) {
        self.generation = generation
        guard hasQueue else { return }
        player.playbackTime = seconds
    }

    /// MusicKit has no volume control on the Mac (`MPVolumeView` does not work with
    /// `ApplicationMusicPlayer`). The Mac's own volume applies.
    func setVolume(_ percent: Int) {}

    private func applyModes() {
        guard hasQueue else { return }
        player.state.shuffleMode = shuffle ? .songs : .off
        player.state.repeatMode = switch repeatMode {
        case .off: MusicPlayer.RepeatMode.none
        case .one: .one
        case .all: .all
        }
    }

    private func fail(_ message: String, id: Int, generation: Int, load: Bool) {
        guard id == loadID else { return }
        send(load ? .loadFailed(message, generation: generation) : .playbackFailed(message, generation: generation))
    }

    private func startPolling() {
        guard poller == nil else { return }
        poller = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        guard !stopped else { return }  // stop() also ends the timer; this is a second guard
        let status = player.state.playbackStatus
        let playing = status == .playing
        if lastPlaying && status == .stopped {  // the queue ran out; Repeat All and One never end
            lastPlaying = false
            return send(.trackEnded(generation: generation))
        }
        let track = player.queue.currentEntry.flatMap(AppleMusicID.of) ?? lastTrack
        if let track, track != lastTrack || playing != lastPlaying {
            lastTrack = track
            lastPlaying = playing
            send(.trackChanged(track, playing: playing, generation: generation))
        }
        if playing { send(.position(player.playbackTime, generation: generation)) }
    }

    /// A song from the user's library, or else from the catalog.
    private static func song(_ id: String) async -> Song? {
        guard let itemID = AppleMusicID.itemID(id, prefix: AppleMusicID.songPrefix) else { return nil }
        var library = MusicLibraryRequest<Song>()
        library.filter(matching: \.id, equalTo: itemID)
        if let song = try? await library.response().items.first { return song }
        let catalog = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: itemID)
        return try? await catalog.response().items.first
    }

    /// The tracks of a library playlist, in order. nil for an unknown or unreadable playlist.
    private static func playlistTracks(_ id: String) async -> [Song]? {
        guard let itemID = AppleMusicID.itemID(id, prefix: AppleMusicID.playlistPrefix) else { return nil }
        var request = MusicLibraryRequest<Playlist>()
        request.filter(matching: \.id, equalTo: itemID)
        guard let playlist = try? await request.response().items.first,
              let tracks = try? await playlist.with([.tracks]).tracks else { return nil }
        return tracks.compactMap { track -> Song? in
            if case .song(let song) = track { song } else { nil }
        }
    }
}
