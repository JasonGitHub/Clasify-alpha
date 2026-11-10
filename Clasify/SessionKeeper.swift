import AppKit
import ClasifyCore
import os

/// Only kinds and times go to the log, never a token or a username.
private let log = Logger(subsystem: "app.clasify.Clasify", category: "session")

/// Keeps the librespot session alive. librespot does not reconnect after a dropped
/// connection (sleep, a network change), so this checks every 5 s and after each wake.
/// After a drop, it logs in again with the stored refresh token, without a sign-out.
/// It signs out only when Spotify refuses the refresh token.
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

    init(client: LibrespotClient, library: LibrespotLibrary, player: SpotifyConnectPlayer, store: Store) {
        self.client = client
        self.library = library
        self.player = player
        self.store = store
        // A library read can log in again on its own. Each path registers the player again.
        library.restored = { [weak self, weak player] in
            self?.backoff.reset()
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

    /// Starts a reconnect when the user is signed in and the session dropped.
    private func check() {
        guard running == nil, ContinuousClock.now >= notBefore, store?.state.signedIn == true,
            library.isLoggedIn, !client.sessionAlive
        else { return }
        Task { _ = await reconnect() }
    }

    /// Logs in again. Returns true when the session works again.
    func reconnect() async -> Bool {
        if let running { return await running.value }
        let task = Task { await run() }
        running = task
        let ok = await task.value
        if running == task { running = nil }
        return ok
    }

    private func run() async -> Bool {
        if client.sessionAlive { return true }  // another login came first
        log.notice("session dropped; logging in again")
        let start = ContinuousClock.now
        let result = await library.reconnect()
        let ms = Int((ContinuousClock.now - start) / .milliseconds(1))
        switch result {
        case .done:
            log.notice("logged in again: \(ms, privacy: .public) ms")
            return true  // `library.restored` registered the player again
        case .refused:
            log.error("login refused after \(ms, privacy: .public) ms; signing out")
            store?.send(.expire)
            return false
        case .failed:
            let wait = backoff.failed()
            notBefore = .now + .seconds(wait)
            log.error("login failed after \(ms, privacy: .public) ms; next try in \(wait, privacy: .public) s")
            return false
        }
    }
}
