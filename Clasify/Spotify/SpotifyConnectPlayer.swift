import AppKit
import ClasifyCore
import Foundation
import LibrespotBridge
import SystemConfiguration
import os

/// Only statuses and step names go to the unified log, never a bridge message or a token.
private let log = Logger(subsystem: AppID.bundle, category: "player")

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
    /// CLA-153: false while the browser shows the activate page; then the safety net below
    /// still hides Spotify but does not bring myPod in front of the browser.
    var mayRaise: () -> Bool = { true }
    /// Logs in again after the session dropped. Returns true when the session works again.
    /// `force` logs in also while the session looks alive: a Connect call timed out (CLA-88).
    var reconnect: @MainActor (_ force: Bool) async -> Bool = { _ in false }

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
    /// The newest seek pressed while loading, sent once the load plays.
    private var pendingSeek: Double?
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
    private var ours = false {
        didSet {
            if ours && !oldValue { endOutside(); controlBack() }  // CLA-97: the reducer ignores it with no loss open
            // CLA-203: the song that played through myPod is not an outside song if it plays on.
            if !ours && oldValue { outsideTrack = lastTrack.isEmpty ? startedTrack : lastTrack }
        }
    }
    /// CLA-203 (fix 5): the Spotify app on this Mac plays while myPod is not in control, and its
    /// last such track. For `day_active` only (`.outsideMusic`).
    private var outsidePlaying = false, outsideTrack = ""
    /// CLA-97: a command timed out or the session dropped, and no state of our device has come
    /// from the new login yet. `relogged`: the new login is done, so its next state confirms it.
    private var lostSession = false, relogged = false
    private var lastTrack = "", lastRunning = false
    /// Spotify moved on to a context that the bridge cannot load, such as a station.
    private var followedOther = false
    /// The dealer reconnects that the newest state reported, so each new one is logged once.
    private var dealerReconnects = 0
    /// Until when, after a new login, a state from our device can give control back.
    /// While the session was down, a load or a command can have failed and given control away.
    private var rejoinUntil: ContinuousClock.Instant?
    /// The user moved our playback to another device. A login does not take it back then.
    private var movedAway = false
    /// When Play took playback back. For up to 3 s, states can still show the other device.
    private var takenBackAt: ContinuousClock.Instant?
    /// What a fire-and-forget command changes. A newer command drops the retry of an older
    /// one only when both change the same thing.
    private enum Lane { case playState, place, volume }
    /// Counts fire-and-forget commands for each lane.
    private var sent: [Lane: Int] = [:]
    /// The newest state from the bridge. At launch it can come before the pre-warm found our
    /// device, so the pre-warm handles it again.
    private var latest: SpotifyPlayerState?
    private var latestAt = ContinuousClock.now
    /// What Clasify controlled before the newest load from the store. If that load fails
    /// before it plays, Spotify still plays the old track, so control goes back to it.
    private var beforeLoad: Snapshot?
    /// The newest load came from the store, not from Play after a quit.
    private var storeLoad = false
    private struct Snapshot {
        var ours: Bool, movedAway: Bool, followedOther: Bool
        var startedTrack: String, lastTrack: String, lastRunning: Bool
        var playlist: String?, context: String, position: Double
        var resumePoint: (track: String, playlist: String?, position: Double)?
        var loaded: (track: String?, at: ContinuousClock.Instant)?
    }
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
    /// The Spotify app that Clasify launched in this session, by its process ID. Only this
    /// one quits when Apple Music becomes active: the user's own Spotify stays.
    private var launchedApp: pid_t?
    /// Apple Music is active: no launch of Spotify may finish. A launch that was already
    /// opening quits the app again (CLA-103). `prewarm` and `load` clear it.
    private var appOff = false

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
        appOff = false
        self.generation = generation
        // A load that replaces one still in flight keeps that one's snapshot: the old track plays.
        let before = loading && storeLoad ? beforeLoad : startedTrack.isEmpty ? nil : Snapshot(
            ours: ours, movedAway: movedAway, followedOther: followedOther, startedTrack: startedTrack,
            lastTrack: lastTrack, lastRunning: lastRunning, playlist: playlist, context: self.context,
            position: position, resumePoint: resumePoint, loaded: loaded)
        start(trackID, context: context, autoplay: autoplay, at: nil)
        beforeLoad = before
        storeLoad = true
    }

    /// The load from the store did not start. Take back what played before it.
    private func restoreBeforeLoad() {
        guard let b = beforeLoad else { return }
        beforeLoad = nil
        (movedAway, followedOther, startedTrack) = (b.movedAway, b.followedOther, b.startedTrack)
        (lastTrack, lastRunning, playlist, context) = (b.lastTrack, b.lastRunning, b.playlist, b.context)
        (position, resumePoint, loaded) = (b.position, b.resumePoint, b.loaded)  // `loaded` keeps its stale-state guard
        guard b.ours else { return }
        guard device != nil else {
            // Spotify quit during the load: Play goes on with the old track.
            resumePoint = (b.lastTrack.isEmpty ? b.startedTrack : b.lastTrack, b.playlist, b.position)
            return
        }
        ours = true
    }

    /// Starts a load. `position` is where to seek once it plays.
    private func start(_ trackID: String, context: String?, autoplay: Bool, at position: Double?) {
        beforeLoad = nil
        storeLoad = false
        takenBackAt = nil
        loadID += 1
        let id = loadID
        ours = false
        loading = true
        wantsRunning = autoplay
        pendingSkips = []
        pendingSeek = nil
        loaded = nil
        lastTrack = ""
        rejoinUntil = nil
        movedAway = false
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
        guard ours else { return resumeWithoutControl() }
        fire(LSB_COMMAND_RESUME)
    }

    /// Play with no control (CLA-93): take playback back from another device, or load the song
    /// that played last there, or the Mac's last song, or ask for a new pick.
    private func resumeWithoutControl() {
        let seen = latest.map {
            ResumePlan.Seen(
                activeDevice: $0.activeDeviceID, track: $0.trackURI, context: $0.contextURI,
                position: $0.position, duration: $0.duration, running: $0.isRunning, hasTrack: $0.hasTrack,
                age: Double((ContinuousClock.now - latestAt) / .milliseconds(1)) / 1000)
        }
        let plan = ResumePlan.pick(device: device, movedAway: movedAway, seen: seen, hasResumePoint: resumePoint != nil)
        log.notice("play with no control: \(plan.kind, privacy: .public)")
        switch plan {
        case .takeBack(let other):
            if let device { takeBack(from: other, to: device) }
        case .load(let track, let playlist, let place):
            // Keep it as the continuation, so Play after a failed load retries this song.
            resumePoint = (track, playlist, place)
            start(track, context: playlist, autoplay: true, at: place)
        case .resumePoint:
            if let point = resumePoint { start(point.track, context: point.playlist, autoplay: true, at: point.position) }
        case .pickASong:
            send(.playbackFailed("Pick a song to play it here", generation: generation))
        }
    }

    /// Moves playback from another device (for example a phone) back to this Mac with a Connect
    /// transfer. The song and its place carry over. Pause, Next and Prev pressed meanwhile follow.
    private func takeBack(from other: String, to device: String) {
        log.notice("play: taking playback back from another device")
        loadID += 1
        let id = loadID
        loading = true
        wantsRunning = true
        pendingSkips = []
        pendingSeek = nil
        beforeLoad = nil  // not a load from the store: a pick meanwhile takes a new snapshot
        storeLoad = false
        Task {
            do {
                try await again { try await client.transfer(from: other, to: device) }
                guard id == loadID, let device = self.device else {
                    // Stop came meanwhile, but the transfer can still have moved playback here.
                    if !loading, let device = self.device { client.fire(LSB_COMMAND_PAUSE, to: device) }
                    return
                }
                // The transfer keeps the other device's play state, so set the wanted one.
                client.fire(wantsRunning ? LSB_COMMAND_RESUME : LSB_COMMAND_PAUSE, to: device)
                for command in pendingSkips { client.fire(command, to: device) }
                if let seek = pendingSeek { client.fireSeek(device: device, seconds: seek) }  // after the skips, as pressed
                pendingSkips = []
                pendingSeek = nil
                client.fireVolume(device: device, percent: volume)  // as after a load: the sound now comes from this Mac
                loading = false
                ours = true
                movedAway = false
                resumePoint = nil
                loaded = nil
                lastTrack = ""  // so the store gets the track that plays now
                takenBackAt = .now
                Task { await applyOptions() }  // the other device's shuffle and repeat came along
                // States from the transfer came while it was not ours yet: handle the newest again.
                if let latest, latest.activeDeviceID == device { handle(latest, receivedAt: latestAt) }
                // A real move away within the 3 s was ignored. States come only on changes, so
                // check the newest one again after the 3 s.
                try? await Task.sleep(for: .seconds(3))
                if id == loadID, ours, let latest { handle(latest, receivedAt: latestAt) }
            } catch {
                Self.logFailure("transfer", error)
                guard id == loadID else { return }
                loading = false
                send(.playbackFailed("That can’t move here. Pick a song to play it", generation: generation))
            }
        }
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
        movedAway = false
        startedTrack = ""
        ticker?.cancel()
    }

    func next(generation: Int) {
        self.generation = generation
        if loading { pendingSkips.append(LSB_COMMAND_NEXT); pendingSeek = nil } else { fire(LSB_COMMAND_NEXT) }
    }

    func prev(generation: Int) {
        self.generation = generation
        if loading { pendingSkips.append(LSB_COMMAND_PREV); pendingSeek = nil } else { fire(LSB_COMMAND_PREV) }  // a seek before it was for the old track
    }

    func seek(to seconds: Double, generation: Int) {
        self.generation = generation
        position = seconds  // so a quit before the next state keeps the new place
        resumePoint?.position = seconds  // a scrub after a quit moves the place too
        if loading { pendingSeek = seconds }
        resend(.place) { [client] in client.fireSeek(device: $0, seconds: seconds, onStale: $1) }
    }

    func setVolume(_ percent: Int) {
        volume = percent
        // The retry reads `volume` again, so it sends the newest value.
        resend(.volume) { [client] in client.fireVolume(device: $0, percent: self.volume, onStale: $1) }
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
        appOff = false
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
                if device == nil {
                    device = found
                    if let latest { handle(latest, receivedAt: latestAt) }  // so a launch can pick up what plays here
                }
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
        movedAway = false
        startedTrack = ""
        latest = nil  // it belongs to the account that signed out
    }

    /// Apple Music is now active: the hidden Spotify app must not run (CLA-103). Quits it only
    /// when Clasify launched it in this session; a Spotify that the user opened, or one left
    /// from an earlier session, stays. The device and the session's state go too.
    func quitApp() {
        appOff = true
        reset()
        guard let pid = launchedApp else { return }
        launchedApp = nil
        NSRunningApplication(processIdentifier: pid)?.terminate()
    }

    /// CLA-189: the pause that a quit of myPod sent, until Spotify answered. The app waits for
    /// it within its quit limit (`AppDelegate.quit`).
    private(set) var quitting: Task<Void, Never>?

    /// CLA-189 (Jason 16:04 JST 11-25): myPod quits normally while Spotify is the service. A
    /// Spotify that myPod launched in this session quits, as `quitApp()` does, so its music
    /// stops. The person's own Spotify stays open: only our playback (`ours`) pauses, with the
    /// same rule as every pause. Nothing of ours plays: nothing goes out and nothing waits.
    func quit() {
        // Codex on #480: that Spotify can have quit, and the person opened Spotify again. Then
        // its PID is gone (or another app's), and the open Spotify is theirs: pause it below.
        if let pid = launchedApp, let app = NSRunningApplication(processIdentifier: pid),
           !app.isTerminated, app.bundleIdentifier == Self.bundleID {
            launchedApp = nil
            app.terminate()
            return
        }
        guard ours, lastRunning, let device else { return }
        quitting = Task { [client] in
            do { try await client.command(LSB_COMMAND_PAUSE, to: device) } catch {
                log.notice("pause at quit failed")  // the status only, as everywhere in this file
            }
        }
    }

    /// Spotify quit. Its device must be found again after the next launch. While it played
    /// our track, show paused and keep the place, so Play continues there.
    private func spotifyQuit() {
        device = nil
        deviceOptions = [:]
        // After following Spotify into a station or album, there is no place to go on from.
        let message = followedOther ? "Spotify closed. Pick a song to play" : "Spotify closed. Press play to go on"
        if ours { lose(message, resumable: true, reason: .spotifyQuit) }
        endOutside()
    }

    /// CLA-203 (fix 5): music while myPod is not in control. Only this Mac's Spotify app counts:
    /// the state's active device is `device`, which `appDevice` picked as this Mac's Spotify app
    /// (a computer with this Mac's name, new since a launch here; two such Macs give no device).
    /// Music on a phone or another computer has another active device ID, so it counts as not
    /// playing. Before a first load or warm-up finds `device`, nothing counts. Sent on each change.
    private func noteOutside(_ state: SpotifyPlayerState, device: String) {
        guard !ours, !loading else { return }
        let playing = state.activeDeviceID == device && state.hasTrack && state.isRunning
        let song = playing && state.trackURI != outsideTrack
        if playing { outsideTrack = state.trackURI }
        guard playing != outsidePlaying || song else { return }
        outsidePlaying = playing
        send(.outsideMusic(playing: playing, song: song))
    }

    /// The outside music ends: myPod took control, or Spotify quit.
    private func endOutside() {
        guard outsidePlaying else { return }
        outsidePlaying = false
        send(.outsideMusic(playing: false, song: false))
    }

    /// Our playback ended outside Clasify. A resumable end keeps the place for Play.
    /// The log gets the reason kind only, with no IDs or names.
    private func lose(_ message: String, resumable: Bool, reason: ControlLoss) {
        let words = [ControlLoss.spotifyQuit: "Spotify quit", .stoppedInSpotify: "no active device", .otherDevice: "other device"]
        log.notice("lost control: \(words[reason] ?? reason.rawValue, privacy: .public)")
        send(.controlLost(reason))  // CLA-97
        ours = false
        ticker?.cancel()
        if resumable && !followedOther { resumePoint = (lastTrack.isEmpty ? startedTrack : lastTrack, playlist, position) }
        send(.playbackFailed(message, generation: generation))
    }

    private func fire(_ command: Int32, evenAfterStop: Bool = false) {
        // Next and prev are not sent again after a timeout: if the first one did arrive, the
        // second one skips twice. The same rule as the bridge's own retry.
        let skip = command == LSB_COMMAND_NEXT || command == LSB_COMMAND_PREV
        resend(skip ? .place : .playState, evenAfterStop: evenAfterStop, afterTimeout: !skip, relative: skip) { [client] in
            client.fire(command, to: $0, onStale: $1)
        }
    }

    /// Sends one fire-and-forget command to our device. When the session dropped, it logs in
    /// again and sends the command once more. When the command timed out, it logs in again by
    /// force, and with `afterTimeout` sends it once more (CLA-88). `call` gets the device ID
    /// and the timeout handler, and returns the status. The retry is dropped after a new load.
    /// `evenAfterStop` keeps it after a stop.
    private func resend(
        _ lane: Lane, evenAfterStop: Bool = false, afterTimeout: Bool = true, relative: Bool = false,
        _ call: @escaping @MainActor (String, StaleHandler?) -> Int32
    ) {
        guard ours, let device else { return }
        let id = loadID
        // A newer command in the same lane goes out after this one fails. Then this one is not
        // sent again: an old Pause must not undo a newer Play, and an old seek must not move
        // the next track. A volume change keeps a pending Pause. A `relative` command (next,
        // prev) is never superseded: two Nexts that were not queued are two skips.
        sent[lane, default: 0] += 1
        let mine = sent[lane]
        let again: @MainActor (Bool) async -> Void = { [weak self] force in
            guard let self, await self.relogin(force), id == self.loadID, relative || mine == self.sent[lane],
                  self.ours || evenAfterStop, let device = self.device else { return }
            _ = call(device, nil)
        }
        let onStale: StaleHandler = { [weak self] in
            log.notice("Connect call timed out; logging in again")
            if let self, !evenAfterStop, id == self.loadID, self.ours { self.sessionLost(.timeout) }  // CLA-97: not an old load's command
            if afterTimeout { Task { await again(true) } } else { Task { _ = await self?.relogin(true) } }
        }
        guard call(device, onStale) == LSB_ERR_NOT_LOGGED_IN else { return }
        if !evenAfterStop { sessionLost(.sessionDrop) }  // CLA-97: a stop's Pause is no loss
        Task { await again(false) }
    }

    /// CLA-97: control is lost until a state of our device comes from the new login.
    private func sessionLost(_ reason: ControlLoss) {
        (lostSession, relogged) = (true, false)
        send(.controlLost(reason))
    }

    /// Logs in again. A working session lets the next state of our device confirm control (CLA-97).
    private func relogin(_ force: Bool) async -> Bool {
        let done = await reconnect(force)
        if done && lostSession { relogged = true }
        return done
    }

    private func controlBack() {
        (lostSession, relogged) = (false, false)
        send(.controlBack)
    }

    /// The session was logged in again. Register it, so the cluster watch delivers states again.
    func sessionRestored() {
        if lostSession { relogged = true }  // CLA-97: the next state of our device confirms it
        Task { _ = try? await client.devices() }
        // The new registration makes the cluster watch send the current state. If our device
        // has a track, `handle` takes control again, or at launch shows what Spotify plays.
        rejoinUntil = ContinuousClock.now + .seconds(10)
    }

    /// Takes control after a new login, when our device has a track and no load or stop came
    /// since. After our own load, the state goes to the store as a track change. With no load
    /// yet, as at launch, the store adopts the track, so Play, Pause and Next work at once.
    private func rejoin(_ state: SpotifyPlayerState) {
        guard let until = rejoinUntil, ContinuousClock.now < until, !ours, !loading, !movedAway,
              state.hasTrack else { return }
        rejoinUntil = nil
        ours = true
        resumePoint = nil
        loaded = nil
        guard startedTrack.isEmpty else {
            log.notice("took control again after a new login")
            lastTrack = ""  // so the store gets the track and its play state
            // Shuffle or repeat can have changed in Spotify while the session was down.
            Task { await applyOptions() }
            resend(.volume) { [client] in client.fireVolume(device: $0, percent: self.volume, onStale: $1) }  // and the volume
            return
        }
        // Never change what the user already hears: no volume, shuffle or repeat goes out.
        // Clasify's options apply again at its next load, and its volume at the next wheel turn.
        log.notice("picked up what Spotify plays here (\(Self.contextKind(state.contextURI), privacy: .public))")
        // The playlist as in `handle`: a playlist or Liked Songs, else none to go on from.
        context = state.contextURI
        let likedSongs = context.hasSuffix(":collection")
        followedOther = !Self.canLoad(context)
        playlist = followedOther ? nil : likedSongs ? Playlist.likedSongsID : context
        startedTrack = state.trackURI
        lastTrack = state.trackURI
        lastRunning = state.isRunning  // `handle` then sends no track change for it
        send(.adopted(track: state.trackURI, playlist: playlist, playing: state.isRunning,
                      position: state.position, generation: generation))
    }

    /// Runs one session call, and after a dropped session logs in again and runs it once more.
    /// A call that timed out (LSB_ERR_STALE_SESSION) logs in again by force (CLA-88).
    private func again<T>(_ call: @MainActor () async throws -> T) async throws -> T {
        var stale = false
        return try await retryOnce(after: { await self.reconnect(stale) }, when: { error in
            let status = (error as? BridgeError)?.status
            stale = status == LSB_ERR_STALE_SESSION
            if stale { log.notice("Connect call timed out; logging in again") }
            return stale || status == LSB_ERR_NOT_LOGGED_IN
        }, call)
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
                    // A song of an album plays the whole album from that song, like any other
                    // context (CLA-45). A song from Artists plays its artist's context (CLA-195).
                    // Spotify takes a plain track list but plays nothing.
                    try await again { try await client.play(device: found, context: contextURI, track: trackID) }
                    if Album.isID(contextURI) { Self.logTime("load: album context played", since: start) }
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
                return fail("Spotify closed. Press play to go on", id, started: true)
            }
            if pendingSeek == nil, let position, position >= 1 { client.fireSeek(device: found, seconds: position) }
            if !wantsRunning { client.fire(LSB_COMMAND_PAUSE, to: found) }
            for command in pendingSkips { client.fire(command, to: found) }
            // A scrub during the load came after any skip, because a skip clears it.
            if let seek = pendingSeek { client.fireSeek(device: found, seconds: seek) }
            pendingSeek = nil
            client.fireVolume(device: found, percent: volume)
            context = contextURI
            followedOther = false
            loaded = (pendingSkips.isEmpty ? trackID : nil, ContinuousClock.now)
            pendingSkips = []
            loading = false
            ours = true
            resumePoint = nil
            beforeLoad = nil
        } catch let error as PlayerError {
            fail(error.message, id)
        } catch {
            Self.logFailure("play", error)
            fail("That didn’t play. Try again", id)
        }
    }

    /// `started` is true when Spotify took the play command, so the old track is gone.
    private func fail(_ message: String, _ id: Int, started: Bool = false) {
        guard id == loadID else { return }
        loading = false
        guard storeLoad, !started else {
            beforeLoad = nil
            return send(.playbackFailed(message, generation: generation))
        }
        let restored = beforeLoad != nil
        restoreBeforeLoad()
        send(.loadFailed(message, generation: generation))
        // The old track shows again, but Spotify quit or it was not ours: show it paused, so Play goes on.
        if restored && !ours { send(.trackChanged(lastTrack.isEmpty ? startedTrack : lastTrack, playing: false, generation: generation)) }
        // After the store shows the old track again: it can have changed, or moved away, during
        // the load. Cluster updates come only on changes, so handle the newest state again.
        if ours, let latest { handle(latest, receivedAt: latestAt) }
    }

    /// A context that the bridge can load again, so Clasify keeps it as its own play:
    /// Liked Songs, a playlist, an album (which a song from Albums plays in), or an artist
    /// (which a song from Artists plays in, CLA-195).
    nonisolated static func canLoad(_ context: String) -> Bool { ResumePlan.canLoad(context) }

    /// `Playlist.likedSongsID` plays the user's Liked Songs. Other IDs are Spotify playlist, album or artist URIs.
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
        case LSB_ERR_STALE_SESSION: "Connect call timed out"
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
            case .ambiguous: throw PlayerError(message: "Spotify is open on another Mac. Close it there")
            case .none: try await Task.sleep(for: .seconds(1))
            }
        }
        // Spotify runs but has no device: it is logged out, or logged in to another account.
        // The toast fits one line (card BD, change 193).
        throw PlayerError(message: "Use the same account in Spotify")
    }

    private func launchSpotify() async throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else {
            send(.spotifyAppFound(false))  // the Spotify App screen opens (card BB, change 131)
            throw PlayerError(message: "We need the Spotify app to play music")
        }
        guard !appOff else { throw PlayerError(message: "") }  // Apple Music became active
        let start = ContinuousClock.now
        try await Self.open(url)
        Self.logTime("Spotify launched", since: start)
        let pid = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first?.processIdentifier
        guard !appOff else {
            // Apple Music became active while Spotify opened: quit it again (CLA-103).
            if let pid { NSRunningApplication(processIdentifier: pid)?.terminate() }
            throw PlayerError(message: "")
        }
        launchedApp = pid
        // Safety net: Spotify must never come to the front.
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first,
           app.isActive || !app.isHidden {
            app.hide()
            if mayRaise() {
                NSApp.activate()
                DeviceWindow.raise()  // so the device window does not stay behind (CLA-47)
            }
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

    /// `receivedAt` is when the bridge sent the state, so the position moves on from then.
    private func handle(_ state: SpotifyPlayerState, receivedAt: ContinuousClock.Instant = .now) {
        latest = state
        latestAt = receivedAt
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
        } else if !state.activeDeviceID.isEmpty {
            rejoinUntil = nil  // it plays elsewhere: a later move to this Mac is not ours to take
        }
        noteOutside(state, device: device)
        guard ours else { return }
        if let loaded, ContinuousClock.now - loaded.at < .seconds(3),
           state.activeDeviceID != device || !isLoaded(state, track: loaded.track) {
            return  // still what played before the load
        }
        loaded = nil
        if let takenBackAt, state.activeDeviceID != device, ContinuousClock.now - takenBackAt < .seconds(3) {
            return  // still from before the transfer
        }
        takenBackAt = nil
        guard state.activeDeviceID == device else {
            // The user moved playback to another device, or Spotify quit. Do not fight it.
            // With no active device, nothing plays elsewhere, so Play may continue here. After a
            // move away, the place is kept too: when that device stops, Play goes on here (CLA-93).
            let stopped = state.activeDeviceID.isEmpty
            let reason: ControlLoss = stopped ? .stoppedInSpotify : .otherDevice
            movedAway = !stopped
            return lose(stopped ? "The music stopped in Spotify" : "Now playing on another device", resumable: true, reason: reason)
        }
        if relogged { controlBack() }  // CLA-97: our device answers from the new login
        // Our Spotify app moved to another context: autoplay after the playlist ended, or a
        // list picked in Spotify itself. Follow it and keep control. Liked Songs can come back
        // as a playlist URI, so only a playlist context is compared.
        if !context.hasSuffix(":collection") && !state.contextURI.isEmpty && state.contextURI != context {
            log.notice("following Spotify into another context (\(Self.contextKind(state.contextURI), privacy: .public))")
            context = state.contextURI
            // So Play after a quit loads the track in its own context. The bridge can load only
            // a playlist, an album, an artist or Liked Songs, so a station keeps no place to go on from.
            let likedSongs = state.contextURI.hasSuffix(":collection")
            followedOther = !Self.canLoad(state.contextURI)
            if !followedOther { playlist = likedSongs ? Playlist.likedSongsID : state.contextURI }
        }
        let gen = generation
        if !state.hasTrack {
            if lastRunning { send(.trackEnded(generation: gen)) }  // Spotify stopped at the end of the context
        } else if state.trackURI != lastTrack || state.isRunning != lastRunning {
            send(.trackChanged(state.trackURI, playing: state.isRunning, generation: gen))
        }
        lastTrack = state.trackURI
        lastRunning = state.hasTrack && state.isRunning
        position = state.position
        send(.position(state.position, generation: gen))
        tick(from: state, since: receivedAt)
    }

    private func tick(from state: SpotifyPlayerState, since start: ContinuousClock.Instant = .now) {
        ticker?.cancel()
        guard state.hasTrack, state.isRunning else { return }
        let gen = generation
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
