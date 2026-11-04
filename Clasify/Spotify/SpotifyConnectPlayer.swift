import AppKit
import ClasifyCore
import Foundation
import LibrespotBridge
import SystemConfiguration
import os

/// Only statuses and step names go to the unified log, never a bridge message or a token.
private let log = Logger(subsystem: "app.clasify.Clasify", category: "player")

/// Plays through the Spotify desktop app. Clasify starts and controls it with Spotify Connect
/// commands through the librespot session. It never uses AppleScript, and it launches Spotify hidden.
///
/// Spotify owns the play order of a context. Clasify sets Spotify's shuffle and repeat to its own
/// settings and reports Spotify's track changes. It follows only the Spotify app on this Mac, and
/// only while that app plays what Clasify started. When the user moves away, it reports that once.
@MainActor
final class SpotifyConnectPlayer: Player {
    nonisolated static let bundleID = "com.spotify.client"

    /// Runs reported actions. Set it once the `Store` exists.
    var send: (Action) -> Void = { _ in }

    private let client: LibrespotClient
    private let library: LibrespotLibrary
    /// The generation of the newest load, seek, next or prev. Every report carries it.
    private var generation = 0
    /// Bumped by each load and stop. A load that is not the newest stops at its next step.
    private var loadID = 0
    /// The newest load until its play command succeeded.
    private var loading = false
    /// Pause or Play pressed while loading: the play state to set once the load plays.
    private var wantsRunning = true
    /// Next and Prev pressed while loading, in order, sent once the load plays. They are not
    /// summed, because at a list's start or with shuffle, Prev then Next is not "no move".
    private var pendingSkips: [Int32] = []
    /// The Spotify app's device on this Mac, once a load found it.
    private var device: String?
    /// The context of the newest load, as Spotify knows it.
    private var context = ""
    /// True after our play command succeeded, until stop or a move away.
    /// States before that can be from an older session or another device, so they are ignored.
    private var ours = false
    private var lastTrack = "", lastRunning = false
    /// The track of the newest load, and when its play command succeeded. Until Spotify shows
    /// that track, for up to 3 s, states can still show what played before the load.
    /// The track is nil when skips pressed during the load were sent: then any track in the
    /// load's playlist on this Mac counts.
    private var loaded: (track: String?, at: ContinuousClock.Instant)?
    private var shuffle = false, repeatMode = RepeatMode.off
    /// Clasify's volume. It is sent once after each play, so Spotify does not keep its own.
    private var volume = AppState().volume
    /// The newest shuffle and repeat that our device reported, so a load sends only the changes.
    private var deviceOptions: [Int32: Bool] = [:]
    /// Moves the position on once a second while a track plays. Cluster updates come only on changes.
    private var ticker: Task<Void, Never>?
    /// The pre-warm in flight: it finds this Mac's device before the first load needs it.
    private var warming: Task<String?, Never>?
    /// Bumped by each pre-warm and by `reset`, so a pre-warm from before a sign-out changes nothing.
    private var warmID = 0
    /// Bumped by `reset`, so an option result from before a sign-out changes nothing.
    private var session = 0

    init(client: LibrespotClient, library: LibrespotLibrary) {
        self.client = client
        self.library = library
        // One consumer keeps the states in the order that the bridge sent them.
        let (states, continuation) = AsyncStream.makeStream(of: SpotifyPlayerState.self)
        client.stateBox.set(Self.forward(to: continuation))
        Task { [weak self] in
            for await state in states { self?.handle(state) }
        }
    }

    /// Made outside the main actor, because the bridge calls it on its own thread. It only
    /// queues the state and returns, because the bridge can wait for this callback.
    private nonisolated static func forward(
        to continuation: AsyncStream<SpotifyPlayerState>.Continuation
    ) -> @Sendable (SpotifyPlayerState) -> Void {
        { continuation.yield($0) }
    }

    // MARK: Player

