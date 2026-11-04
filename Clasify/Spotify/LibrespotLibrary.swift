import ClasifyCore
import Foundation
import LibrespotBridge
import os

/// Only the status and the URI go to the unified log, never a bridge message.
private let log = Logger(subsystem: "app.clasify.Clasify", category: "library")

/// The user's Spotify library, read through librespot (not the Web API). It also owns
/// the login: the refresh token is in the Keychain, the access token only in memory.
///
/// `fetchLibrary` returns the whole library, as the current `Library` protocol asks.
/// A later ClasifyCore change splits it per screen.
@MainActor
final class LibrespotLibrary: Library {
    /// The most bridge reads that run at the same time.
    nonisolated static let maxReads = 4

    private let client: LibrespotClient
    /// The canonical Spotify username, after a login. The Spotify-app player needs it
    /// for the Liked Songs context `spotify:user:<username>:collection`.
    private(set) var username: String?
    /// The library of this session. `logOut` and a new login clear it.
    private var cache: [Playlist]?
    /// Bumped by every login and logout, so a read that started for an older session
    /// cannot fill the cache.
    private var session = 0
    /// The running `restoreSession`. Two refreshes with one refresh token can fail,
    /// because Spotify can replace the token, so callers share one.
    private var restoring: Task<Bool, Never>?
    /// The newest bridge login (it may be done). Bridge logins run one at a time: when two overlap, the
    /// bridge can send LOGGED_IN for both, and the client could not tell them apart.
    private var bridgeLogin: Task<Void, Never>?

    init(client: LibrespotClient) {
        self.client = client
    }

    var isLoggedIn: Bool { username != nil }

    /// Logs in through the browser. Returns false when the user cancels or the login fails.
    func logIn() async -> Bool {
        do {
            try await browserLogIn()
            return true
        } catch {
            let status = (error as? BridgeError)?.status ?? 0
            log.error("login failed: status \(status, privacy: .public)")
            return false
        }
    }

    /// Throws when the user cancels, Spotify refuses, or the Keychain refuses the token.
    private func browserLogIn() async throws {
        let mine = session
        let tokens = try await LibrespotClient.oauthLogin()
        // A logout or another login came while the browser was open. Do not undo it.
        guard session == mine else { throw BridgeError.cancelled }
        guard let refresh = tokens.refreshToken else { throw BridgeError.noRefreshToken }
        try await startSession(tokens.accessToken)
        // Keep the login only after it worked.
        guard RefreshTokenStore.save(refresh) else {
            session += 1
            username = nil
            client.logout()  // the UI shows the login screen, so no session may stay
            throw BridgeError.keychain
        }
    }

    /// Stops a login that waits for the browser. A login that already has its tokens
    /// stops too, because the user went back to the login screen.
    func cancelLogIn() async {
        session += 1
        username = nil
        cache = nil
        client.logout()  // a bridge login that already started must not leave a session
        await LibrespotClient.oauthCancel()
    }

    /// Logs in again with the refresh token in the Keychain. Returns false when there is
    /// no stored login, or the refresh or the login failed. The stored token stays, because
    /// the bridge cannot tell "offline" from "refused". Only `logOut` removes it.
    @discardableResult
    func restoreSession() async -> Bool {
        if let restoring { return await restoring.value }
        let task = Task { await self.refreshAndStart() }
        restoring = task
        let restored = await task.value
        if restoring == task { restoring = nil }
        return restored
    }

    private func refreshAndStart() async -> Bool {
        guard let refresh = RefreshTokenStore.read() else { return false }
        let mine = session
        do {
            let tokens = try await LibrespotClient.oauthRefresh(refresh)
            // A logout or a login came while the refresh ran. Do not save a token or
            // start a session, because that would undo it.
            guard session == mine else { return false }
            // Spotify can replace the refresh token, and then the old one stops working.
            // Keep the new one at once. If the Keychain refuses it, report no session,
            // so the app does not look logged in with a login that cannot come back.
            if let newRefresh = tokens.refreshToken, !RefreshTokenStore.save(newRefresh) { return false }
            try await startSession(tokens.accessToken)
            return true
        } catch {
            return false
        }
    }

