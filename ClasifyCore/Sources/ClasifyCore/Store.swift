import Observation

/// Playback engine (librespot in 1.0). Code above it doesn't know which engine is playing.
@MainActor
public protocol Player: AnyObject {
    func load(trackID: String, autoplay: Bool)
    func pause()
    func resume()
    func stop()
    func seek(to seconds: Double)
    func setVolume(_ percent: Int)
}

/// Holds all app state. Only `send` changes it, and only through `reduce`.
@MainActor @Observable
public final class Store {
    public private(set) var state: AppState
    @ObservationIgnored private let player: any Player
    @ObservationIgnored private let env: Dependencies

    public init(player: any Player, state: AppState = AppState(), env: Dependencies = .live) {
        self.player = player; self.state = state; self.env = env
    }

    public func send(_ action: Action) {
        for effect in reduce(&state, action, env) {
            switch effect {
            case .load(let id, let autoplay): player.load(trackID: id, autoplay: autoplay)
            case .pause: player.pause()
            case .resume: player.resume()
            case .stop: player.stop()
            case .seek(let t): player.seek(to: t)
            case .setVolume(let v): player.setVolume(v)
            }
        }
    }
}