    func load(trackID: String, context: String?, autoplay: Bool, generation: Int) {
        self.generation = generation
        loadID += 1
        let id = loadID
        ours = false
        loading = true
        wantsRunning = autoplay
        pendingSkips = []
        loaded = nil
        lastTrack = ""
        ticker?.cancel()
        Task { await play(trackID, context: context, id: id) }
    }

    func pause() {
        if loading {
            wantsRunning = false
            return
        }
        fire(LSB_COMMAND_PAUSE)
    }

    func resume() {
        if loading {
            wantsRunning = true
            return
        }
        // After a move away, the pick is gone here. Ask for a new one, do not take it back.
        guard ours else { return send(.playbackFailed("Pick a track to play it here", generation: generation)) }
        fire(LSB_COMMAND_RESUME)
    }

    func stop() {
        loadID += 1  // a load in flight must not start Spotify after this
        loading = false
        // Queued at once, so it goes out before the logout that can come next.
        fire(LSB_COMMAND_PAUSE)
        ours = false
        ticker?.cancel()
    }

    func next(generation: Int) {
        self.generation = generation
        if loading { pendingSkips.append(LSB_COMMAND_NEXT) } else { fire(LSB_COMMAND_NEXT) }
    }

    func prev(generation: Int) {
        self.generation = generation
        if loading { pendingSkips.append(LSB_COMMAND_PREV) } else { fire(LSB_COMMAND_PREV) }
    }

    func seek(to seconds: Double, generation: Int) {
        self.generation = generation
        guard ours, let device else { return }
        client.fireSeek(device: device, seconds: seconds)
    }

    func setVolume(_ percent: Int) {
        volume = percent
        guard ours, let device else { return }
        client.fireVolume(device: device, percent: percent)
    }

    func setShuffle(_ on: Bool) {
        shuffle = on
        if ours { Task { await applyOptions() } }
    }

    func setRepeat(_ mode: RepeatMode) {
        repeatMode = mode
        if ours { Task { await applyOptions() } }
    }

    /// Call it after sign-in. It starts Spotify hidden if it does not run and finds this Mac's
    /// device, so the first play does not wait for them. It sends no command, so it never
    /// changes what Spotify plays. A failure stays quiet: the first load tries again and shows it.
    func prewarm() {
        guard device == nil, warming == nil else { return }
        warmID += 1
        let id = warmID
        warming = Task {
            let start = ContinuousClock.now
            defer { if id == warmID { warming = nil } }
            do {
                let found = try await appDevice { id == warmID }
                guard id == warmID else { return nil }
                Self.logTime("prewarm: device found", since: start)
                if device == nil { device = found }
                return found
            } catch {
                Self.logFailure("prewarm", error)
                return nil
            }
        }
    }

    /// Call it when the session signs out. The device ID and its options belong to that
    /// account, so the next account looks them up again.
    func reset() {
        warmID += 1
        session += 1
        warming?.cancel()
        warming = nil
        device = nil
        deviceOptions = [:]
    }

    private func fire(_ command: Int32) {
        guard ours, let device else { return }
        client.fire(command, to: device)
    }

    // MARK: Playing

