/// CLA-179: what the Mac's media keys and Now Playing show for local songs. `LocalSystemControls`
/// (in the app) only applies it. It follows `LocalPlayback`'s commands, and counts only while
/// Local is the active service: then the keys belong to myPod, else to other apps.
public struct LocalNowPlaying: Equatable, Sendable {
    /// A media key or a Now Playing control. Other controls stay off.
    public enum Command: CaseIterable, Sendable { case play, pause, toggle, next, previous }

    public enum State: Sendable { case stopped, playing, paused }

    /// What the Now Playing panel shows. The Mac moves the time on from `elapsed` at `rate`.
    public struct Info: Equatable, Sendable {
        public var title: String, artist: String?, album: String?
        /// Seconds. nil when the library gives no length.
        public var duration: Double?
        public var elapsed: Double
        /// 1 while playing, 0 while paused.
        public var rate: Double
    }

    /// Local is the active service (`Player.setActive`).
    public var active = false
    /// The song on screen. After the end of a list it stays, paused, until a stop.
    public private(set) var song: LocalItem?
    public private(set) var playing = false
    /// Seconds into the song when it last started, paused, played or moved.
    public private(set) var elapsed: Double = 0
    /// Counts the times `elapsed` was set. A new time goes to the Mac even when it equals the
    /// last one (Codex on #447: Repeat One starts the same song at 0 again; a seek back).
    public private(set) var anchors = 0

    public init() {}

    public var state: State {
        guard active, song != nil else { return .stopped }
        return playing ? .playing : .paused
    }

    public var info: Info? {
        guard state != .stopped, let song else { return nil }
        let title = song.title.isEmpty ? song.url.deletingPathExtension().lastPathComponent : song.title
        return Info(
            title: title, artist: song.artist.isEmpty ? nil : song.artist, album: song.album.isEmpty ? nil : song.album,
            duration: song.duration > 0 ? song.duration : nil, elapsed: elapsed, rate: playing ? 1 : 0)
    }

    /// Follows the commands of one `LocalPlayback.handle`. `playback` is its state after that
    /// call; `time` is where the audio is now, in seconds (for Play and Pause).
    public mutating func follow(_ commands: [LocalPlayback.Command], of playback: LocalPlayback, time: Double) {
        var failed = false, changed = false
        for command in commands {
            switch command {
            case .start, .adoptNext, .play, .pause, .seek, .stopAudio: anchors &+= 1
            default: break
            }
            switch command {
            case .start(_, let seek, let play): (playing, elapsed) = (play, seek ?? 0)
            case .adoptNext: elapsed = 0
            case .play: (playing, elapsed) = (true, time)
            case .pause: (playing, elapsed) = (false, time)
            case .seek(let seconds): elapsed = seconds
            // The audio is off: the song on screen rests, paused at its start (Play starts it again).
            case .stopAudio: (playing, elapsed) = (false, 0)
            case .report(.trackChanged(let id, _, _)):
                song = playback.now?.items.first { $0.id == id }
                changed = true
            case .report(.playbackFailed): failed = true
            default: break
            }
        }
        // Codex on #447: no song opened (a new load whose files all failed): rest on the song that
        // Play tries again, not on the one from before.
        if failed && !changed { song = playback.now?.song }
        if playback.now == nil { song = nil }  // a stop: nothing on screen
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
