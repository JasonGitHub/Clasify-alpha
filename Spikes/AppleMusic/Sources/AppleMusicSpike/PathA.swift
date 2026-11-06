import Foundation
// Spike: MusicKit response types are not Sendable in the macOS 15.5 SDK. The responses are only read on the main actor.
@preconcurrency import MusicKit
import Observation

/// Path A: native MusicKit. Library reads with MusicLibraryRequest, playback with ApplicationMusicPlayer.
@MainActor @Observable final class PathA {
    var playlists: [Playlist] = []
    var status = "-"

    @ObservationIgnored private var poller: Timer?
    @ObservationIgnored private var lastEntry = ""
    @ObservationIgnored private var lastStatus = ""
    private var log: SpikeLog { SpikeLog.shared }
    private var player: ApplicationMusicPlayer { ApplicationMusicPlayer.shared }

    func authorize() async {
        log.add("A", "auth status before: \(MusicAuthorization.currentStatus)")
        let result = await MusicAuthorization.request()
        log.add("A", "auth status after: \(result)")
        do {
            let subscription = try await MusicSubscription.current
            log.add("A", "subscription: canPlayCatalogContent=\(subscription.canPlayCatalogContent)")
        } catch {
            log.add("A", "MusicSubscription error: \(error)")
        }
    }

    func loadPlaylists() async {
        let start = Date()
        do {
            let request = MusicLibraryRequest<Playlist>()
            let response = try await request.response()
            playlists = Array(response.items)
            log.add("A", "MusicLibraryRequest: \(playlists.count) playlists in \(elapsedMS(since: start)) ms")
        } catch {
            log.add("A", "MusicLibraryRequest error: \(error)")
        }
    }

    func play(_ playlist: Playlist) async {
        log.add("A", "play playlist \(playlist.name) (\(playlist.id))")
        player.queue = ApplicationMusicPlayer.Queue(for: [playlist])
        await startPlayback()
    }

    /// Searches the catalog. This needs the developer token that MusicKit makes from the signed App ID.
    func playCatalogSong() async {
        let start = Date()
        do {
            var request = MusicCatalogSearchRequest(term: "Daft Punk", types: [Song.self])
            request.limit = 1
            let response = try await request.response()
            guard let song = response.songs.first else {
                log.add("A", "catalog search: no song")
                return
            }
            log.add("A", "catalog search OK in \(elapsedMS(since: start)) ms: \(song.title)")
            player.queue = ApplicationMusicPlayer.Queue(for: [song])
            await startPlayback()
        } catch {
            log.add("A", "catalog search error: \(error)")
        }
    }

    private func startPlayback() async {
        let start = Date()
        do {
            try await player.prepareToPlay()
            log.add("A", "prepareToPlay OK in \(elapsedMS(since: start)) ms")
            try await player.play()
            log.add("A", "play() returned in \(elapsedMS(since: start)) ms")
        } catch {
            log.add("A", "playback error: \(error)")
        }
        startPolling()
    }

    func togglePause() async {
        if player.state.playbackStatus == .playing {
            player.pause()
            log.add("A", "pause()")
        } else {
            do {
                try await player.play()
                log.add("A", "play()")
            } catch {
                log.add("A", "play error: \(error)")
            }
        }
    }

    func next() async {
        do {
            try await player.skipToNextEntry()
            log.add("A", "skipToNextEntry OK")
        } catch {
            log.add("A", "skipToNextEntry error: \(error)")
        }
    }

    func previous() async {
        do {
            try await player.skipToPreviousEntry()
            log.add("A", "skipToPreviousEntry OK")
        } catch {
            log.add("A", "skipToPreviousEntry error: \(error)")
        }
    }

    func seekForward() {
        let target = player.playbackTime + 30
        player.playbackTime = target
        log.add("A", "seek to \(Int(target)) s")
    }

    private func startPolling() {
        guard poller == nil else { return }
        poller = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { self.poll() }
        }
    }

    private func poll() {
        let playback = "\(player.state.playbackStatus)"
        let entry = player.queue.currentEntry?.title ?? "none"
        let time = Int(player.playbackTime)
        status = "\(playback), \(time) s, \(entry)"
        if playback != lastStatus {
            log.add("A", "status \(lastStatus) -> \(playback) at \(time) s")
            lastStatus = playback
        }
        if entry != lastEntry {
            log.add("A", "track changed: \(lastEntry) -> \(entry)")
            lastEntry = entry
        }
    }
}
