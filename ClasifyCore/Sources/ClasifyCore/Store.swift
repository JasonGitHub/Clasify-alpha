import Observation

/// Playback engine (librespot in 1.0). Code above it doesn't know which engine is playing.
@MainActor
public protocol Player: AnyObject {
    /// Report `.position` and `.trackEnded` for this load with the same `generation`.
    func load(trackID: String, autoplay: Bool, generation: Int)
    func pause()
    func resume()
    func stop()
    /// Report later `.position` and `.trackEnded` with this `generation`.
    func seek(to seconds: Double, generation: Int)
    func setVolume(_ percent: Int)
}

/// Spotify library source (playlists and Liked Songs). Returns nil when the fetch fails.
@MainActor
public protocol Library: AnyObject {
    func fetchLibrary() async -> [Playlist]?
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

    /// Waits for in-flight library fetches to deliver `.loaded`. For tests.
    func settle() async {
        while let task = fetches.values.first { await task.value }
    }

    public func send(_ action: Action) {
        for effect in reduce(&state, action, env) {
            switch effect {
            case .load(let id, let autoplay, let gen): player.load(trackID: id, autoplay: autoplay, generation: gen)
            case .pause: player.pause()
            case .resume: player.resume()
            case .stop: player.stop()
            case .seek(let t, let gen): player.seek(to: t, generation: gen)
            case .setVolume(let v): player.setVolume(v)
            case .fetchLibrary(let token):
                let library = self.library
                fetches[token] = Task { [weak self] in
                    let result = await library.fetchLibrary()
                    self?.fetches[token] = nil
                    self?.send(.loaded(token: token, library: result))  // a stale token is ignored by the reducer
                }
            }
        }
    }
}
