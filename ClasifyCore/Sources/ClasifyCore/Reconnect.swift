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
    after reconnect: () async -> Bool, when dropped: (any Error) -> Bool, _ attempt: () async throws -> T
) async throws -> T {
    do {
        return try await attempt()
    } catch where dropped(error) {
        guard await reconnect() else { throw error }
        return try await attempt()
    }
}
