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

/// How a login ended.
public enum LoginResult: Equatable, Sendable {
    case ok, failed
    /// The login worked, but the account is not Spotify Premium, so it ended (CLA-66).
    case notPremium
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
    /// The playlist list or one playlist's tracks, read again past any cached read.
    /// Returns nil when the read fails.
    func rereadPlaylists() async -> [Playlist]?
    func reread(_ playlist: String) async -> [Track]?
    /// The details of one track ("spotify:track:<id>"). Returns nil when the read fails.
    func track(_ id: String) async -> Track?
    /// Reads Liked Songs and the playlist list in the background, at most two reads at a time,
    /// so that a later `playlists()` or `tracks(of:)` can answer at once.
    func prefetch() async
    /// Logs in through the browser: `.failed` when the user cancels or the login fails.
    func logIn() async -> LoginResult
    /// Stops a login that waits for the browser.
    func cancelLogIn() async
    /// Logs in again with the stored login: `.failed` when there is none or it fails.
    func restoreSession() async -> LoginResult
    /// Forgets the stored login and ends the session.
    func logOut()
    /// Called on the main actor while a track read runs: how many of the list's items have
    /// their details, and how many there are. The store sets it.
    var onProgress: (@MainActor (_ playlist: String, _ done: Int, _ total: Int) -> Void)? { get set }
}

/// Holds all app state. Only `send` changes it, and only through `reduce`.
@MainActor @Observable
public final class Store {
    public private(set) var state: AppState
    @ObservationIgnored private let player: any Player
    @ObservationIgnored private let library: any Library
    @ObservationIgnored private let env: Dependencies
    @ObservationIgnored private var fetches: [Int: Task<Void, Never>] = [:]  // in flight, by token
    /// Called after each `.wheel` step that moved something (see `wheelMoved`). The app clicks
    /// and ticks the trackpad here.
    @ObservationIgnored public var onWheelStep: (@MainActor () -> Void)?
    /// Opens the Spotify app's download page in the browser (card BB). The app sets it.
    @ObservationIgnored public var onGetSpotifyApp: (@MainActor () -> Void)?
    /// Opens Spotify's Premium page in the browser (card AX, screen 135). The app sets it.
    @ObservationIgnored public var onGetPremium: (@MainActor () -> Void)?
    /// Where the settings are saved. When set, `init` loads them into the state.
    @ObservationIgnored private let settingsStore: (any SettingsStore)?

    public init(
        player: any Player, library: any Library, state: AppState = AppState(), env: Dependencies = .live,
        settings: (any SettingsStore)? = nil
    ) {
        self.player = player; self.library = library; self.state = state; self.env = env
        settingsStore = settings
        library.onProgress = { [weak self] playlist, done, total in
            self?.send(.readProgress(playlist, done: done, total: total))
        }
        if let settings {
            self.state.settings = Settings(from: settings)
            // The player keeps its own shuffle and repeat for when it takes over playback later.
            player.setShuffle(self.state.shuffle)
            player.setRepeat(self.state.repeatMode)
        }
    }

    /// Waits for in-flight library fetches to deliver their results. For tests.
    func settle() async {
        while let task = fetches.values.first { await task.value }
    }

    public func send(_ action: Action) {
        let before = state
        let effects = reduce(&state, action, env)
        if let settingsStore, state.settings != before.settings { state.settings.save(to: settingsStore) }
        if case .wheel = action, wheelMoved(from: before, to: state) { onWheelStep?() }
        for effect in effects {
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
            case .refreshPlaylists:
                let library = self.library
                Task(priority: .utility) { [weak self] in
                    let result = await library.rereadPlaylists()
                    self?.send(.playlistsRefreshed(result))
                }
            case .refreshTracks(let id):
                let library = self.library
                Task(priority: .utility) { [weak self] in
                    let result = await library.reread(id)
                    self?.send(.tracksRefreshed(playlist: id, tracks: result))
                }
            case .readArtTracks(let token, let id):
                let library = self.library
                Task(priority: .utility) { [weak self] in
                    let result = await library.tracks(of: id)
                    self?.send(.artTracksRead(token: token, playlist: id, tracks: result))
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
                    let result = await library.logIn()
                    self?.send(result == .notPremium ? .notPremium(token: token) : .authDone(token: token, ok: result == .ok))
                }
            case .getSpotifyApp: onGetSpotifyApp?()
            case .getPremium: onGetPremium?()
            case .cancelLogIn:
                let library = self.library
                Task { await library.cancelLogIn() }
            case .restoreSession(let token):
                let library = self.library
                Task { [weak self] in
                    let result = await library.restoreSession()
                    self?.send(result == .notPremium ? .notPremium(token: token) : .restored(token: token, ok: result == .ok))
                }
            case .logOut: library.logOut()
            }
        }
    }
}
