import AppKit
import Foundation
import Observation

/// Drives the Spotify app only through Spotify Connect commands (no AppleScript)
/// and watches its windows every 50 ms. State comes from the Connect cluster updates.
/// Spike only.
@MainActor
@Observable
final class ConnectProbe {
    private(set) var results: [ResultLine] = []
    private(set) var isBusy = false

    @ObservationIgnored private weak var model: SpikeModel?
    @ObservationIgnored private var log: [String] = []
    @ObservationIgnored private var start = Date()
    @ObservationIgnored private var devices: [ConnectDevice] = []
    @ObservationIgnored private var devicesAt = Date.distantPast
    @ObservationIgnored private var state: ClusterState?
    @ObservationIgnored private var stateAt = Date.distantPast
    @ObservationIgnored private var clusterCount = 0

    static let bundleID = "com.spotify.client"

    struct ResultLine: Identifiable {
        var id: String { name }
        let name: String
        var value: String
    }

    /// One device from the Connect cluster.
    struct ConnectDevice {
        let id: String
        let name: String
        let type: String
        let software: String
        let active: Bool
    }

    struct ClusterState {
        let reason: String
        let activeDevice: String
        let playing: Bool
        let paused: Bool
        let buffering: Bool
        let track: String
        let positionAsOf: Int
        let timestamp: Int
        let duration: Int
        let context: String
        let volume: Int

        /// The position now, from the position at `timestamp` (ms since 1970).
        var position: Int {
            guard playing, !paused else { return positionAsOf }
            return positionAsOf + max(0, Int(Date().timeIntervalSince1970 * 1000) - timestamp)
        }

        var line: String {
            "\(reason) playing \(playing) paused \(paused) buffering \(buffering) track \(track) "
                + "pos \(position / 1000) of \(duration / 1000) s vol \(volume) context \(context)"
        }
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
        if log.count > 300 { log.removeFirst(log.count - 300) }
    }

    private static func ms(since date: Date) -> Int { Int(Date().timeIntervalSince(date) * 1000) }

