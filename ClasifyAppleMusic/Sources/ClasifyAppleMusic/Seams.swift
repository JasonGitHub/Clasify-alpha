/// Covers of Apple Music library songs that MusicKit gives no usable cover (macOS 27, build 191).
/// The Mac app reads them from Apple's iTunesLibrary framework (`AppleMusicArt`). A platform
/// with no such source uses `NoLibraryCovers`.
public protocol LibraryCovers: Sendable {
    /// For each song (its MusicKit ID and `LibraryKey`), the persistent ID of a library item
    /// that has a cover, by the song's MusicKit ID. Songs with none are left out.
    func covers(_ songs: [(id: String, key: String)]) async -> [String: UInt64]
    /// Drops what was read, so that the next read sees the library as it is now.
    func forget() async
}

/// No library covers: songs keep their MusicKit cover, or none.
public struct NoLibraryCovers: LibraryCovers {
    public init() {}
    public func covers(_ songs: [(id: String, key: String)]) async -> [String: UInt64] { [:] }
    public func forget() async {}
}

/// The device's output volume, for a player with no volume of its own (MusicKit's
/// `ApplicationMusicPlayer` on the Mac). The Mac app fills it with `MacVolume` (Core Audio).
/// A platform without it gives nil, and the player then sets no volume.
@MainActor public protocol OutputVolume: AnyObject {
    /// Gets the volume in percent after each change, while it listens.
    var onChange: (Int) -> Void { get set }
    /// Starts to listen, and reports the volume now.
    func start()
    /// Stops listening. Nothing is reported after this.
    func stop()
    /// The volume in percent, or nil when there is none.
    func read() -> Int?
    /// Sets the volume in percent, if the device takes it.
    func write(_ percent: Int)
}
