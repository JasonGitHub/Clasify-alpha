import ClasifyCore
import Foundation

/// The user's Spotify library, read through librespot (not the Web API). It also owns
/// the login: the refresh token is in the Keychain, the access token only in memory.
///
/// Login is not wired into the reducer yet. `fetchLibrary` returns the whole library,
/// as the current `Library` protocol asks. A later ClasifyCore change splits it per screen.
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

    init(client: LibrespotClient) {
        self.client = client
    }

    var isLoggedIn: Bool { username != nil }

    /// Logs in through the browser. Throws when the user cancels or Spotify refuses.
    func logIn() async throws {
        let tokens = try await LibrespotClient.oauthLogin()
        guard let refresh = tokens.refreshToken, RefreshTokenStore.save(refresh) else {
            throw BridgeError.keychain
        }
        try await startSession(tokens.accessToken)
    }

    /// Stops a login that waits for the browser.
    func cancelLogIn() async {
        await LibrespotClient.oauthCancel()
    }

    /// Logs in again with the refresh token in the Keychain. Returns false when there is
    /// no stored login, or the refresh or the login failed. The stored token stays, because
    /// the bridge cannot tell "offline" from "refused". Only `logOut` removes it.
    @discardableResult
    func restoreSession() async -> Bool {
        guard let refresh = RefreshTokenStore.read() else { return false }
        do {
            let tokens = try await LibrespotClient.oauthRefresh(refresh)
            if let newRefresh = tokens.refreshToken { RefreshTokenStore.save(newRefresh) }
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
        session += 1
        username = nil
        cache = nil
    }

    func fetchLibrary() async -> [Playlist]? {
        if let cache { return cache }
        if !isLoggedIn, !(await restoreSession()) { return nil }
        do {
            return try await readAndCache()
        } catch let error as BridgeError where error == .cancelled {
            return nil  // The account changed while it read. The reducer drops this load.
        } catch {
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
        let name = try await client.login(accessToken: token)
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

    /// Liked Songs first, then every playlist in the user's order.
    private nonisolated static func readLibrary(_ client: LibrespotClient) async throws -> [Playlist] {
        let summaries = try await client.playlists()
        var jobs: [(index: Int, uri: String?)] = [(0, nil)]
        jobs += summaries.enumerated().map { (index: $0.offset + 1, uri: $0.element.uri) }
        var tracks = [[Track]](repeating: [], count: jobs.count)
        try await withThrowingTaskGroup(of: (Int, [Track]).self) { group in
            var next = jobs.makeIterator()
            func start() {
                guard let job = next.next() else { return }
                group.addTask {
                    let result = try await client.tracks(playlistURI: job.uri)
                    return (job.index, result)
                }
            }
            for _ in 0..<maxReads { start() }
            while let done = try await group.next() {
                tracks[done.0] = done.1
                start()
            }
        }
        let liked = Playlist(id: Playlist.likedSongsID, name: "Liked Songs", tracks: tracks[0])
        let playlists = summaries.enumerated().map {
            Playlist(id: $0.element.uri, name: $0.element.name, tracks: tracks[$0.offset + 1])
        }
        return [liked] + playlists
    }
}
