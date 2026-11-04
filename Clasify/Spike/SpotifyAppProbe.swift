import AppKit
import Darwin
import Foundation
import Observation

/// Build 4: tests the "Spotify app plays, Clasify controls it" route with Apple Events.
/// Spike only. Not the 1.0 engine.
@MainActor
@Observable
final class SpotifyAppProbe {
    struct ResultLine: Identifiable {
        var id: String { name }
        let name: String
        var value: String
    }

    /// The player state, read with one Apple Event.
    struct State {
        var state = ""
        var position = 0.0
        var trackID = ""
        var durationMs = 0
        var volume = -1
        var shuffling = ""
    }

    private(set) var results: [ResultLine] = []
    private(set) var log: [String] = []
    private(set) var isConnected = false
    private(set) var isBusy = false

    @ObservationIgnored private var start = Date()
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var lastCommandAt = Date.distantPast
    @ObservationIgnored private var lastNotificationAt = Date.distantPast
    @ObservationIgnored private var lastNotifiedTrack = ""
    @ObservationIgnored private var lastPollLine = ""

    static let bundleID = "com.spotify.client"

    private var app: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first
    }

    private func set(_ name: String, _ value: String) {
        if let index = results.firstIndex(where: { $0.name == name }) {
            results[index].value = value
        } else {
            results.append(ResultLine(name: name, value: value))
        }
        append("RESULT \(name): \(value)")
    }

    private var elapsedMs: Int { Int(Date().timeIntervalSince(start) * 1000) }

    private func append(_ text: String) {
        log.append("+\(elapsedMs) ms \(text)")
        if log.count > 400 { log.removeFirst(log.count - 400) }
    }

    // MARK: Apple Events

    /// Runs AppleScript. Returns the string result, or the error number and message.
    private func run(_ source: String) -> (value: String?, error: Int?, message: String?) {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            return (nil, error[NSAppleScript.errorNumber] as? Int, error[NSAppleScript.errorMessage] as? String)
        }
        return (result?.stringValue ?? "", nil, nil)
    }

    private func tell(_ body: String) -> (value: String?, error: Int?, message: String?) {
        run("tell application \"Spotify\"\n\(body)\nend tell")
    }

    private func readState() -> State? {
        let script = """
        set s to (player state as string)
        set p to (player position as string)
        set v to (sound volume as string)
        set sh to (shuffling as string)
        try
            set t to (id of current track)
            set d to (duration of current track as string)
        on error
            set t to ""
            set d to "0"
        end try
        return s & "|" & p & "|" & t & "|" & d & "|" & v & "|" & sh
        """
        guard let value = tell(script).value else { return nil }
        let parts = value.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 6 else { return nil }
        return State(
            state: parts[0],
            position: Double(parts[1].replacingOccurrences(of: ",", with: ".")) ?? 0,
            trackID: parts[2],
            durationMs: Int(Double(parts[3].replacingOccurrences(of: ",", with: ".")) ?? 0),
            volume: Int(parts[4]) ?? -1,
            shuffling: parts[5]
        )
    }

    // MARK: 1. Connect

    func connect() async {
        isBusy = true
        defer { isBusy = false }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else {
            set("Spotify installed", "no")
            return
        }
        set("Spotify installed", "yes, \(url.path)")
        let launchedAt = Date()
        if app == nil {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.hides = true
            configuration.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
            set("Launch", "was not running, launched with hides = true, activates = false")
        } else {
            set("Launch", "was already running")
        }
        // The first Apple Event shows the Automation prompt. -1743 means denied.
        for _ in 0..<240 {
            // An Apple Event to an app that is not running launches it, maybe visible.
            // So wait until our hidden launch has finished first.
            guard app?.isFinishedLaunching == true else {
                try? await Task.sleep(for: .milliseconds(250))
                continue
            }
            let result = tell("return player state as string")
            if result.value != nil {
                let ms = Int(Date().timeIntervalSince(launchedAt) * 1000)
                set("Automation", "allowed")
                set("Ready after", "\(ms) ms (includes the time on the Automation prompt)")
                isConnected = true
                break
            }
            if result.error == -1743 {
                set("Automation", "denied (-1743). Allow it in System Settings > Privacy & Security > Automation.")
                return
            }
            if let error = result.error, error != -600, error != -609 {
                append("Apple Event error \(error): \(result.message ?? "")")
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard isConnected else {
            set("Ready after", "not ready after 60 s")
            return
        }
        visibility("Hidden at ready")
        startListening()
        try? await Task.sleep(for: .seconds(3))
        visibility("Hidden 3 s after ready")
    }

    /// Item 6: is the Spotify window on screen, is the app hidden, is it in the Dock?
    private func visibility(_ name: String) {
        guard let app else {
            set(name, "Spotify not running")
            return
        }
        let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? [])
            .filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier }
            .filter { ($0[kCGWindowLayer as String] as? Int) == 0 }
        let dock = app.activationPolicy == .regular ? "in Dock" : "not in Dock"
        set(name, "\(windows.count) windows on screen, isHidden \(app.isHidden), isActive \(app.isActive), \(dock)")
    }

    // MARK: 4. Events

    private func startListening() {
        guard observer == nil else { return }
        observer = Self.observePlayback(Self.onMain { [self] payload in notified(payload) })
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        set("Notifications", "listening to com.spotify.client.PlaybackStateChanged")
    }

    struct Payload: Sendable {
        let state: String
        let trackID: String
        let name: String
        let position: String
    }

    nonisolated private static func onMain<T: Sendable>(
        _ handler: @escaping @MainActor @Sendable (T) -> Void
    ) -> @Sendable (T) -> Void {
        { value in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { handler(value) }
            }
        }
    }

    /// Built in a nonisolated function, so the observer block has no actor isolation.
    nonisolated private static func observePlayback(_ handler: @escaping @Sendable (Payload) -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: nil
        ) { note in
            let info = note.userInfo ?? [:]
            handler(Payload(
                state: info["Player State"] as? String ?? "",
                trackID: info["Track ID"] as? String ?? "",
                name: info["Name"] as? String ?? "",
                position: (info["Playback Position"] as? NSNumber).map { String(format: "%.1f", $0.doubleValue) } ?? ""
            ))
        }
    }

    private func notified(_ payload: Payload) {
        lastNotificationAt = Date()
        let trackChanged = !lastNotifiedTrack.isEmpty && payload.trackID != lastNotifiedTrack
        // A new track with no command in the last 3 s means the old track ended.
        if trackChanged, Date().timeIntervalSince(lastCommandAt) > 3 {
            set("Track end produces a notification", "yes (new track \(payload.trackID) with no command)")
        }
        lastNotifiedTrack = payload.trackID
        append("NOTIFY state=\(payload.state) track=\(payload.trackID) pos=\(payload.position) \"\(payload.name)\"")
    }

    private func poll() {
        guard let state = readState() else {
            append("POLL failed")
            return
        }
        let line = "POLL state=\(state.state) track=\(state.trackID) vol=\(state.volume)"
        // Log a poll line only when something other than the position changes.
        if line != lastPollLine {
            append("\(line) pos=\(String(format: "%.1f", state.position))")
            lastPollLine = line
        }
    }

    // MARK: 2. Play in context

    func play(context: String?, tracks: [String]?, name: String) async {
        guard let context, let tracks, let first = tracks.first(where: { $0.hasPrefix("spotify:track:") }) else {
            set(name, "no context or tracks yet. Run 3a first.")
            return
        }
        isBusy = true
        defer { isBusy = false }
        await command(name + ": play", "play track \"\(first)\" in context \"\(context)\"") { _, now in
            now.trackID == first && now.state == "playing"
        }
        visibility("Hidden after play")
        guard let before = readState() else { return }
        await command(name + ": next track", "next track") { old, now in now.trackID != old.trackID }
        guard let after = readState() else { return }
        let index = tracks.firstIndex(of: after.trackID)
        let verdict: String
        if let index {
            verdict = "yes, next track is #\(index + 1) of \(tracks.count) in the context"
        } else {
            verdict = "no, next track \(after.trackID) is not in the context"
        }
        set(name + ": context kept", "\(verdict) (shuffling \(before.shuffling))")
        memory()
    }

    // MARK: 3. Controls

    func pause() async { await command("Pause", "pause") { _, now in now.state == "paused" } }
    func resume() async { await command("Resume", "play") { _, now in now.state == "playing" } }
    func next() async { await command("Next", "next track") { old, now in now.trackID != old.trackID } }
    func previous() async {
        await command("Prev", "previous track") { old, now in
            now.trackID != old.trackID || now.position < old.position - 2
        }
    }
    func seekForward() async {
        await command("Seek +30 s", "set player position to (player position + 30)") { old, now in
            now.position >= old.position + 25
        }
    }
    func volume50() async { await command("Volume 50", "set sound volume to 50") { _, now in now.volume == 50 } }

    /// Seeks to 5 s before the end, then waits up to 20 s for a notification with a new track.
    func trackEnd() async {
        guard let state = readState(), state.durationMs > 10_000 else {
            set("Track end produces a notification", "no track playing")
            return
        }
        isBusy = true
        defer { isBusy = false }
        let target = Double(state.durationMs) / 1000 - 5
        lastCommandAt = Date()
        _ = tell("set player position to \(target)")
        append("SEND seek to \(String(format: "%.1f", target)) s, 5 s before the end")
        let since = Date()
        for _ in 0..<200 {
            try? await Task.sleep(for: .milliseconds(100))
            if lastNotificationAt > since, lastNotifiedTrack != state.trackID {
                return // notified() has set the result.
            }
        }
        let now = readState()
        let changed = now.map { $0.trackID != state.trackID } ?? false
        set("Track end produces a notification", changed ? "no notification, but the track changed" : "no, and the track did not change")
    }

    /// Sends one command and measures the time until the polled state shows the change.
    private func command(_ name: String, _ body: String, until: (State, State) -> Bool) async {
        guard let before = readState() else {
            set(name, "cannot read the state")
            return
        }
        lastCommandAt = Date()
        let sentAt = Date()
        let result = tell(body)
        let sendMs = Int(Date().timeIntervalSince(sentAt) * 1000)
        append("SEND \(name) (\(sendMs) ms)")
        if let error = result.error {
            set(name, "error \(error): \(result.message ?? "")")
            return
        }
        for _ in 0..<100 {
            if let now = readState(), until(before, now) {
                let ms = Int(Date().timeIntervalSince(sentAt) * 1000)
                let notified = lastNotificationAt > sentAt
                    ? ", notification after \(Int(lastNotificationAt.timeIntervalSince(sentAt) * 1000)) ms"
                    : ", no notification"
                set(name, "OK, state change after \(ms) ms (event \(sendMs) ms\(notified))")
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        set(name, "no state change within 5 s")
    }

    // MARK: 5. Memory

    func memory() {
        let own = Self.memory(of: getpid())
        set("Memory Clasify", Self.format(own))
        var total = (resident: UInt64(0), footprint: UInt64(0))
        var count = 0
        for pid in Self.allPIDs() where Self.path(of: pid).contains("/Spotify.app/") {
            let usage = Self.memory(of: pid)
            total.resident += usage.resident
            total.footprint += usage.footprint
            count += 1
        }
        set("Memory Spotify", "\(Self.format(total)) over \(count) processes")
    }

    private static func format(_ usage: (resident: UInt64, footprint: UInt64)) -> String {
        "RSS \(usage.resident / 1_048_576) MB, footprint \(usage.footprint / 1_048_576) MB"
    }

    nonisolated private static func allPIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return Array(pids.prefix(Int(max(filled, 0)))).filter { $0 > 0 }
    }

    nonisolated private static func path(of pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return "" }
        return String(cString: buffer)
    }

    nonisolated private static func memory(of pid: pid_t) -> (resident: UInt64, footprint: UInt64) {
        var info = rusage_info_v2()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
            }
        }
        guard status == 0 else { return (0, 0) }
        return (info.ri_resident_size, info.ri_phys_footprint)
    }

    // MARK: Report

    var reportLines: [String] {
        if results.isEmpty { return ["   Not run"] }
        return results.map { "   \($0.name): \($0.value)" } + ["   Log:"] + log.map { "     \($0)" }
    }
}