    private var spotify: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first
    }

    /// The Spotify app's Connect device: a computer that runs the desktop app.
    private var appDevice: ConnectDevice? {
        let others = devices.filter { $0.name != "Clasify spike" }
        return others.first { $0.type == "COMPUTER" && $0.software.lowercased().contains("osx") }
            ?? others.first { $0.type == "COMPUTER" }
    }

    // MARK: Events from the bridge

    func connectResult(path: String, message: String) {
        guard path == "devices", !message.hasPrefix("ERROR") else {
            if path == "devices" { append("devices \(message)") }
            return
        }
        devices = message.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 5 else { return nil }
            return ConnectDevice(
                id: parts[0], name: parts[1], type: parts[2], software: parts[3], active: parts[4] == "true"
            )
        }
        devicesAt = Date()
    }

    func cluster(_ line: String) {
        let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 12 else {
            append("CLUSTER \(line)")
            return
        }
        let new = ClusterState(
            reason: parts[0], activeDevice: parts[1], playing: parts[2] == "true", paused: parts[3] == "true",
            buffering: parts[4] == "true", track: parts[5], positionAsOf: Int(parts[6]) ?? 0,
            timestamp: Int(parts[7]) ?? 0, duration: Int(parts[8]) ?? 0, context: parts[9], volume: Int(parts[10]) ?? 0
        )
        state = new
        stateAt = Date()
        clusterCount += 1
        append("CLUSTER \(new.line)")
    }

    // MARK: Helpers

    /// Registers this session, then waits for a device list with the Spotify app in it.
    private func findAppDevice(timeout: Int) async -> ConnectDevice? {
        let deadline = Date().addingTimeInterval(TimeInterval(timeout))
        while Date() < deadline {
            let asked = Date()
            model?.connectDevices()
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(100))
                if devicesAt > asked { break }
            }
            if devicesAt > asked, let device = appDevice { return device }
            try? await Task.sleep(for: .seconds(1))
        }
        return nil
    }

    private func send(_ endpoint: String, to device: String, extra: String = "") {
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let body = #"{"command":{"endpoint":"\#(endpoint)"\#(extra),"logging_params":{"command_id":"\#(id)"}}}"#
        model?.connectRequest("POST", "/connect-state/v1/player/command/from/{self}/to/\(device)", body: body)
    }

    /// `skipTo` is a JSON object body for options.skip_to, like `"track_uri":"spotify:track:…"`.
    private func play(_ context: String, on device: String, skipTo: String = "") {
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let body = """
        {"command":{"context":{"uri":"\(context)","url":"context://\(context)","metadata":{}},\
        "play_origin":{"feature_identifier":"harmony","feature_version":"4.11.0"},\
        "options":{"license":"on-demand","skip_to":{\(skipTo)},"player_options_override":{}},\
        "logging_params":{"command_id":"\(id)"},"endpoint":"play"}}
        """
        model?.connectRequest("POST", "/connect-state/v1/player/command/from/{self}/to/\(device)", body: body)
    }

    /// Waits until a cluster update after `since` meets `until`. Returns the delay in ms.
    private func waitForState(since: Date, timeout: Double = 5, until: (ClusterState) -> Bool) async -> Int? {
        let deadline = since.addingTimeInterval(timeout)
        while Date() < deadline {
            if stateAt > since, let state, until(state) { return Int(stateAt.timeIntervalSince(since) * 1000) }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return nil
    }

    /// Samples Spotify's windows and activation every `interval` ms while `body` runs.
    /// `onSample` runs after each sample, for example to hide Spotify on its first window.
    private func watchWindows(
        interval: Int = 50, onSample: (@MainActor @Sendable (WindowWatcher) -> Void)? = nil,
        _ body: () async -> Void
    ) async -> String {
        let watcher = WindowWatcher()
        let task = Task { @MainActor in
            while !Task.isCancelled {
                watcher.sample(spotify)
                onSample?(watcher)
                try? await Task.sleep(for: .milliseconds(interval))
            }
        }
        await body()
        try? await Task.sleep(for: .seconds(2))
        task.cancel()
        watcher.sample(spotify)
        return watcher.summary
    }

    /// Any Spotify process, helpers included.
    private var anySpotifyProcess: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier?.hasPrefix(Self.bundleID) == true }
    }

    /// The installed Spotify app's version, for the report.
    private var spotifyVersion: String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID),
              let info = Bundle(url: url)?.infoDictionary
        else { return "not installed" }
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    // MARK: 1. Cold start

    enum LaunchMethod {
        /// NSWorkspace with hides=true, activates=false, and these launch arguments.
        case arguments([String])
        /// NSWorkspace with hides=true, then hide Spotify and activate Clasify on the first window.
        case hideOnFirstWindow

        var name: String {
            switch self {
            case .arguments(let arguments): "Cold start (\(arguments.joined(separator: " ")))"
            case .hideOnFirstWindow: "Cold start (hide on first window)"
            }
        }
    }

    func coldStart(model: SpikeModel, method: LaunchMethod) async {
        self.model = model
        let name = method.name
        set("Spotify version", spotifyVersion)
        guard let context = model.firstPlaylistURI else { return set(name, "no playlist. Run 1 and 2 first.") }
        guard !anySpotifyProcess else { return set(name, "a Spotify process is running. Quit Spotify fully first.") }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else {
            return set(name, "Spotify is not installed")
        }
        isBusy = true
        defer { isBusy = false }
        let launchedAt = Date()
        var deviceMs: Int?
        var commandMs: Int?
        var audioMs: Int?
        let hider = Hider(launchedAt: launchedAt)
        let onSample: (@MainActor @Sendable (WindowWatcher) -> Void)?
        if case .hideOnFirstWindow = method {
            onSample = { [self] watcher in hider.check(spotify, windows: watcher.lastWindows) }
        } else {
            onSample = nil
        }
        let interval = if case .hideOnFirstWindow = method { 10 } else { 50 }
        let windows = await watchWindows(interval: interval, onSample: onSample) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.hides = true
            configuration.activates = false
            configuration.addsToRecentItems = false
            if case .arguments(let arguments) = method { configuration.arguments = arguments }
            NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
            guard let device = await findAppDevice(timeout: 40) else { return }
            deviceMs = Self.ms(since: launchedAt)
            let sentAt = Date()
            play(context, on: device.id)
            commandMs = Self.ms(since: launchedAt)
            if let delay = await waitForState(since: sentAt, timeout: 10, until: {
                $0.activeDevice == device.id && $0.playing && !$0.paused && !$0.buffering
            }) {
                audioMs = Int(sentAt.timeIntervalSince(launchedAt) * 1000) + delay
            }
        }
        set(name, "device in cluster after \(deviceMs.map { "\($0) ms" } ?? "none in 40 s"), "
            + "play sent at \(commandMs.map { "\($0) ms" } ?? "-"), playing at \(audioMs.map { "\($0) ms" } ?? "not seen")")
        set(name + ": window check", windows)
        if case .hideOnFirstWindow = method {
            set(name + ": hide steps", hider.summary)
        }
    }

    // MARK: 2. Window open behind another app

    func behind(model: SpikeModel) async {
        self.model = model
        let name = "Behind Clasify"
        guard let playlist = model.firstPlaylistURI, let liked = model.likedContextURI else {
            return set(name, "no contexts. Run 1 and 2 first.")
        }
        guard let app = spotify else { return set(name, "Spotify is not running") }
        isBusy = true
        defer { isBusy = false }
        let before = "Spotify windows \(Self.onScreenWindows(of: app)), Spotify active \(app.isActive), "
            + "front app \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")"
        var steps: [String] = []
        let windows = await watchWindows {
            guard let device = await findAppDevice(timeout: 10) else { return steps.append("no app device") }
            var sentAt = Date()
            play(playlist, on: device.id)
            let first = await waitForState(since: sentAt) { $0.playing && $0.context == playlist }
            steps.append("playlist \(first.map { "\($0) ms" } ?? "not seen")")
            try? await Task.sleep(for: .seconds(2))
            let track = state?.track
            sentAt = Date()
            send("skip_next", to: device.id)
            let next = await waitForState(since: sentAt) { $0.track != track }
            steps.append("next \(next.map { "\($0) ms" } ?? "not seen")")
            try? await Task.sleep(for: .seconds(2))
            sentAt = Date()
            play(liked, on: device.id)
            let third = await waitForState(since: sentAt) { $0.playing && $0.context == liked }
            steps.append("Liked Songs \(third.map { "\($0) ms" } ?? "FAIL, context is \(state?.context ?? "none")")")
        }
        set(name, "before: \(before); " + steps.joined(separator: ", "))
        set(name + ": window check", windows)
    }

    // MARK: Liked Songs

    /// Plays Liked Songs three ways and checks the context and track in the cluster.
    func likedSongs(model: SpikeModel) async {
        self.model = model
        guard let liked = model.likedContextURI, let tracks = model.contexts[liked], let first = tracks.first else {
            return set("Liked Songs", "no Liked Songs. Run 1 and 2 first.")
        }
        isBusy = true
        defer { isBusy = false }
        guard let device = await findAppDevice(timeout: 10) else { return set("Liked Songs", "no app device") }
        let variants: [(name: String, context: String, skipTo: String)] = [
            ("Liked A (user collection, as build 7)", liked, ""),
            ("Liked B (user collection, skip_to first track)", liked, #""track_uri":"\#(first)","track_index":0"#),
            ("Liked C (spotify:collection:tracks)", "spotify:collection:tracks", ""),
        ]
        for variant in variants {
            let sentAt = Date()
            play(variant.context, on: device.id, skipTo: variant.skipTo)
            let delay = await waitForState(since: sentAt) { $0.playing && !$0.buffering && $0.track != "" }
            try? await Task.sleep(for: .seconds(1))
            let now = state
            let inLiked = now.map { tracks.contains($0.track) } ?? false
            let contextOK = now?.context == liked || now?.context.hasSuffix(":collection") == true
                || now?.context == "spotify:collection:tracks"
            set(variant.name, "\(contextOK && inLiked ? "PASS" : "FAIL"): after \(delay.map { "\($0) ms" } ?? "no update"), "
                + "context \(now?.context ?? "none"), track in Liked Songs \(inLiked)")
            try? await Task.sleep(for: .seconds(2))
        }
    }

    // MARK: 3. Controls without AppleScript

    func controls(model: SpikeModel) async {
        self.model = model
        isBusy = true
        defer { isBusy = false }
        guard let app = await findAppDevice(timeout: 10) else { return set("Controls", "no app device") }
        let device = app.id
        guard state != nil else { return set("Controls", "no cluster state yet. Play something first.") }
        let windows = await watchWindows {
            await measure("Pause", device) { self.send("pause", to: device) } until: { $0.paused }
            await measure("Resume", device) { self.send("resume", to: device) } until: { !$0.paused && $0.playing }
            let track1 = state?.track
            await measure("Next", device) { self.send("skip_next", to: device) } until: { $0.track != track1 }
            try? await Task.sleep(for: .seconds(2))
            let track2 = state?.track
            await measure("Prev", device) { self.send("skip_prev", to: device) } until: {
                $0.track != track2 || $0.positionAsOf < 1500
            }
            let target = (state?.position ?? 0) + 30_000
            await measure("Seek +30 s", device) { self.send("seek_to", to: device, extra: #","value":\#(target)"#) } until: {
                abs($0.positionAsOf - target) < 3000
            }
            await measure("Volume 50%", device) {
                self.model?.connectRequest(
                    "PUT", "/connect-state/v1/connect/volume/from/{self}/to/\(device)", body: #"{"volume":32768}"#
                )
            } until: { abs($0.volume - 32768) < 1500 }
        }
        set("Controls: window check", windows)
    }

    private func measure(
        _ name: String, _ device: String, _ action: () -> Void, until: (ClusterState) -> Bool
    ) async {
        let sentAt = Date()
        action()
        if let delay = await waitForState(since: sentAt, until: until) {
            set(name, "OK, cluster shows it after \(delay) ms: \(state?.line ?? "")")
        } else {
            set(name, "no matching cluster update within 5 s (last: \(state?.line ?? "none"))")
        }
        try? await Task.sleep(for: .milliseconds(500))
    }

    // MARK: 4. Track end from the cluster

    func trackEnd(model: SpikeModel) async {
        self.model = model
        isBusy = true
        defer { isBusy = false }
        guard let app = await findAppDevice(timeout: 10) else { return set("Track end", "no app device") }
        let device = app.id
        guard let current = state, current.duration > 10_000 else { return set("Track end", "nothing playing") }
        let sentAt = Date()
        send("seek_to", to: device, extra: #","value":\#(current.duration - 5000)"#)
        if let delay = await waitForState(since: sentAt, timeout: 20, until: { $0.track != current.track }) {
            set("Track end", "new track in the cluster \(delay) ms after the seek to end - 5 s: \(state?.line ?? "")")
        } else {
            set("Track end", "no new track within 20 s (last: \(state?.line ?? "none"))")
        }
    }

    // MARK: Windows

    fileprivate static func onScreenWindows(of app: NSRunningApplication) -> Int {
        (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? [])
            .filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier }
            .filter { ($0[kCGWindowLayer as String] as? Int) == 0 }
            .count
    }

    // MARK: Report

    var reportLines: [String] {
        if results.isEmpty { return ["   Not run"] }
        return results.map { "   \($0.name): \($0.value)" } + ["   Cluster updates: \(clusterCount)", "   Log:"]
            + log.map { "     \($0)" }
    }
}

/// Hides Spotify and activates Clasify each time a Spotify window or activation shows up.
@MainActor
private final class Hider {
    private let launchedAt: Date
    private var steps: [String] = []
    private var showing = false
    private var clasifyLostFocus = false

    init(launchedAt: Date) { self.launchedAt = launchedAt }

    private var ms: Int { Int(Date().timeIntervalSince(launchedAt) * 1000) }

    func check(_ app: NSRunningApplication?, windows: Int) {
        guard let app else { return }
        if !NSApplication.shared.isActive { clasifyLostFocus = true }
        let now = windows > 0 || app.isActive
        if now, !showing {
            steps.append("shown at \(ms) ms (windows \(windows), active \(app.isActive)), hide sent")
            app.hide()
            NSApplication.shared.activate()
        } else if !now, showing {
            steps.append("gone at \(ms) ms")
        }
        showing = now
    }

    var summary: String {
        (steps.isEmpty ? "no window seen" : steps.joined(separator: ", ")) + "; Clasify lost focus \(clasifyLostFocus)"
    }
}

/// Collects the window samples for one test.
@MainActor
final class WindowWatcher {
    private let start = Date()
    private var samples = 0
    private var firstWindows: Int?
    private var maxWindows = 0
    private(set) var lastWindows = 0
    private var everActive = false
    private var everFront = false
    private var firstChange: String?
    private var firstSeenAt: Int?

    func sample(_ app: NSRunningApplication?) {
        samples += 1
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        guard let app else { return }
        if firstSeenAt == nil { firstSeenAt = ms }
        let windows = ConnectProbe.onScreenWindows(of: app)
        lastWindows = windows
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
        if firstWindows == nil { firstWindows = windows }
        if firstChange == nil, windows > (firstWindows ?? 0) || app.isActive || front {
            firstChange = "at \(ms) ms (windows \(windows), active \(app.isActive), front \(front))"
        }
        maxWindows = max(maxWindows, windows)
        everActive = everActive || app.isActive
        everFront = everFront || front
    }

    var summary: String {
        "\(samples) samples; Spotify seen from \(firstSeenAt.map { "\($0) ms" } ?? "never"); windows first \(firstWindows ?? 0), "
            + "max \(maxWindows); ever active \(everActive); ever frontmost \(everFront); "
            + "first change \(firstChange ?? "none")"
    }
}
