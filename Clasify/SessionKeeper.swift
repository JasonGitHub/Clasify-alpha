import AppKit
import ClasifyCore
import Network
import os

/// Only kinds and times go to the log, never a token or a username.
private let log = Logger(subsystem: "app.clasify.Clasify", category: "session")

/// Keeps the librespot session alive. librespot does not reconnect after a dropped
/// connection (sleep, a network change), so this checks every 5 s and after each wake.
/// After a drop, it logs in again with the stored refresh token, without a sign-out.
/// It signs out only when Spotify refuses the refresh token. While Apple Music is active, it
/// does nothing: the Spotify session is not used then (CLA-103).
/// After a network change, or when a Connect call times out, the session can still look
/// alive while its connections are dead. Then it logs in again by force (CLA-88).
@MainActor
final class SessionKeeper {
    private let client: LibrespotClient
    private let library: LibrespotLibrary
    private let player: SpotifyConnectPlayer
    private weak var store: Store?
    /// The reconnect that runs. The poll, the wake and the player all wait on it.
    private var running: Task<Bool, Never>?
    private var backoff = Backoff()
    /// The poll does not try again before this time. A player command does.
    private var notBefore = ContinuousClock.now
    /// Decides when a network change needs a new login.
    private var paths = PathWatch()
    private let monitor = NWPathMonitor()
    /// When the newest login worked. A call that the old session started can still time out
    /// after it, and a forced login just after one is not needed.
    private var loggedInAt: ContinuousClock.Instant?
    /// A forced login failed: the poll tries it again after the backoff, also while the old
    /// session still looks alive. Any working login ends it.
    private var forceDue = false

    init(client: LibrespotClient, library: LibrespotLibrary, player: SpotifyConnectPlayer, store: Store) {
        self.client = client
        self.library = library
        self.player = player
        self.store = store
        // A library read can log in again on its own. Each path registers the player again.
        library.restored = { [weak self, weak player] in
            self?.backoff.reset()
            self?.forceDue = false
            self?.notBefore = .now  // a player command can succeed during a wait: end that wait
            player?.sessionRestored()
            self?.store?.send(.libraryStale)  // changes made during the drop show
        }
        // A browser login (the first launch, or after Log out or an expired session) registers
        // the player too, so that Clasify adopts what Spotify plays, as after a stored login
        // (CLA-60). The library was just read for this login, so it is not stale.
        library.loggedIn = { [weak self, weak player] in
            self?.backoff.reset()
            self?.notBefore = .now
            player?.sessionRestored()
        }
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                self.check()
            }
        }
        // A Connect command that nobody waits on timed out: only a new login helps.
        LibrespotClient.staleSession = { [weak self] in
            log.notice("Connect call timed out; logging in again")
            self?.forced()
        }
        monitor.pathUpdateHandler = { [weak self] path in
            // The path goes to the log only as "none" or "usable", never as names or addresses.
            let name = path.status == .satisfied
                ? (path.availableInterfaces.map(\.name) + path.gateways.map { "\($0)" }).joined(separator: " ")
                : nil
            // The queue is .main, so this runs on the main actor.
            MainActor.assumeIsolated { self?.pathChanged(name) }
        }
        monitor.start(queue: .main)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // The queue is .main, so this runs on the main actor.
            MainActor.assumeIsolated {
                self?.notBefore = .now  // a wake is a good time to try at once
                self?.check()
            }
        }
    }

    /// A network path update. A changed path logs in again once it settles.
    private func pathChanged(_ path: String?) {
        let now = Dependencies.live.now()
        paths.update(path, at: now)
        guard paths.due != nil else { return }
        log.notice("network path changed (\(path == nil ? "none" : "usable", privacy: .public)); login in \(PathWatch.settle, privacy: .public) s")
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(PathWatch.settle))
            guard let self, self.paths.take(at: Dependencies.live.now()) else { return }
            self.loggedInAt = nil  // a login just before the change used the old network
            self.forced()
        }
    }

    /// Logs in again by force, when the user is signed in. A login that runs already is joined.
    private func forced() {
        guard store?.state.signedIn == true, store?.state.service == .spotify, library.isLoggedIn else { return }
        Task { _ = await reconnect(force: true) }
    }

    /// Starts a reconnect when the user is signed in and the session dropped, or a forced
    /// login failed before.
    private func check() {
        guard running == nil, ContinuousClock.now >= notBefore, store?.state.signedIn == true,
            store?.state.service == .spotify, library.isLoggedIn, forceDue || !client.sessionAlive
        else { return }
        let force = forceDue
        Task { _ = await reconnect(force: force) }
    }

    /// Logs in again. Returns true when the session works again. `force` logs in also when
    /// the session looks alive, because a call timed out or the network changed.
    func reconnect(force: Bool = false) async -> Bool {
        if let running { return await running.value }
        let task = Task { await run(force: force) }
        running = task
        let ok = await task.value
        if running == task { running = nil }
        return ok
    }

    private func run(force: Bool) async -> Bool {
        if !force && client.sessionAlive { return true }  // another login came first
        if force, client.sessionAlive, let loggedInAt, ContinuousClock.now - loggedInAt < .seconds(5) { return true }
        log.notice("\(force ? "forced login" : "session dropped; logging in again", privacy: .public)")
        let start = ContinuousClock.now
        let result = await library.reconnect()
        let ms = Int((ContinuousClock.now - start) / .milliseconds(1))
        // A switch to Apple Music during the login: its result must not sign out or replace
        // the Apple Music screens. Spotify logs in again after a switch back.
        guard store?.state.service == .spotify else {
            log.notice("login ended after a switch to Apple Music; result dropped")
            return false
        }
        switch result {
        case .done:
            log.notice("logged in again: \(ms, privacy: .public) ms")
            loggedInAt = .now
            forceDue = false
            return true  // `library.restored` registered the player again
        case .refused:
            log.error("login refused after \(ms, privacy: .public) ms; signing out")
            store?.send(.expire)
            return false
        case .notPremium:
            // No retry: a new login would end the same way. The Premium screen shows, and
            // its "Check again" logs in again (CLA-66). Signed out, so the poll stops.
            log.error("account is not Premium after \(ms, privacy: .public) ms")
            store?.send(.notPremium(token: nil))
            return false
        case .failed:
            if force { forceDue = true }  // the old session can still look alive: keep trying
            let wait = backoff.failed()
            notBefore = .now + .seconds(wait)
            log.error("login failed after \(ms, privacy: .public) ms; next try in \(wait, privacy: .public) s")
            return false
        }
    }
}