    /// Forgets the login: the Keychain item, the username and the cache. The access token
    /// is never kept: it goes straight to the bridge session.
    func logOut() {
        RefreshTokenStore.delete()
        client.logout()
        session += 1
        username = nil
        cache = nil
        // A restore that still runs sees the new session and stops. A later restore must not join it.
        restoring = nil
    }

    func fetchLibrary() async -> [Playlist]? {
        if let cache { return cache }
        if !isLoggedIn, !(await restoreSession()) { return nil }
        let mine = session
        do {
            return try await readAndCache()
        } catch let error as BridgeError where error == .cancelled {
            return nil  // The account changed while it read. The reducer drops this load.
        } catch {
            // The account changed while it read. A restore now would log the old account in again.
            guard session == mine else { return nil }
            // The session can drop. Log in again once, then try once more.
            guard await restoreSession() else { return nil }
            return try? await readAndCache()
        }
    }

    private func startSession(_ token: String) async throws {
        session += 1
        let mine = session
        cache = nil
        username = nil
        // Chain this login after the one before it, so the two never overlap.
        let (client, previous) = (self.client, bridgeLogin)
        let attempt = Task {
            await previous?.value
            // A cancel or logout while this login waited in line: do not start it.
            guard self.session == mine else { throw BridgeError.cancelled }
            return try await client.login(accessToken: token)
        }
        bridgeLogin = Task { _ = await attempt.result }
        let name = try await attempt.value
        guard session == mine else { throw BridgeError.cancelled }  // a logout or newer login came first
        username = name
    }

    private func readAndCache() async throws -> [Playlist] {
        let mine = session
        let library = try await Self.readLibrary(client)
        guard session == mine else { throw BridgeError.cancelled }  // the account changed meanwhile
        cache = library
        return library
    }

    /// Liked Songs first, then every playlist in the user's order. A playlist that cannot
    /// be read (deleted, blocked in the region) stays in the list with no tracks. Only a
    /// failed playlist list, a missing login, or a failure of every read fails it all.
    private nonisolated static func readLibrary(_ client: LibrespotClient) async throws -> [Playlist] {
        let summaries = try await client.playlists()
        var jobs: [(index: Int, uri: String?)] = [(0, nil)]
        jobs += summaries.enumerated().map { (index: $0.offset + 1, uri: $0.element.uri) }
        var tracks = [[Track]](repeating: [], count: jobs.count)
        var failures: [BridgeError] = []
        try await withThrowingTaskGroup(of: (Int, Result<[Track], BridgeError>).self) { group in
            var next = jobs.makeIterator()
            func start() {
                guard let job = next.next() else { return }
                group.addTask {
                    do {
                        let result = try await client.tracks(playlistURI: job.uri)
                        return (job.index, .success(result))
                    } catch let error as BridgeError {
                        if error.status == LSB_ERR_NOT_LOGGED_IN { throw error }
                        let uri = job.uri ?? "Liked Songs"
                        log.error("cannot read \(uri, privacy: .public): status \(error.status, privacy: .public)")
                        return (job.index, .failure(error))
                    }
                }
            }
            for _ in 0..<maxReads { start() }
            while let done = try await group.next() {
                switch done.1 {
                case .success(let result): tracks[done.0] = result
                case .failure(let error): failures.append(error)
                }
                start()
            }
        }
        // Every read failed: the session is most likely gone, so let the caller log in again.
        if failures.count == jobs.count, let first = failures.first { throw first }
        let liked = Playlist(id: Playlist.likedSongsID, name: "Liked Songs", tracks: tracks[0])
        let playlists = summaries.enumerated().map {
            Playlist(id: $0.element.uri, name: $0.element.name, tracks: tracks[$0.offset + 1])
        }
        return [liked] + playlists
    }
}