    private func play(_ trackID: String, context playlist: String?, id: Int) async {
        guard let contextURI = contextURI(for: playlist) else { return fail("Can’t play this list", id) }
        let start = ContinuousClock.now
        do {
            // Reuse the known device, or the one that the pre-warm finds. Look it up again once
            // if the play fails, for example after Spotify restarted.
            var known = device
            if known == nil, let warming {
                known = await warming.value
                guard id == loadID else { return }
            }
            for attempt in 0..<2 {
                let found: String
                if let known { found = known } else { found = try await appDevice { id == loadID } }
                guard id == loadID else { return }
                Self.logTime("load: device found", since: start)
                device = found
                await applyOptions()
                Self.logTime("load: options set", since: start)
                guard id == loadID else { return }
                do {
                    try await client.play(device: found, context: contextURI, track: trackID)
                    Self.logTime("load: play acknowledged", since: start)
                    break
                } catch where attempt == 0 && known != nil {
                    known = nil
                }
            }
            guard id == loadID, let found = device else { return }
            if !wantsRunning { client.fire(LSB_COMMAND_PAUSE, to: found) }
            for command in pendingSkips { client.fire(command, to: found) }
            client.fireVolume(device: found, percent: volume)
            context = contextURI
            loaded = (pendingSkips.isEmpty ? trackID : nil, ContinuousClock.now)
            pendingSkips = []
            loading = false
            ours = true
        } catch let error as PlayerError {
            fail(error.message, id)
        } catch {
            Self.logFailure("play", error)
            fail("Can’t start Spotify playback", id)
        }
    }

    private func fail(_ message: String, _ id: Int) {
        guard id == loadID else { return }
        loading = false
        send(.playbackFailed(message, generation: generation))
    }

    /// `Playlist.likedSongsID` plays the user's Liked Songs. Other IDs are Spotify playlist URIs.
    private func contextURI(for playlist: String?) -> String? {
        guard let playlist else { return nil }
        guard playlist == Playlist.likedSongsID else { return playlist }
        return library.username.map { "spotify:user:\($0):collection" }
    }

    /// Sends the shuffle and repeat options that our device does not report yet.
    /// Repeat One keeps the context repeat on too, so the context still repeats if Spotify
    /// ignores the track repeat.
    ///
    /// It reads the wanted options again after each command. A toggle while a command is in
    /// flight then still reaches Spotify, though the call for that toggle saw nothing to send.
    private func applyOptions() async {
        let session = session
        var failed: Set<Int32> = []
        for _ in 0..<8 {  // a bound, in case Spotify keeps reporting other values
            let want: [(Int32, Bool)] = [
                (LSB_OPTION_SHUFFLE, shuffle),
                (LSB_OPTION_REPEAT_CONTEXT, repeatMode != .off),
                (LSB_OPTION_REPEAT_TRACK, repeatMode == .one),
            ]
            guard let device, let next = want.first(where: { deviceOptions[$0.0] != $0.1 && !failed.contains($0.0) })
            else { return }
            let (option, on) = next
            do {
                try await client.setOption(option, on, device: device)
                // After a sign-out (`reset`), the value belongs to the old account. The next
                // account can get the same device ID, so the session is compared, not the device.
                guard session == self.session else { return }
                deviceOptions[option] = on
            } catch {
                Self.logFailure("option \(option)", error)
                failed.insert(option)
            }
        }
    }

    /// Milliseconds since `start`, for finding where the first song waits.
    private nonisolated static func logTime(_ step: String, since start: ContinuousClock.Instant) {
        let ms = Int((ContinuousClock.now - start) / .milliseconds(1))
        log.notice("\(step, privacy: .public): \(ms, privacy: .public) ms")
    }

    private nonisolated static func logFailure(_ step: String, _ error: any Error) {
        let status = (error as? BridgeError)?.status ?? 0
        log.error("\(step, privacy: .public) failed: status \(status, privacy: .public)")
    }

    // MARK: The Spotify app

    private struct PlayerError: Error {
        let message: String
    }

