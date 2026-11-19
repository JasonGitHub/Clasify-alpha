/// The `Library` that the store uses: it sends each call to the library of the active music
/// service (CLA-103), as `ServicePlayer` does for playback. One service is active at a time.
@MainActor
public final class ServiceLibrary: Library {
    private let spotify: any Library
    private let appleMusic: any Library
    /// The active service. A change sends nothing: the store logs in to the new one.
    public var service: MusicService

    public init(spotify: any Library, appleMusic: any Library, service: MusicService) {
        self.spotify = spotify
        self.appleMusic = appleMusic
        self.service = service
    }

    private var active: any Library {
        switch service {
        case .spotify: spotify
        case .appleMusic: appleMusic
        }
    }

    public var words: LibraryWords { active.words }
    /// Both libraries report to the store; only the active one reads.
    public var onProgress: (@MainActor (_ playlist: String, _ done: Int, _ total: Int, _ albums: Int) -> Void)? {
        didSet { spotify.onProgress = onProgress; appleMusic.onProgress = onProgress }
    }

    public func playlists() async -> [Playlist]? { await active.playlists() }
    public func tracks(of playlist: String) async -> [Track]? { await active.tracks(of: playlist) }
    public func rereadPlaylists() async -> [Playlist]? { await active.rereadPlaylists() }
    public func reread(_ playlist: String) async -> [Track]? { await active.reread(playlist) }
    public func track(_ id: String) async -> Track? { await active.track(id) }
    public func artists() async -> [Playlist]? { await active.artists() }
    public func prefetch() async { await active.prefetch() }
    public func logIn(page: String?) async -> LoginResult { await active.logIn(page: page) }
    public func cancelLogIn() async { await active.cancelLogIn() }
    public func restoreSession() async -> LoginResult { await active.restoreSession() }
    public func logOut() { active.logOut() }
}
