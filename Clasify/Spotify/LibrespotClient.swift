import ClasifyCore
import Foundation
import LibrespotBridge
import os

/// A failed bridge call. `message` never holds a token.
struct BridgeError: Error, Sendable, Equatable {
    let status: Int32
    let message: String

    static let cancelled = BridgeError(status: -1, message: "cancelled")
    static let keychain = BridgeError(status: -2, message: "cannot keep the login in the Keychain")
    static let noRefreshToken = BridgeError(status: -3, message: "Spotify sent no refresh token")
    static let timedOut = BridgeError(status: -4, message: "login timed out")
}

/// The login that waits for LOGGED_IN or ERROR. `id` tells a timeout which login it is for.
struct PendingLogin: Sendable {
    /// Also goes to `lsb_login`, which echoes it in the event, so a late event of an older login is ignored.
    var id: UInt64 = 0
    var continuation: CheckedContinuation<String, any Error>?

    /// Takes the continuation, so that only one caller resumes it.
    mutating func take() -> CheckedContinuation<String, any Error>? {
        defer { continuation = nil }
        return continuation
    }
}

/// Tokens from OAuth. Keep the access token in memory only. Only the refresh token
/// goes into the Keychain.
struct OAuthTokens: Sendable {
    let accessToken: String
    /// nil when Spotify keeps the old refresh token.
    let refreshToken: String?
    let expiresIn: TimeInterval
}

/// One playlist in the user's list, without its tracks.
struct PlaylistSummary: Sendable, Equatable {
    let uri: String
    let name: String
    let trackCount: Int
}

/// Swift wrapper over the librespot bridge: login, library reads, and Spotify Connect
/// commands (in LibrespotClient+Connect.swift).
/// The app keeps one for its lifetime and never calls `lsb_free`, so callbacks
/// can never come after the bridge is gone.
///
/// `@unchecked Sendable` is safe here: `handle` never changes after `init`, the
/// bridge's C functions may be called from any thread (the Rust side locks its
/// own state), and `pendingLogin` is guarded by its lock.
final class LibrespotClient: @unchecked Sendable {
    let handle: OpaquePointer
    private let pendingLogin: OSAllocatedUnfairLock<PendingLogin>
    /// Gets each Spotify player state. It lives as long as the app, like the bridge.
    let stateBox = StateBox()

    /// A login with no answer by then fails. LibrespotLibrary runs logins one at a time,
    /// so one login that never answers would block every later login.
    static let loginTimeout = Duration.seconds(30)

    init?() {
        let pending = OSAllocatedUnfairLock(initialState: PendingLogin())
        let box = Unmanaged.passRetained(EventBox(pendingLogin: pending)).toOpaque()
        guard let handle = lsb_new(eventCallback, box) else {
            Unmanaged<EventBox>.fromOpaque(box).release()
            return nil
        }
        self.handle = handle
        self.pendingLogin = pending
        // The box is never released, because the bridge is never freed.
        lsb_connect_watch(handle, stateCallback, Unmanaged.passRetained(stateBox).toOpaque())
    }

