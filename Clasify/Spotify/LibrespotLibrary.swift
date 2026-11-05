import ClasifyCore
import Foundation
import LibrespotBridge
import os

/// Only the status and the URI go to the unified log, never a bridge message.
private let log = Logger(subsystem: "app.clasify.Clasify", category: "library")
/// How long each login and library step takes, in ms. Only the step name, the time and a
/// count go to the log: never a token, a username or a playlist name.
/// Read it with `log stream --predicate 'subsystem == "app.clasify.Clasify" && category == "timing"'`.
private let timing = Logger(subsystem: "app.clasify.Clasify", category: "timing")

/// Runs one step and logs its time.
@MainActor
private func timed<T: Sendable>(_ step: String, count: (T) -> Int? = { _ in nil }, _ body: () async throws -> T) async throws -> T {
    let start = ContinuousClock.now
    func ms() -> Int { Int((ContinuousClock.now - start) / .milliseconds(1)) }
    do {
        let value = try await body()
        if let n = count(value) {
            timing.notice("\(step, privacy: .public): \(ms(), privacy: .public) ms, \(n, privacy: .public) items")
        } else {
            timing.notice("\(step, privacy: .public): \(ms(), privacy: .public) ms")
        }
        return value
    } catch {
        timing.notice("\(step, privacy: .public): failed after \(ms(), privacy: .public) ms")
        throw error
    }
}

