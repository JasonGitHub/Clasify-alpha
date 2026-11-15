import ClasifyCore
import Foundation
// MusicKit's request and item types are not Sendable in the macOS 15 SDK. This file uses them
// only on the main actor.
@preconcurrency import MusicKit
import os

/// TEMP (CLA-103, build 202: Next and Previous do nothing in Shuffle Songs): one line per press,
/// counts and flags only, no titles, no IDs.
private let timing = Logger(subsystem: AppID.bundle, category: "timing")

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

    func load(trackID: String, context: String?, autoplay: Bool, generation: Int) {
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
            let kind = context.map { Self.kind($0) } ?? "none"
            timing.notice("""
                apple load (TEMP): context \(kind, privacy: .public), tracks \(tracks.map { "\($0.count)" } ?? "nil", privacy: .public), \
                start found \(start.map { $0.byID ? "yes (row id)" : "yes (key)" } ?? "no", privacy: .public), \
                song id same \(AppleMusicID.song(song.id) == trackID ? "yes" : "no", privacy: .public)
                """)
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
                return fail("That song can’t play here", id: id, load: true)
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

    func pause() {
        wantsPlay = false
        guard hasQueue, !loading else { return }  // a load in flight applies it
        player.pause()
        lastPlaying = false
    }

    func resume() {
        wantsPlay = true
        guard hasQueue, !stopped, !loading else { return }  // a load in flight applies it
        let id = loadID
        Task {
            guard id == loadID, wantsPlay else { return }  // a pause or stop came first
            do { try await player.play() } catch {
                fail("Apple Music can’t play now", id: id, load: false)
            }
            if id != loadID && stopped { player.stop() }  // stop() ran during play()
            else if !wantsPlay { player.pause() }  // a pause came during play()
        }
    }

    func stop() {
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

    func next(generation: Int) {
        self.generation = generation
        if loading { pendingSkips.append(true); pendingSeek = nil; return logSkip(true, "loading yes") }  // the load runs it
        guard hasQueue else { return logSkip(true, "no queue") }
        Task { await skip(true) }  // the next poll reports the new track
    }

    func prev(generation: Int) {
        self.generation = generation
        if loading { pendingSkips.append(false); pendingSeek = nil; return logSkip(false, "loading yes") }  // the load runs it
        guard hasQueue else { return logSkip(false, "no queue") }
        Task { await skip(false) }
    }

    /// The same skip as before, with a TEMP log line around it. Errors are still dropped.
    private func skip(_ forward: Bool) async {
        let before = currentIndex()
        var threw = "no"
        do {
            if forward { _ = try await player.skipToNextEntry() } else { _ = try await player.skipToPreviousEntry() }
        } catch {
            threw = "\((error as NSError).domain) \((error as NSError).code)"
        }
        try? await Task.sleep(for: .milliseconds(600))
        let resolved = player.queue.currentEntry.flatMap(storeID) != nil
        logSkip(forward, "loading no, threw \(threw), entries \(player.queue.entries.count), index \(before) -> \(currentIndex()), "
            + "resolved \(resolved ? "yes" : "no") (\(matchKind(player.queue.currentEntry))), status \(player.state.playbackStatus)")
    }

    /// TEMP: whether the entry's item is a song, and which key kind finds it in the queue.
    private func matchKind(_ entry: ApplicationMusicPlayer.Queue.Entry?) -> String {
        guard let entry else { return "no entry" }
        let byName = entry.subtitle.flatMap { queued.id(title: entry.title, artist: $0) } != nil ? "title" : "none"
        guard case .song(let song) = entry.item else { return "song no, entry \(byName)" }
        let keys = Self.keys(song), none = "\u{1F}"  // a title and artist that match nothing
        if queued.id(for: SongKeys(ids: keys.ids, title: none, artist: none)) != nil { return "song yes, id" }
        if queued.id(for: SongKeys(ids: [], isrc: keys.isrc, title: none, artist: none)) != nil { return "song yes, isrc" }
        return queued.id(for: keys) != nil ? "song yes, title" : "song yes, none, entry \(byName)"
    }

    /// TEMP: the current entry's place in the queue, or "none".
    private func currentIndex() -> String {
        guard let current = player.queue.currentEntry else { return "none" }
        return player.queue.entries.firstIndex { $0.id == current.id }.map { "\($0)" } ?? "not in entries"
    }

    private func logSkip(_ forward: Bool, _ details: String) {
        timing.notice("apple skip (TEMP): \(forward ? "next" : "prev", privacy: .public), shuffle \(self.shuffle ? "on" : "off", privacy: .public), \(details, privacy: .public)")
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
        if loading { pendingSeek = seconds; return }  // the load runs it
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

    /// Reports with the newest generation: a Next or Prev during the load moved it on.
    private func fail(_ message: String, id: Int, load: Bool) {
        guard id == loadID else { return }
        if load {  // the old queue, if any, plays on and reports again
            loading = false
            if hasQueue && !wantsPlay { player.pause() }  // the user paused during the load
        }
        send(load ? .loadFailed(message, generation: generation) : .playbackFailed(message, generation: generation))
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
    /// TEMP: the kind of a play context, for the "apple load" line.
    private static func kind(_ context: String) -> String {
        if context == ClasifyCore.Playlist.likedSongsID { return "liked" }
        if context == ClasifyCore.Playlist.songsID { return "songs" }
        if ClasifyCore.Playlist.isArtistID(context) { return "artist" }
        return ClasifyCore.Album.isID(context) ? "album" : "playlist"
    }

    private static func keys(_ song: Song) -> SongKeys {
        SongKeys(
            ids: [song.id.rawValue] + (AppleMusicReads.catalogID(song).map { [$0] } ?? []),
            isrc: song.isrc, title: song.title, artist: song.artistName)
    }
}
