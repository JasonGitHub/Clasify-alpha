import AppKit
import iTunesLibrary
import Observation

struct MusicAppPlaylist: Identifiable, Hashable {
    let id: String  // persistent ID, 16 hex digits, as AppleScript shows it
    let name: String
}

/// Path B: the Music app, launched hidden, driven with AppleScript.
/// Playlists come from iTunesLibrary.framework, or from AppleScript as a fallback.
/// (SystemMusicPlayer is not available on native macOS.)
@MainActor @Observable final class PathB {
    var playlists: [MusicAppPlaylist] = []
    var status = "-"

    @ObservationIgnored private var poller: Timer?
    @ObservationIgnored private var lastTrack = ""
    private var log: SpikeLog { SpikeLog.shared }

    private var musicIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty
    }

    func launchHidden() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") else {
            log.add("B", "Music.app not found")
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.hides = true
        config.addsToRecentItems = false
        config.createsNewApplicationInstance = false
        let start = Date()
        log.add("B", "launch Music hidden (activates=false, hides=true)")
        NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
            let text = error.map { "launch error: \($0)" } ?? "launched hidden, pid \(app?.processIdentifier ?? 0)"
            Task { @MainActor in SpikeLog.shared.add("B", "\(text) in \(elapsedMS(since: start)) ms") }
        }
    }

    func loadWithITLibrary() {
        let start = Date()
        do {
            let library = try ITLibrary(apiVersion: "1.0")
            playlists = library.allPlaylists
                .filter { !$0.isPrimary }
                .map { MusicAppPlaylist(id: String(format: "%016llX", $0.persistentID.uint64Value), name: $0.name) }
            log.add("B", "ITLibrary: \(playlists.count) playlists in \(elapsedMS(since: start)) ms (Music running: \(musicIsRunning))")
        } catch {
            log.add("B", "ITLibrary error: \(error)")
        }
    }

    func loadWithAppleScript() {
        log.add("B", "AppleScript playlist read (Music running before: \(musicIsRunning))")
        let start = Date()
        let source = """
        tell application "Music"
            set out to ""
            repeat with p in user playlists
                set out to out & (persistent ID of p) & tab & (name of p) & linefeed
            end repeat
            return out
        end tell
        """
        guard let text = run(source) else { return }
        playlists = text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return MusicAppPlaylist(id: String(parts[0]), name: String(parts[1]))
        }
        log.add("B", "AppleScript: \(playlists.count) playlists in \(elapsedMS(since: start)) ms")
    }

    func play(_ playlist: MusicAppPlaylist) {
        log.add("B", "play \(playlist.name) (\(playlist.id)); Music running before: \(musicIsRunning)")
        let start = Date()
        let source = "tell application \"Music\" to play (first playlist whose persistent ID is \"\(playlist.id)\")"
        if run(source) != nil {
            log.add("B", "play command returned in \(elapsedMS(since: start)) ms")
        }
        startPolling()
    }

    func togglePause() { command("playpause") }
    func next() { command("next track") }
    func previous() { command("previous track") }
    func seekForward() { command("set player position to (player position + 30)") }

    func quitMusic() {
        guard musicIsRunning else { return }
        command("quit")
    }

    private func command(_ verb: String) {
        guard musicIsRunning else {
            log.add("B", "\(verb): Music is not running, so the spike sends nothing")
            return
        }
        if run("tell application \"Music\" to \(verb)") != nil { log.add("B", verb) }
    }

    private func startPolling() {
        guard poller == nil else { return }
        poller = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { self.poll() }
        }
    }

    private func poll() {
        // Never send AppleScript when Music is not running, because that would launch it.
        guard musicIsRunning else {
            status = "Music not running"
            return
        }
        let source = """
        tell application "Music"
            set s to player state as text
            set p to 0
            set n to ""
            try
                set p to player position
                set n to name of current track
            end try
            return s & tab & ((round p) as text) & tab & n
        end tell
        """
        guard let text = run(source, quiet: true) else { return }
        let parts = text.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else { return }
        status = "\(parts[0]), \(parts[1]) s, \(parts[2])"
        if parts[2] != lastTrack {
            log.add("B", "track changed: \(lastTrack) -> \(parts[2])")
            lastTrack = parts[2]
        }
    }

    private func run(_ source: String, quiet: Bool = false) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            if !quiet { log.add("B", "AppleScript error: \(error[NSAppleScript.errorMessage] ?? error)") }
            return nil
        }
        return result?.stringValue ?? ""
    }
}