    /// Launches Spotify hidden if it does not run, then waits until its device is in the cluster.
    /// It stops waiting when `wanted` turns false, for example when a newer load starts.
    private func appDevice(while wanted: () -> Bool) async throws -> String {
        // Devices from before a launch here are other machines, so they are never this Mac.
        var before: Set<String> = []
        if NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty {
            let listed = try await client.devices()
            before = Set(listed.map(\.id))
            try await launchSpotify()
        }
        let name = SCDynamicStoreCopyComputerName(nil, nil) as String?
        let deadline = ContinuousClock.now + .seconds(15)
        while ContinuousClock.now < deadline && wanted() {
            // Each call registers again (one connect-state PUT), so ask once a second.
            let devices = try await client.devices().map {
                SpotifyAppDevice.Candidate(id: $0.id, name: $0.name, type: $0.type)
            }
            switch SpotifyAppDevice.pick(devices, computerName: name, excluding: before) {
            case .found(let found): return found
            case .ambiguous: throw PlayerError(message: "Spotify runs on several computers. Quit it on the others")
            case .none: try await Task.sleep(for: .seconds(1))
            }
        }
        // Spotify runs but has no device: it is logged out, or logged in to another account.
        throw PlayerError(message: "Log in to the Spotify app with the same account")
    }

    private func launchSpotify() async throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else {
            throw PlayerError(message: "Install the Spotify app to play music")
        }
        let start = ContinuousClock.now
        try await Self.open(url)
        Self.logTime("Spotify launched", since: start)
        // Safety net: Spotify must never come to the front.
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first,
           app.isActive || !app.isHidden {
            app.hide()
            NSApp.activate()
            log.notice("Spotify was visible after launch; hid it")
        }
    }

    /// Launches hidden, with no window and no activation (spike builds 9 and 10). It runs off
    /// the main actor, so the running app that NSWorkspace returns never crosses actors.
    private nonisolated static func open(_ url: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.hides = true
        configuration.activates = false
        configuration.arguments = ["--autostart", "--minimized"]
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    // MARK: State from the cluster

    /// The load's track, or after queued skips any track of the load's playlist.
    /// Liked Songs can come back as a playlist URI, so its context is not compared. An empty
    /// context does not conflict, as in `handle`.
    private func isLoaded(_ state: SpotifyPlayerState, track: String?) -> Bool {
        if let track { return state.trackURI == track }
        return context.hasSuffix(":collection") || state.contextURI.isEmpty || state.contextURI == context
    }

    private func handle(_ state: SpotifyPlayerState) {
        guard let device else { return }
        if state.activeDeviceID == device {
            deviceOptions = [
                LSB_OPTION_SHUFFLE: state.shuffle, LSB_OPTION_REPEAT_CONTEXT: state.repeatContext,
                LSB_OPTION_REPEAT_TRACK: state.repeatTrack,
            ]
        }
        guard ours else { return }
        if let loaded, ContinuousClock.now - loaded.at < .seconds(3),
           state.activeDeviceID != device || !isLoaded(state, track: loaded.track) {
            return  // still what played before the load
        }
        loaded = nil
        // Liked Songs can come back as a playlist URI, so only a playlist context is compared.
        let otherContext = !context.hasSuffix(":collection") && !state.contextURI.isEmpty && state.contextURI != context
        guard state.activeDeviceID == device, !otherContext else {
            // The user moved playback to another device or list, or Spotify quit. Do not fight it.
            ours = false
            ticker?.cancel()
            let message = state.activeDeviceID.isEmpty ? "Spotify stopped playing" : "Playing elsewhere now"
            return send(.playbackFailed(message, generation: generation))
        }
        let gen = generation
        if !state.hasTrack {
            if lastRunning { send(.trackEnded(generation: gen)) }  // Spotify stopped at the end of the context
        } else if state.trackURI != lastTrack || state.isRunning != lastRunning {
            send(.trackChanged(state.trackURI, playing: state.isRunning, generation: gen))
        }
        lastTrack = state.trackURI
        lastRunning = state.hasTrack && state.isRunning
        send(.position(state.position, generation: gen))
        tick(from: state)
    }

    private func tick(from state: SpotifyPlayerState) {
        ticker?.cancel()
        guard state.hasTrack, state.isRunning else { return }
        let start = ContinuousClock.now, gen = generation
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled, gen == self.generation else { return }
                let t = min(state.position + Double((ContinuousClock.now - start).components.seconds), state.duration)
                self.send(.position(t, generation: gen))
            }
        }
    }
}
