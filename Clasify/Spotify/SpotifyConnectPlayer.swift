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
    /// Logs in again after the session dropped. Returns true when the session works again.
    var reconnect: @MainActor () async -> Bool = { false }

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
    /// The track and playlist ID of the newest load, as Clasify knows them.
    private var startedTrack = "", playlist: String?
    /// The newest position that went to the store.
    private var position: Double = 0
    /// Where playback stopped when Spotify quit or stopped. Play loads it again there.
    private var resumePoint: (track: String, playlist: String?, position: Double)?
    /// True after our play command succeeded, until stop or a move away.
    /// States before that can be from an older session or another device, so they are ignored.
    private var ours = false
    private var lastTrack = "", lastRunning = false
    /// Spotify moved on to a context that the bridge cannot load, such as a station.
    private var followedOther = false
    /// The dealer reconnects that the newest state reported, so each new one is logged once.
    private var dealerReconnects = 0
    /// Until when, after a new login, a state from our device can give control back.
    /// While the session was down, a load or a command can have failed and given control away.
    private var rejoinUntil: ContinuousClock.Instant?
    /// TEMP (cover blink, 2026-11-05): the track before `lastTrack`, and when the newest play
    /// command succeeded, for the track-change log. Remove once the cause of the blink is known.
    private var trackBefore = "", playedAt = ContinuousClock.now
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
        // The cluster does not always report that Spotify quit, so watch the app too.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == Self.bundleID else { return }
            // The queue is .main, so this runs on the main actor.
            MainActor.assumeIsolated { self?.spotifyQuit() }
        }
        // For the log only: a session can drop while the Mac sleeps.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in log.notice("Mac woke from sleep") }
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
        start(trackID, context: context, autoplay: autoplay, at: nil)
    }

    /// Starts a load. `position` is where to seek once it plays.
    private func start(_ trackID: String, context: String?, autoplay: Bool, at position: Double?) {
        loadID += 1
        let id = loadID
        ours = false
        loading = true
        wantsRunning = autoplay
        pendingSkips = []
        loaded = nil
        lastTrack = ""
        rejoinUntil = nil
        // A continuation keeps its point until it plays, so a failed relaunch can be retried.
        if position == nil { resumePoint = nil }
        self.position = position ?? 0
        startedTrack = trackID
        playlist = context
        ticker?.cancel()
        Task { await play(trackID, context: context, id: id, at: position) }
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
        // After Spotify quit or stopped, load the same track again where it stopped.
        if !ours, let point = resumePoint {
            return start(point.track, context: point.playlist, autoplay: true, at: point.position)
        }
        // After a move away, the pick is gone here. Ask for a new one, do not take it back.
        guard ours else {
            log.notice("play: no control and no place to go on from")
            return send(.playbackFailed("Pick a track to play it here", generation: generation))
        }
        fire(LSB_COMMAND_RESUME)
    }

    func stop() {
        loadID += 1  // a load in flight must not start Spotify after this
        loading = false
        // Queued at once, so it goes out before the logout that can come next.
        // The retry after a reconnect must still go out, though `ours` is false by then.
        fire(LSB_COMMAND_PAUSE, evenAfterStop: true)
        ours = false
        resumePoint = nil
        rejoinUntil = nil
        startedTrack = ""
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
        position = seconds  // so a quit before the next state keeps the new place
        resumePoint?.position = seconds  // a scrub after a quit moves the place too
        resend { [client] in client.fireSeek(device: $0, seconds: seconds) }
    }

    func setVolume(_ percent: Int) {
        volume = percent
        // The retry reads `volume` again, so it sends the newest value.
        resend { [client] in client.fireVolume(device: $0, percent: self.volume) }
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
        resumePoint = nil
        rejoinUntil = nil
        startedTrack = ""
    }

    /// Spotify quit. Its device must be found again after the next launch. While it played
    /// our track, show paused and keep the place, so Play continues there.
    private func spotifyQuit() {
        device = nil
        deviceOptions = [:]
        // After following Spotify into a station or album, there is no place to go on from.
        let message = followedOther ? "Spotify quit. Pick a track to play" : "Spotify quit. Press Play to go on"
        if ours { lose(message, resumable: true, reason: "Spotify quit") }
    }

    /// Our playback ended outside Clasify. A resumable end keeps the place for Play.
    /// The log gets the reason kind only, with no IDs or names.
    private func lose(_ message: String, resumable: Bool, reason: String) {
        log.notice("lost control: \(reason, privacy: .public)")
        ours = false
        ticker?.cancel()
        if resumable && !followedOther { resumePoint = (lastTrack.isEmpty ? startedTrack : lastTrack, playlist, position) }
        send(.playbackFailed(message, generation: generation))
    }

    private func fire(_ command: Int32, evenAfterStop: Bool = false) {
        resend(evenAfterStop: evenAfterStop) { [client] in client.fire(command, to: $0) }
    }

    /// Sends one fire-and-forget command to our device. When the session dropped, it logs in
    /// again and sends the command once more. `call` gets the device ID and returns the status.
    /// The retry is dropped after a new load. `evenAfterStop` keeps it after a stop.
    private func resend(evenAfterStop: Bool = false, _ call: @escaping @MainActor (String) -> Int32) {
        guard ours, let device else { return }
        guard call(device) == LSB_ERR_NOT_LOGGED_IN else { return }
        let id = loadID
        Task {
            guard await reconnect(), id == loadID, ours || evenAfterStop, let device = self.device else { return }
            _ = call(device)
        }
    }

    /// The session was logged in again. Register it, so the cluster watch delivers states again.
    func sessionRestored() {
        Task { _ = try? await client.devices() }
        // The new registration makes the cluster watch send the current state. If our device
        // has a track and Clasify still shows our last load, `handle` takes control again.
        // At launch there was no load yet, so nothing is taken.
        rejoinUntil = ContinuousClock.now + .seconds(10)
    }

    /// Takes control again after a new login, when our device still has a track and no load
    /// or stop came after our last load. The state then goes to the store as a track change.
    private func rejoin(_ state: SpotifyPlayerState) {
        guard let until = rejoinUntil, ContinuousClock.now < until, !ours, !loading, !startedTrack.isEmpty,
              state.hasTrack else { return }
        rejoinUntil = nil
        log.notice("took control again after a new login")
        ours = true
        resumePoint = nil
        loaded = nil
        lastTrack = ""  // so the store gets the track and its play state
    }

    /// Runs one session call, and after a dropped session logs in again and runs it once more.
    private func again<T>(_ call: @MainActor () async throws -> T) async throws -> T {
        try await retryOnce(after: reconnect, when: { ($0 as? BridgeError)?.status == LSB_ERR_NOT_LOGGED_IN }, call)
    }

    // MARK: Playing

    private func play(_ trackID: String, context playlist: String?, id: Int, at position: Double?) async {
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
                if let known { found = known } else { found = try await again { try await appDevice { id == loadID } } }
                guard id == loadID else { return }
                Self.logTime("load: device found", since: start)
                device = found
                await applyOptions()
                Self.logTime("load: options set", since: start)
                guard id == loadID else { return }
                do {
                    try await again { try await client.play(device: found, context: contextURI, track: trackID) }
                    Self.logTime("load: play acknowledged", since: start)
                    break
                } catch where attempt == 0 && known != nil {
                    Self.logFailure("play, first try", error)
                    known = nil
                }
            }
            guard id == loadID else { return }
            // Spotify quit after it took the play command. The continuation stays for Play.
            guard let found = device else {
                if resumePoint == nil { resumePoint = (trackID, playlist, self.position) }
                return fail("Spotify quit. Press Play to go on", id)
            }
            if let position, position >= 1 { client.fireSeek(device: found, seconds: position) }
            if !wantsRunning { client.fire(LSB_COMMAND_PAUSE, to: found) }
            for command in pendingSkips { client.fire(command, to: found) }
            client.fireVolume(device: found, percent: volume)
            context = contextURI
            followedOther = false
            loaded = (pendingSkips.isEmpty ? trackID : nil, ContinuousClock.now)
            playedAt = ContinuousClock.now
            pendingSkips = []
            loading = false
            ours = true
            resumePoint = nil
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
                // After a dropped session, this logs in again and sends the option once more.
                try await again { try await client.setOption(option, on, device: device) }
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
        let kind = switch status {
        case LSB_ERR_NOT_LOGGED_IN: "not logged in"
        case LSB_ERR_CONNECT: "Connect call failed"
        case LSB_ERR_INVALID_ARGUMENT: "invalid argument"
        case LSB_ERR_READ: "read failed"
        case LSB_ERR_OAUTH: "OAuth"
        default: error is BridgeError ? "other" : "not a bridge error"
        }
        log.error("\(step, privacy: .public) failed: status \(status, privacy: .public) (\(kind, privacy: .public))")
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
        // After this wait with no new computer, this Mac's entry from before the launch counts:
        // Spotify keeps one device ID per install.
        let registered = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline && wanted() {
            // Each call registers again (one connect-state PUT), so ask once a second.
            let devices = try await client.devices().map {
                SpotifyAppDevice.Candidate(id: $0.id, name: $0.name, type: $0.type)
            }
            let pick = SpotifyAppDevice.pick(
                devices, computerName: name, excluding: before, allowExcluded: ContinuousClock.now >= registered)
            switch pick {
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

    /// The kind of a Spotify context URI, for the log: playlist, collection, station and so on.
    nonisolated static func contextKind(_ uri: String) -> String {
        let parts = uri.split(separator: ":")
        guard parts.first == "spotify", parts.count >= 2 else { return uri.isEmpty ? "none" : "other" }
        if parts.last == "collection" { return "collection" }
        let known = ["playlist", "album", "artist", "station", "show", "episode", "track", "user"]
        return known.contains(String(parts[1])) ? String(parts[1]) : "other"
    }

    private func handle(_ state: SpotifyPlayerState) {
        // A lower count is a new login: it only sets the new baseline.
        if state.dealerReconnects > dealerReconnects {
            log.notice("dealer reconnected: \(state.dealerReconnects, privacy: .public) in this login")
        }
        dealerReconnects = state.dealerReconnects
        guard let device else { return }
        if state.activeDeviceID == device {
            deviceOptions = [
                LSB_OPTION_SHUFFLE: state.shuffle, LSB_OPTION_REPEAT_CONTEXT: state.repeatContext,
                LSB_OPTION_REPEAT_TRACK: state.repeatTrack,
            ]
            rejoin(state)
        }
        guard ours else { return }
        if let loaded, ContinuousClock.now - loaded.at < .seconds(3),
           state.activeDeviceID != device || !isLoaded(state, track: loaded.track) {
            Self.logTime("track state: ignored, still the track before the load", since: playedAt)
            return  // still what played before the load
        }
        loaded = nil
        guard state.activeDeviceID == device else {
            // The user moved playback to another device, or Spotify quit. Do not fight it.
            // With no active device, nothing plays elsewhere, so Play may continue here.
            let stopped = state.activeDeviceID.isEmpty
            let reason = stopped ? "no active device" : "other device"
            return lose(stopped ? "Spotify stopped playing" : "Playing elsewhere now", resumable: stopped, reason: reason)
        }
        // Our Spotify app moved to another context: autoplay after the playlist ended, or a
        // list picked in Spotify itself. Follow it and keep control. Liked Songs can come back
        // as a playlist URI, so only a playlist context is compared.
        if !context.hasSuffix(":collection") && !state.contextURI.isEmpty && state.contextURI != context {
            log.notice("following Spotify into another context (\(Self.contextKind(state.contextURI), privacy: .public))")
            context = state.contextURI
            // So Play after a quit loads the track in its own context. The bridge can load only
            // a playlist, so a station or album keeps no place to go on from.
            let likedSongs = state.contextURI.hasSuffix(":collection")
            followedOther = !likedSongs && !state.contextURI.hasPrefix("spotify:playlist:")
            if !followedOther { playlist = likedSongs ? Playlist.likedSongsID : state.contextURI }
        }
        let gen = generation
        if !state.hasTrack {
            if lastRunning { send(.trackEnded(generation: gen)) }  // Spotify stopped at the end of the context
        } else if state.trackURI != lastTrack || state.isRunning != lastRunning {
            if state.trackURI != lastTrack {
                let kind = state.trackURI == trackBefore ? "back to the track before" : "new track"
                Self.logTime("track change: \(kind)", since: playedAt)
                trackBefore = lastTrack
            }
            send(.trackChanged(state.trackURI, playing: state.isRunning, generation: gen))
        }
        lastTrack = state.trackURI
        lastRunning = state.hasTrack && state.isRunning
        position = state.position
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
                self.position = t
                self.send(.position(t, generation: gen))
            }
        }
    }
}
