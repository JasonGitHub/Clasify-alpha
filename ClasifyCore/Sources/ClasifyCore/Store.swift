import Observation

/// Playback engine (the Spotify desktop app, controlled through Spotify Connect, in 1.0). Code above it doesn't know which engine is playing.
/// The engine reports `.position`, `.trackEnded`, `.trackChanged`, `.adopted`, `.playbackFailed` and `.loadFailed` back to the store,
/// each with the generation of the newest `load`, `seek`, `next` or `prev`.
/// It reports only the state of its own device and context, so playback that the user moves elsewhere is not followed.
@MainActor
public protocol Player: AnyObject {
    /// Report `.position` and `.trackEnded` for this load with the same `generation`.
    /// `context` is the playlist ID (a Spotify URI, or `Playlist.likedSongsID`), or nil.
    func load(trackID: String, context: String?, autoplay: Bool, generation: Int)
    func pause()
    func resume()
    func stop()
    /// Skip within the playing context. Report the new track with `.trackChanged` and this `generation`.
    func next(generation: Int)
    func prev(generation: Int)
    /// The engine keeps the newest value and applies it to its own device before it plays.
    /// It may skip a value that it already applied, and it never changes another device.
    func setShuffle(_ on: Bool)
    func setRepeat(_ mode: RepeatMode)
    /// Report later `.position` and `.trackEnded` with this `generation`.
    func seek(to seconds: Double, generation: Int)
    func setVolume(_ percent: Int)
}

/// Spotify login and library source (playlists and Liked Songs).
/// It reads each part only when asked, and keeps what it read in memory for the session.
@MainActor
public protocol Library: AnyObject {
    /// The user's playlists in order, with names and track counts but no tracks.
    /// Returns nil when the read fails.
    func playlists() async -> [Playlist]?
    /// The tracks of one playlist, or of Liked Songs for `Playlist.likedSongsID`.
    /// Returns nil when the read fails.
    func tracks(of playlist: String) async -> [Track]?
    /// The details of one track ("spotify:track:<id>"). Returns nil when the read fails.
    func track(_ id: String) async -> Track?
    /// Reads Liked Songs and the playlist list in the background, at most two reads at a time,
    /// so that a later `playlists()` or `tracks(of:)` can answer at once.
    func prefetch() async
    /// Logs in through the browser. Returns false when the user cancels or the login fails.
    func logIn() async -> Bool
    /// Stops a login that waits for the browser.
    func cancelLogIn() async
    /// Logs in again with the stored login. Returns false when there is none or it fails.
    func restoreSession() async -> Bool
    /// Forgets the stored login and ends the session.
    func logOut()
}

/// Holds all app state. Only `send` changes it, and only through `reduce`.
@MainActor @Observable
public final class Store {
    public private(set) var state: AppState
    @ObservationIgnored private let player: any Player
    @ObservationIgnored private let library: any Library
    @ObservationIgnored private let env: Dependencies
    @ObservationIgnored private var fetches: [Int: Task<Void, Never>] = [:]  // in flight, by token

    public init(player: any Player, library: any Library, state: AppState = AppState(), env: Dependencies = .live) {
        self.player = player; self.library = library; self.state = state; self.env = env
    }

    /// Waits for in-flight library fetches to deliver their results. For tests.
    func settle() async {
        while let task = fetches.values.first { await task.value }
    }

    public func send(_ action: Action) {
        for effect in reduce(&state, action, env) {
            switch effect {
            case .load(let id, let context, let autoplay, let gen):
                player.load(trackID: id, context: context, autoplay: autoplay, generation: gen)
            case .pause: player.pause()
            case .resume: player.resume()
            case .stop: player.stop()
            case .next(let gen): player.next(generation: gen)
            case .prev(let gen): player.prev(generation: gen)
            case .setShuffle(let on): player.setShuffle(on)
            case .setRepeat(let mode): player.setRepeat(mode)
            case .seek(let t, let gen): player.seek(to: t, generation: gen)
            case .setVolume(let v): player.setVolume(v)
            // A stale token is ignored by the reducer.
            case .fetchPlaylists(let token):
                let library = self.library
                fetches[token] = Task { [weak self] in
                    let result = await library.playlists()
                    self?.fetches[token] = nil
                    self?.send(.playlistsLoaded(token: token, playlists: result))
                }
            case .fetchTracks(let token, let id):
                let library = self.library
                fetches[token] = Task { [weak self] in
                    let result = await library.tracks(of: id)
                    self?.fetches[token] = nil
                    self?.send(.tracksLoaded(token: token, playlist: id, tracks: result))
                }
            case .readTrack(let id):
                let library = self.library
                Task { [weak self] in
                    let track = await library.track(id)
                    self?.send(.trackRead(id, track))
                }
            case .prefetch:
                let library = self.library
                Task(priority: .utility) { await library.prefetch() }
            case .logIn(let token):
                let library = self.library
                Task { [weak self] in
                    let ok = await library.logIn()
                    self?.send(.authDone(token: token, ok: ok))
                }
            case .cancelLogIn:
                let library = self.library
                Task { await library.cancelLogIn() }
            case .restoreSession(let token):
                let library = self.library
                Task { [weak self] in
                    let ok = await library.restoreSession()
                    self?.send(.restored(token: token, ok: ok))
                }
            case .logOut: library.logOut()
            }
        }
    }
}
