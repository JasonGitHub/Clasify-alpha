import AppKit
import ClasifyCore
import Foundation
import LibrespotBridge
import os

/// Only statuses and step names go to the unified log, never a bridge message or a token.
private let log = Logger(subsystem: "app.clasify.Clasify", category: "player")

/// Plays through the Spotify desktop app. Clasify starts and controls it with Spotify Connect
/// commands through the librespot session. It never uses AppleScript, and it launches Spotify hidden.
///
/// Spotify owns the play order of a context. Clasify sets Spotify's shuffle and repeat to its own
/// settings and reports Spotify's track changes. It follows only the Spotify app on this Mac
/// that it started playing. When the user moves playback to another device, it reports that once.
@MainActor
final class SpotifyConnectPlayer: Player {
    nonisolated static let bundleID = "com.spotify.client"

    /// Runs reported actions. Set it once the `Store` exists.
    var send: (Action) -> Void = { _ in }

    private let client: LibrespotClient
    private let library: LibrespotLibrary
    /// The generation of the newest load, seek, next or prev. Every report carries it.
    private var generation = 0
    /// The Spotify app's device on this Mac, once a load found it.
    private var device: String?
    /// True after our play command succeeded, until stop or a move to another device.
    /// States before that can be from an older session or another device, so they are ignored.
    private var ours = false
    private var lastTrack = "", lastRunning = false
    /// The track of the newest load, and when its play command succeeded. Until Spotify shows
    /// that track, for up to 3 s, states still show the track from before the load.
    private var loaded: (track: String, at: ContinuousClock.Instant)?
    private var shuffle = false, repeatMode = RepeatMode.off
    /// The options that the device has now, so a load sends only the ones that changed.
    private var applied: (shuffle: Bool, repeatMode: RepeatMode)?
    /// Moves the position on once a second while a track plays. Cluster updates come only on changes.
    private var ticker: Task<Void, Never>?

    init(client: LibrespotClient, library: LibrespotLibrary) {
        self.client = client
        self.library = library
        client.stateBox.set(Self.stateHandler(for: self))
    }

    /// Made outside the main actor: the bridge calls it on its own thread. It only hops to main,
    /// asynchronously, because the bridge can wait for this callback.
    private nonisolated static func stateHandler(for player: SpotifyConnectPlayer) -> @Sendable (SpotifyPlayerState) -> Void {
        { [weak player] state in Task { @MainActor in player?.handle(state) } }
    }

    // MARK: Player

    func load(trackID: String, context: String?, autoplay: Bool, generation: Int) {
        self.generation = generation
        ours = false
        loaded = nil
        lastTrack = ""
        Task { await play(trackID, context: context, autoplay: autoplay, generation: generation) }
    }

    func pause() { command(LSB_COMMAND_PAUSE) }
    func resume() {
        // After a move to another device, the pick is gone here. Ask for a new one, do not take it back.
        guard ours else { return send(.playbackFailed("Pick a track to play it here", generation: generation)) }
        command(LSB_COMMAND_RESUME)
    }

    func stop() {
        if ours { command(LSB_COMMAND_PAUSE) }
        ours = false
        ticker?.cancel()
    }

    func next(generation: Int) { self.generation = generation; command(LSB_COMMAND_NEXT) }
    func prev(generation: Int) { self.generation = generation; command(LSB_COMMAND_PREV) }

    func seek(to seconds: Double, generation: Int) {
        self.generation = generation
        guard ours, let device else { return }
        let client = client
        Task { do { try await client.seek(device: device, seconds: seconds) } catch { Self.logFailure("seek", error) } }
    }

    func setVolume(_ percent: Int) {
        guard ours, let device else { return }
        let client = client
        Task { do { try await client.volume(device: device, percent: percent) } catch { Self.logFailure("volume", error) } }
    }

    func setShuffle(_ on: Bool) {
        shuffle = on
        if ours { Task { await applyOptions() } }
    }

