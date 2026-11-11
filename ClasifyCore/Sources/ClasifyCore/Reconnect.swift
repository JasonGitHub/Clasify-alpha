/// The wait before the next login try after a dropped session: 2, 4, 8 … up to 60 s.
public struct Backoff: Equatable, Sendable {
    public let first: Double, limit: Double
    /// Seconds to wait after the next failure.
    public private(set) var next: Double

    public init(first: Double = 2, limit: Double = 60) {
        self.first = first; self.limit = limit; next = first
    }

    /// Returns the wait for this failure, and doubles the one after it.
    public mutating func failed() -> Double {
        defer { next = min(next * 2, limit) }
        return next
    }

    public mutating func reset() { next = first }
}

/// Runs `attempt`. When it fails because the session dropped, it waits for `reconnect`
/// and runs `attempt` once more. Any other failure, or a failed reconnect, throws the first error.
@MainActor
public func retryOnce<T>(
    after reconnect: @MainActor () async -> Bool, when dropped: (any Error) -> Bool,
    _ attempt: @MainActor () async throws -> T
) async throws -> T {
    do {
        return try await attempt()
    } catch where dropped(error) {
        guard await reconnect() else { throw error }
        return try await attempt()
    }
}

/// Decides when a network change needs a new login (CLA-88). After a Wi-Fi switch, the
/// librespot session can look alive for up to about 100 s while its connections are dead.
/// A new login gives a new session with new connections. The app sends each network path
/// update here, and asks `take` after `settle` seconds.
public struct PathWatch: Equatable, Sendable {
    /// Seconds without a new update before the login, so that one switch makes one login.
    public static let settle: Double = 2

    /// The newest usable path, or nil before the first one.
    private var usable: String?
    /// No path was usable since the newest usable one.
    private var lost = false
    /// When the login is due, or nil when none is.
    public private(set) var due: Double?

    public init() {}

    /// A path update. `path` names the usable path, for example its interfaces and gateways.
    /// It is nil while no path is usable. The first usable path at launch needs no login.
    public mutating func update(_ path: String?, at now: Double) {
        guard let path else {
            lost = true
            due = nil  // wait until a path is usable again
            return
        }
        defer { usable = path; lost = false }
        guard let before = usable else { return }
        if lost || before != path || due != nil { due = now + Self.settle }
    }

    /// True once, when the login is due at `now`.
    public mutating func take(at now: Double) -> Bool {
        guard let due, now >= due else { return false }
        self.due = nil
        return true
    }
}
