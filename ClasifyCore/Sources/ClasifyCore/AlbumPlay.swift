/// How the engine plays a song of an album, which the Albums screen opens from Liked Songs.
/// First as a plain list of the album's liked songs, so that only they play. If Spotify
/// refuses that list, as the whole album, from the song (Round 9, CLA-36). The engine logs
/// which path played, so a test on a Mac shows which one Spotify takes.
public enum AlbumPlay {
    public enum Path: String, Sendable { case trackList = "track list", albumContext = "album context" }

    /// The most songs in one list. The bridge takes up to this many.
    public static let maxTracks = 500

    /// The album's liked songs in play order, as track URIs, or nil when there is no list to
    /// try: `track` is not among them, or there are too many.
    public static func trackList(album: String, track: String, liked: [Track]) -> [String]? {
        let ids = Album.songs(album, in: liked).map(\.id)
        guard ids.contains(track), ids.count <= maxTracks else { return nil }
        return ids
    }

    /// Runs `trackList` when there is a list, else or when it throws, `albumContext`.
    /// Returns the path that played. Throws the album context's error when both fail.
    /// Returns nil with no fallback when the list failed and `stillWanted` is false: a newer
    /// load came while the list was refused, so the album must not replace it.
    /// It runs on the caller's actor, so the steps can use the caller's state.
    public static func run(
        hasList: Bool, trackList: () async throws -> Void, albumContext: () async throws -> Void,
        trackListFailed: (any Error) -> Void = { _ in }, stillWanted: () -> Bool = { true },
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> Path? {
        if hasList {
            do {
                try await trackList()
                return .trackList
            } catch {
                trackListFailed(error)
                guard stillWanted() else { return nil }
            }
        }
        try await albumContext()
        return .albumContext
    }
}