    /// Starts a librespot session with an access token. Returns the canonical username.
    /// A newer login or `logout` supersedes this one, which then throws `BridgeError.cancelled`.
    /// It throws `BridgeError.timedOut` after `loginTimeout`.
    func login(accessToken: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let (id, older) = pendingLogin.withLock { pending in
                let older = pending.take()
                pending.id += 1
                pending.continuation = continuation
                return (pending.id, older)
            }
            older?.resume(throwing: BridgeError.cancelled)
            let status = lsb_login(handle, accessToken, id)
            if status != LSB_OK {
                finishLogin(id, throwing: BridgeError(status: status, message: "login did not start"))
                return
            }
            Task.detached { [self] in
                try? await Task.sleep(for: Self.loginTimeout)
                let mine = pendingLogin.withLock { pending -> CheckedContinuation<String, any Error>? in
                    guard pending.id == id, let waiting = pending.take() else { return nil }
                    // Stop the bridge login too, so that it cannot publish a session later. This runs
                    // under the lock, so a newer login cannot start before it and be stopped by it.
                    lsb_logout(self.handle)
                    return waiting
                }
                mine?.resume(throwing: BridgeError.timedOut)
            }
        }
    }

    /// Fails login `id` if it still waits.
    private func finishLogin(_ id: UInt64, throwing error: BridgeError) {
        pendingLogin.withLock { pending in pending.id == id ? pending.take() : nil }?.resume(throwing: error)
    }

    /// False when there is no session or it dropped, for example after sleep or a network
    /// change. librespot does not reconnect by itself. A cheap check.
    var sessionAlive: Bool { lsb_session_status(handle) == LSB_OK }

    /// Ends the bridge session. A login that still waits throws `BridgeError.cancelled`.
    func logout() {
        pendingLogin.withLock { $0.take() }?.resume(throwing: BridgeError.cancelled)
        lsb_logout(handle)
    }

    /// The playlists in the user's list, in order.
    func playlists() async throws -> [PlaylistSummary] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[PlaylistSummary], any Error>) in
            let box = Unmanaged.passRetained(ResultBox(continuation)).toOpaque()
            let status = lsb_read_playlists(handle, playlistsCallback, box)
            if status != LSB_OK {
                Unmanaged<ResultBox<[PlaylistSummary]>>.fromOpaque(box).takeRetainedValue()
                    .resume(.failure(BridgeError(status: status, message: "cannot read playlists")))
            }
        }
    }

    /// All tracks of a playlist, or of Liked Songs when `playlistURI` is nil.
    /// `progress` gets how many of the list's items have their details, and how many there
    /// are, on a bridge thread, before the result (CLA-55).
    func tracks(playlistURI: String?, progress: @escaping @Sendable (Int, Int, Int) -> Void) async throws -> [Track] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[Track], any Error>) in
            let box = Unmanaged.passRetained(TracksBox(ResultBox(continuation), progress: progress)).toOpaque()
            let status: Int32
            if let playlistURI {
                status = lsb_read_tracks_progress(handle, playlistURI, tracksProgress, tracksBoxCallback, box)
            } else {
                status = lsb_read_tracks_progress(handle, nil, tracksProgress, tracksBoxCallback, box)
            }
            if status != LSB_OK {
                Unmanaged<TracksBox>.fromOpaque(box).takeRetainedValue().result
                    .resume(.failure(BridgeError(status: status, message: "cannot read tracks")))
            }
        }
    }

    /// The details of one track, or nil when Spotify has none for it.
    func track(uri: String) async throws -> Track? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[Track], any Error>) in
            let box = Unmanaged.passRetained(ResultBox(continuation)).toOpaque()
            let status = lsb_read_track(handle, uri, tracksCallback, box)
            if status != LSB_OK {
                Unmanaged<ResultBox<[Track]>>.fromOpaque(box).takeRetainedValue()
                    .resume(.failure(BridgeError(status: status, message: "cannot read a track")))
            }
        }.first
    }

    /// Opens the Spotify login page in the browser and waits for the redirect.
    /// The bridge call can block while an older login stops, so it runs off the main actor.
    /// `next` is nil, or the activate page that the page after the login opens (CLA-143).
    static func oauthLogin(next: String?) async throws -> OAuthTokens {
        try await withCheckedThrowingContinuation { continuation in
            // A raw pointer is not Sendable, so it crosses into the task as an address.
            let address = UInt(bitPattern: Unmanaged.passRetained(ResultBox(continuation)).toOpaque())
            Task.detached {
                let box = UnsafeMutableRawPointer(bitPattern: address)!
                // The bridge copies `next` before it returns.
                let status = next.map { $0.withCString { lsb_oauth_login(tokenCallback, box, $0) } } ?? lsb_oauth_login(tokenCallback, box, nil)
                if status != LSB_OK {
                    Unmanaged<ResultBox<OAuthTokens>>.fromOpaque(box).takeRetainedValue()
                        .resume(.failure(BridgeError(status: status, message: "login did not start")))
                }
            }
        }
    }

    /// Stops a waiting `oauthLogin`, which then throws.
    static func oauthCancel() async {
        await Task.detached { _ = lsb_oauth_cancel() }.value
    }

    /// Gets a new access token for a refresh token.
    static func oauthRefresh(_ refreshToken: String) async throws -> OAuthTokens {
        try await withCheckedThrowingContinuation { continuation in
            let box = Unmanaged.passRetained(ResultBox(continuation)).toOpaque()
            let status = lsb_oauth_refresh(refreshToken, tokenCallback, box)
            if status != LSB_OK {
                Unmanaged<ResultBox<OAuthTokens>>.fromOpaque(box).takeRetainedValue()
                    .resume(.failure(BridgeError(status: status, message: "refresh did not start")))
            }
        }
    }
}

// MARK: - C callbacks

// The C callbacks are global functions, so they are nonisolated. They run on bridge
// threads. A closure formed inside a @MainActor type would be main-actor isolated,
// and Swift 6 traps when it runs on another thread.

/// Holds one continuation for a C callback that comes exactly once.
final class ResultBox<Value: Sendable>: Sendable {
    private let continuation: CheckedContinuation<Value, any Error>

    init(_ continuation: CheckedContinuation<Value, any Error>) { self.continuation = continuation }

    func resume(_ result: Result<Value, BridgeError>) { continuation.resume(with: result.mapError { $0 as any Error }) }
}

/// A track read's result and its progress, behind one context pointer. The bridge calls the
/// progress only before the result, which releases the box.
final class TracksBox: Sendable {
    let result: ResultBox<[Track]>
    /// Done, total, and the albums of the tracks so far.
    let progress: @Sendable (Int, Int, Int) -> Void

    init(_ result: ResultBox<[Track]>, progress: @escaping @Sendable (Int, Int, Int) -> Void) {
        self.result = result
        self.progress = progress
    }
}