    func setRepeat(_ mode: RepeatMode) {
        repeatMode = mode
        if ours { Task { await applyOptions() } }
    }

    // MARK: Playing

    private func play(_ trackID: String, context: String?, autoplay: Bool, generation gen: Int) async {
        guard let contextURI = contextURI(for: context) else {
            return fail("Can’t play this list", gen)
        }
        do {
            let device = try await appDevice()
            guard gen == generation else { return }  // a newer load came
            self.device = device
            await applyOptions()
            try await client.play(device: device, context: contextURI, track: trackID)
            guard gen == generation else { return }
            if !autoplay { try await client.send(LSB_COMMAND_PAUSE, to: device) }
            loaded = (trackID, ContinuousClock.now)
            ours = true
        } catch let error as PlayerError {
            fail(error.message, gen)
        } catch {
            Self.logFailure("play", error)
            fail("Can’t start Spotify playback", gen)
        }
    }

    private func fail(_ message: String, _ gen: Int) {
        guard gen == generation else { return }
        send(.playbackFailed(message, generation: gen))
    }

    /// `Playlist.likedSongsID` plays the user's Liked Songs. Other IDs are Spotify playlist URIs.
    private func contextURI(for playlist: String?) -> String? {
        guard let playlist else { return nil }
        guard playlist == Playlist.likedSongsID else { return playlist }
        return library.username.map { "spotify:user:\($0):collection" }
    }

    /// Sends the shuffle and repeat options that the device does not have yet.
    private func applyOptions() async {
        guard let device else { return }
        let want = (shuffle: shuffle, repeatMode: repeatMode)
        if let applied, applied == want { return }
        // Repeat One keeps the context repeat on too, so the context still repeats if
        // Spotify ignores the track repeat.
        let options = [
            (LSB_OPTION_SHUFFLE, want.shuffle),
            (LSB_OPTION_REPEAT_CONTEXT, want.repeatMode != .off),
            (LSB_OPTION_REPEAT_TRACK, want.repeatMode == .one),
        ]
        do {
            for (option, on) in options { try await client.setOption(option, on, device: device) }
            applied = want
        } catch {
            applied = nil
            Self.logFailure("options", error)
        }
    }

    private func command(_ command: Int32) {
        guard ours, let device else { return }
        let client = client
        Task { do { try await client.send(command, to: device) } catch { Self.logFailure("command \(command)", error) } }
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
    private func appDevice() async throws -> String {
        if NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty {
            try await launchSpotify()
        }
        let deadline = ContinuousClock.now + .seconds(15)
        while ContinuousClock.now < deadline {
            let devices = try await client.devices()
            if let device = Self.thisMac(in: devices) { return device.id }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw PlayerError(message: "Spotify didn’t answer. Try again")
    }

    /// The Spotify desktop app on this Mac: a computer device, by this Mac's name if one matches.
    private static func thisMac(in devices: [ConnectDevice]) -> ConnectDevice? {
        let apps = devices.filter { $0.type == "COMPUTER" && $0.software.lowercased().contains("osx") }
        let name = Host.current().localizedName
        return apps.first { $0.name == name } ?? (apps.count == 1 ? apps[0] : nil)
    }

    private func launchSpotify() async throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else {
            throw PlayerError(message: "Install the Spotify app to play music")
        }
        try await Self.open(url)
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

    private func handle(_ state: SpotifyPlayerState) {
        guard ours, let device else { return }
        guard state.activeDeviceID == device else {
            // The user moved playback to another device, or Spotify quit. Do not fight it.
            ours = false
            ticker?.cancel()
            let message = state.activeDeviceID.isEmpty ? "Spotify stopped playing" : "Playing on another device"
            send(.playbackFailed(message, generation: generation))
            return
        }
        if let loaded, state.trackURI != loaded.track, ContinuousClock.now - loaded.at < .seconds(3) {
            return  // still the track from before the load
        }
        loaded = nil
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
