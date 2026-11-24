/// CLA-179: what the Mac's media keys and Now Playing show for local songs. `LocalSystemControls`
/// (in the app) only applies it. It follows `LocalPlayback`'s commands, and counts only while
/// Local is the active service: then the keys belong to myPod, else to other apps.
public struct LocalNowPlaying: Equatable, Sendable {
    /// A media key or a Now Playing control. Other controls stay off.
    public enum Command: CaseIterable, Sendable { case play, pause, toggle, next, previous }

    public enum State: Sendable { case stopped, playing, paused }

    /// Local is the active service (`Player.setActive`).
    public var active = false
    /// The song on screen, while the audio holds it.
    public private(set) var song: String?
    public private(set) var playing = false

    public init() {}

    public var state: State {
        guard active, song != nil else { return .stopped }
        return playing ? .playing : .paused
    }

    /// Follows one command of `LocalPlayback`.
    public mutating func apply(_ command: LocalPlayback.Command) {
        switch command {
        case .start(_, _, let play): playing = play
        case .play: playing = true
        case .pause: playing = false
        case .stopAudio: (song, playing) = (nil, false)
        case .report(.trackChanged(let id, _, _)): song = id
        default: break
        }
    }

    /// The input action for a key, the same as the skin's button: `.play` toggles, so Play
    /// while playing and Pause while paused do nothing.
    public static func action(for command: Command, playing: Bool) -> Action? {
        switch command {
        case .play: playing ? nil : .play
        case .pause: playing ? .play : nil
        case .toggle: .play
        case .next: .next
        case .previous: .prev
        }
    }
}