/// The bridge's event context. It lives as long as the app.
private final class EventBox: Sendable {
    let pendingLogin: OSAllocatedUnfairLock<PendingLogin>

    init(pendingLogin: OSAllocatedUnfairLock<PendingLogin>) {
        self.pendingLogin = pendingLogin
    }
}

func string(_ text: UnsafePointer<CChar>?) -> String? {
    text.map { String(cString: $0) }
}

private func eventCallback(_ context: UnsafeMutableRawPointer?, _ event: UnsafePointer<LsbEvent>?) {
    guard let context, let event else { return }
    let box = Unmanaged<EventBox>.fromOpaque(context).takeUnretainedValue()
    let raw = event.pointee
    let result: Result<String, BridgeError>
    switch Int32(raw.kind) {
    case LSB_EVENT_LOGGED_IN: result = .success(string(raw.message) ?? "")
    case LSB_EVENT_ERROR: result = .failure(BridgeError(status: LSB_ERR_NOT_LOGGED_IN, message: string(raw.message) ?? "login failed"))
    case LSB_EVENT_NOT_PREMIUM: result = .failure(BridgeError(status: LSB_ERR_NOT_PREMIUM, message: "not Spotify Premium"))
    default: return
    }
    let loginID = raw.login_id
    let pending = box.pendingLogin.withLock { pending in pending.id == loginID ? pending.take() : nil }
    pending?.resume(with: result.mapError { $0 as any Error })
}

private func failure(_ status: Int32, _ message: UnsafePointer<CChar>?) -> BridgeError {
    BridgeError(status: status, message: string(message) ?? "read failed")
}

private func playlistsCallback(
    _ context: UnsafeMutableRawPointer?, _ status: Int32, _ message: UnsafePointer<CChar>?,
    _ items: UnsafePointer<LsbPlaylist>?, _ count: Int
) {
    guard let context else { return }
    let box = Unmanaged<ResultBox<[PlaylistSummary]>>.fromOpaque(context).takeRetainedValue()
    guard status == LSB_OK else { return box.resume(.failure(failure(status, message))) }
    let playlists = UnsafeBufferPointer(start: items, count: items == nil ? 0 : count).map {
        PlaylistSummary(uri: string($0.uri) ?? "", name: string($0.name) ?? "", trackCount: Int($0.track_count))
    }
    box.resume(.success(playlists))
}

private func tracksCallback(
    _ context: UnsafeMutableRawPointer?, _ status: Int32, _ message: UnsafePointer<CChar>?,
    _ items: UnsafePointer<LsbTrack>?, _ count: Int
) {
    guard let context else { return }
    let box = Unmanaged<ResultBox<[Track]>>.fromOpaque(context).takeRetainedValue()
    box.resume(trackResult(status, message, items, count))
}

private func tracksProgress(_ context: UnsafeMutableRawPointer?, _ done: Int, _ total: Int, _ albums: Int) {
    guard let context else { return }
    Unmanaged<TracksBox>.fromOpaque(context).takeUnretainedValue().progress(done, total, albums)
}

private func tracksBoxCallback(
    _ context: UnsafeMutableRawPointer?, _ status: Int32, _ message: UnsafePointer<CChar>?,
    _ items: UnsafePointer<LsbTrack>?, _ count: Int
) {
    guard let context else { return }
    let box = Unmanaged<TracksBox>.fromOpaque(context).takeRetainedValue()
    box.result.resume(trackResult(status, message, items, count))
}

private func trackResult(
    _ status: Int32, _ message: UnsafePointer<CChar>?, _ items: UnsafePointer<LsbTrack>?, _ count: Int
) -> Result<[Track], BridgeError> {
    guard status == LSB_OK else { return .failure(failure(status, message)) }
    let tracks = UnsafeBufferPointer(start: items, count: items == nil ? 0 : count).map {
        Track(
            id: string($0.uri) ?? "", title: string($0.title) ?? "", artist: string($0.artist) ?? "",
            duration: Double($0.duration_ms) / 1000, coverID: string($0.cover_id),
            album: Album.from(id: string($0.album_uri), name: string($0.album_name), artist: string($0.album_artist)),
            disc: Int($0.disc_number), number: Int($0.track_number), largeCoverID: string($0.large_cover_id),
            artists: ArtistRef.list(uris: string($0.artist_uris), names: string($0.artist_names)))  // CLA-195
    }
    return .success(tracks)
}

private func tokenCallback(_ context: UnsafeMutableRawPointer?, _ result: UnsafePointer<LsbToken>?) {
    guard let context, let result else { return }
    let box = Unmanaged<ResultBox<OAuthTokens>>.fromOpaque(context).takeRetainedValue()
    let raw = result.pointee
    guard raw.status == LSB_OK, let access = string(raw.access_token) else {
        return box.resume(.failure(BridgeError(status: raw.status, message: string(raw.message) ?? "login failed")))
    }
    box.resume(.success(OAuthTokens(
        accessToken: access, refreshToken: string(raw.refresh_token), expiresIn: TimeInterval(raw.expires_in_s))))
}
