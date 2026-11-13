import AppKit
import CoreGraphics
import Foundation
// SPIKE: MusicKit response types are not Sendable in the macOS 15 SDK. This file reads them only
// on the main actor.
@preconcurrency import MusicKit
import Observation

/// SPIKE (Apple Music test): can Clasify play Apple Music with ApplicationMusicPlayer and no
/// other app window on screen? Shows only when the hidden switch `spike.applemusic` is on
/// (`defaults write app.clasify.Clasify spike.applemusic -bool true`, then relaunch), in
/// View › Apple Music Test. Remove this file and AppleMusicSpikeWindow.swift after the test.
enum AppleMusicSpike {
    static let key = "spike.applemusic"
    /// Read once at launch.
    static let isOn = UserDefaults.standard.bool(forKey: key)
}


/// The test log. It stays in memory and on stdout only. It writes no file.
@MainActor @Observable final class AppleMusicSpikeLog {
    static let shared = AppleMusicSpikeLog()

    private(set) var lines: [String] = []

    @ObservationIgnored private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return f
    }()

    func add(_ tag: String, _ text: String) {
        let line = "\(formatter.string(from: Date())) JST [\(tag)] \(text)"
        lines.append(line)
        print(line)
    }

    func clear() { lines.removeAll() }

    var text: String { lines.joined(separator: "\n") }
}

private func elapsedMS(since start: Date) -> Int { Int(Date().timeIntervalSince(start) * 1000) }


/// Logs every on-screen window of Music.app (or any process named like "Music"),
/// every app launch and activation, and Music's Dock and hidden state.
/// It polls every 50 ms, so a short flash shows in the log.
@MainActor final class AppleMusicFlashWatcher {
    static let shared = AppleMusicFlashWatcher()

    private var timer: Timer?
    private var lastWindows: Set<String> = []
    private var lastMusicState = ""
    private let musicIDs: Set<String> = ["com.apple.Music", "com.apple.iTunes"]
    private var log: AppleMusicSpikeLog { AppleMusicSpikeLog.shared }

    func start() {
        guard timer == nil else { return }
        log.add("watch", "watcher on: polls on-screen windows every 50 ms")
        let center = NSWorkspace.shared.notificationCenter
        _ = center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let text = "launched \(app?.bundleIdentifier ?? "?") pid \(app?.processIdentifier ?? 0)"
            MainActor.assumeIsolated { AppleMusicSpikeLog.shared.add("watch", text) }
        }
        _ = center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let text = "quit \(app?.bundleIdentifier ?? "?")"
            MainActor.assumeIsolated { AppleMusicSpikeLog.shared.add("watch", text) }
        }
        _ = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let id = app?.bundleIdentifier ?? "?"
            let own = app?.processIdentifier == getpid()
            MainActor.assumeIsolated {
                AppleMusicSpikeLog.shared.add(own ? "watch" : "FLASH?", "frontmost app is now \(id)")
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            MainActor.assumeIsolated { AppleMusicFlashWatcher.shared.poll() }
        }
    }

    private func poll() {
        let musicApps = NSWorkspace.shared.runningApplications.filter { musicIDs.contains($0.bundleIdentifier ?? "") }
        let musicPIDs = Set(musicApps.map(\.processIdentifier))

        let state = musicApps.map { app in
            let dock = app.activationPolicy == .regular ? "yes" : "no"
            return "Music running: hidden=\(app.isHidden) active=\(app.isActive) Dock icon=\(dock)"
        }.joined(separator: "; ")
        let shown = state.isEmpty ? "Music not running" : state
        if shown != lastMusicState {
            log.add("watch", shown)
            lastMusicState = shown
        }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return }
        var now = Set<String>()
        for window in info {
            let pid = window[kCGWindowOwnerPID as String] as? Int32 ?? 0
            if pid == getpid() { continue }
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            guard musicPIDs.contains(pid) || owner.localizedCaseInsensitiveContains("music") else { continue }
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            let alpha = window[kCGWindowAlpha as String] as? Double ?? 1
            let bounds = window[kCGWindowBounds as String] as? [String: Double] ?? [:]
            let number = window[kCGWindowNumber as String] as? Int ?? 0
            let size = "\(Int(bounds["Width"] ?? 0))x\(Int(bounds["Height"] ?? 0))"
            let origin = "\(Int(bounds["X"] ?? 0)),\(Int(bounds["Y"] ?? 0))"
            now.insert("#\(number) \(owner) layer \(layer) alpha \(alpha) \(size) at \(origin)")
        }
        for item in now.subtracting(lastWindows).sorted() { log.add("FLASH?", "window on screen: \(item)") }
        for item in lastWindows.subtracting(now).sorted() { log.add("watch", "window gone: \(item)") }
        lastWindows = now
    }
}


/// Native MusicKit: library reads with MusicLibraryRequest, playback with ApplicationMusicPlayer.
@MainActor @Observable final class AppleMusicSpikePlayer {
    var playlists: [Playlist] = []
    var status = "-"

    @ObservationIgnored private var poller: Timer?
    @ObservationIgnored private var lastEntry = ""
    @ObservationIgnored private var lastStatus = ""
    private var log: AppleMusicSpikeLog { AppleMusicSpikeLog.shared }
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