/// The user's Spotify library, read through librespot (not the Web API). It also owns
/// the login: the refresh token is in the Keychain, the access token only in memory.
///
/// Each read runs only when a screen or `prefetch` asks for it. The result stays in memory
/// for the session, and a second caller joins a read that still runs. Nothing goes to disk.
@MainActor
final class LibrespotLibrary: Library {
    private let client: LibrespotClient
    /// The canonical Spotify username, after a login. The Spotify-app player needs it
    /// for the Liked Songs context `spotify:user:<username>:collection`.
    private(set) var username: String?
    /// The reads of this session, done or running. A failed read leaves. `clearCache` empties
    /// both at each login and logout, so a read of another account is never used.
    private var playlistsRead: Task<[PlaylistSummary], any Error>?
    /// By playlist URI, or `Playlist.likedSongsID`.
    private var trackReads: [String: Task<[Track], any Error>] = [:]
    /// Bumped by every login and logout, so a read that started for an older session
    /// cannot fill the cache.
    private var session = 0
    /// The running `restoreSession`. Two refreshes with one refresh token can fail,
    /// because Spotify can replace the token, so callers share one.
    private var restoring: Task<Restore, Never>?
    /// Runs after each background login that worked, from a library read or from `SessionKeeper`.
    var restored: @MainActor () -> Void = {}
    /// The newest bridge login (it may be done). Bridge logins run one at a time. Each event also
    /// carries its login id, so a late event of an older login is ignored.
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
        let tokens = try await timed("oauth login") { try await LibrespotClient.oauthLogin() }
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
        clearCache()
        client.logout()  // a bridge login that already started must not leave a session
        await LibrespotClient.oauthCancel()
    }

    /// Logs in again with the refresh token in the Keychain. Returns false when there is
    /// no stored login, or the refresh or the login failed. The stored token stays, because
    /// the bridge cannot tell "offline" from "refused". Only `logOut` removes it.
    @discardableResult
    func restoreSession() async -> Bool { await reconnect() == .done }

    /// How a login with the stored refresh token ended.
    enum Restore: Sendable { case done, failed, refused }

    /// Logs in again with the stored refresh token, for example after the session dropped.
    /// The library stays when the account is the same. `.refused` means that Spotify rejected
    /// the token or no login is stored: only a new browser login helps. Callers share one run,
    /// because two refreshes with one refresh token can fail.
    func reconnect() async -> Restore {
        if let restoring { return await restoring.value }
        let task = Task {
            let result = await self.refreshAndStart()
            // Inside the task, so it runs once for each login, whichever caller started it.
            if result == .done { self.restored() }
            return result
        }
        restoring = task
        let result = await task.value
        if restoring == task { restoring = nil }
        return result
    }

    private func refreshAndStart() async -> Restore {
        guard let refresh = RefreshTokenStore.read() else { return .refused }
        let mine = session
        do {
            let tokens = try await timed("oauth refresh") { try await LibrespotClient.oauthRefresh(refresh) }
            // A logout or a login came while the refresh ran. Do not save a token or
            // start a session, because that would undo it.
            guard session == mine else { return .failed }
            // Spotify can replace the refresh token, and then the old one stops working.
            // Keep the new one at once. If the Keychain refuses it, report no session,
            // so the app does not look logged in with a login that cannot come back.
            if let newRefresh = tokens.refreshToken, !RefreshTokenStore.save(newRefresh) { return .failed }
            try await startSession(tokens.accessToken)
            return .done
        } catch let error as BridgeError where error.status == LSB_ERR_REFUSED {
            return .refused
        } catch {
            return .failed
        }
    }

    /// Forgets the login: the Keychain item, the username and the cache. The access token
    /// is never kept: it goes straight to the bridge session.
    func logOut() {
        RefreshTokenStore.delete()
        client.logout()
        session += 1
        username = nil
        clearCache()
        // A restore that still runs sees the new session and stops. A later restore must not join it.
        restoring = nil
    }

    func playlists() async -> [Playlist]? {
        let list = await withSession { try await self.readPlaylists() }
        return list?.map { Playlist(id: $0.uri, name: $0.name, tracks: [], trackCount: $0.trackCount) }
    }

    func tracks(of playlist: String) async -> [Track]? {
        await withSession { try await self.readTracks(playlist) }
    }

    func track(_ id: String) async -> Track? {
        let client = self.client
        return await withSession { try await client.track(uri: id) } ?? nil
    }

    /// Two reads at a time: Liked Songs and the playlist list. A screen that opens meanwhile
    /// joins the running read.
    func prefetch() async {
        async let liked = tracks(of: Playlist.likedSongsID)
        async let list = playlists()
        _ = await (liked, list)
    }

    /// Runs a read in the session. It logs in again once when the session dropped.
    private func withSession<T: Sendable>(_ read: () async throws -> T) async -> T? {
        if !isLoggedIn, !(await restoreSession()) { return nil }
        let mine = session
        do {
            return try await read()
        } catch let error as BridgeError where error == .cancelled {
            return nil  // The account changed while it read. The reducer drops this load.
        } catch let error as BridgeError where error.status == LSB_ERR_NOT_LOGGED_IN {
            // The account changed while it read. A restore now would log the old account in again.
            guard session == mine else { return nil }
            // The session dropped. Log in again once, then try once more.
            guard await restoreSession() else { return nil }
            return try? await read()
        } catch {
            // Any other failure (a deleted playlist, a network error) would fail again after a
            // login, and a login empties the cache. The screen offers a retry.
            return nil
        }
    }

    private func readPlaylists() async throws -> [PlaylistSummary] {
        let mine = session
        let client = self.client
        let task = playlistsRead ?? Task { try await timed("rootlist", count: { $0.count }) { try await client.playlists() } }
        playlistsRead = task
        do {
            let list = try await task.value
            guard session == mine else { throw BridgeError.cancelled }  // the account changed meanwhile
            return list
        } catch {
            if playlistsRead == task { playlistsRead = nil }  // so that the next open reads again
            throw error
        }
    }

    /// A playlist that cannot be read (deleted, blocked in the region) fails, and its screen offers a retry.
    private func readTracks(_ id: String) async throws -> [Track] {
        let mine = session
        let client = self.client
        let uri = id == Playlist.likedSongsID ? nil : id
        let name = uri ?? "Liked Songs"
        let task = trackReads[id] ?? Task<[Track], any Error> {
            do {
                // The time covers the context read and the metadata batches.
                return try await timed(uri == nil ? "liked songs read" : "playlist read", count: { $0.count }) {
                    try await client.tracks(playlistURI: uri)
                }
            } catch let error as BridgeError {
                log.error("cannot read \(name, privacy: .public): status \(error.status, privacy: .public)")
                throw error
            }
        }
        trackReads[id] = task
        do {
            let tracks = try await task.value
            guard session == mine else { throw BridgeError.cancelled }
            return tracks
        } catch {
            if trackReads[id] == task { trackReads[id] = nil }
            throw error
        }
    }

    private func clearCache() {
        playlistsRead = nil
        trackReads = [:]
    }

    /// A login of the same account keeps the library and the username, so a reconnect
    /// is not seen above. Another account starts empty.
    private func startSession(_ token: String) async throws {
        session += 1
        let mine = session
        let previousName = username
        // Chain this login after the one before it, so the two never overlap.
        let (client, previous) = (self.client, bridgeLogin)
        let attempt = Task {
            await previous?.value
            // A cancel or logout while this login waited in line: do not start it.
            guard self.session == mine else { throw BridgeError.cancelled }
            return try await timed("bridge login") { try await client.login(accessToken: token) }
        }
        bridgeLogin = Task { _ = await attempt.result }
        let name = try await attempt.value
        guard session == mine else { throw BridgeError.cancelled }  // a logout or newer login came first
        if name != previousName { clearCache() }
        username = name
    }
}
