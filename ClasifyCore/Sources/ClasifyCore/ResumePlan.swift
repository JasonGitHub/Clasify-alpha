/// What Play does when Clasify has no control of playback (CLA-93). The player asks this,
/// then runs the step. Plain values only, so tests need no player.
public enum ResumePlan: Equatable, Sendable {
    /// Another device plays: move playback back to this Mac.
    case takeBack(from: String)
    /// Load the song that played last, in its list, at its place. `playlist` is a playlist
    /// or album URI, or `Playlist.likedSongsID`.
    case load(track: String, playlist: String, at: Double)
    /// Load the Mac's last song at its place.
    case resumePoint
    /// Nothing to go on from: ask for a new pick.
    case pickASong

    /// For the log: the kind only, with no IDs.
    public var kind: String {
        switch self {
        case .takeBack: "take back from another device"
        case .load: "the song that played last, from the newest state"
        case .resumePoint: "the Mac's last song"
        case .pickASong: "nothing to go on from"
        }
    }

    /// The newest player state that Spotify reported, as plain values.
    public struct Seen: Equatable, Sendable {
        public var activeDevice: String, track: String, context: String
        public var position: Double, duration: Double
        public var running: Bool, hasTrack: Bool
        /// Seconds since the state came.
        public var age: Double

        public init(activeDevice: String, track: String, context: String, position: Double, duration: Double,
                    running: Bool, hasTrack: Bool, age: Double) {
            self.activeDevice = activeDevice; self.track = track; self.context = context
            self.position = position; self.duration = duration
            self.running = running; self.hasTrack = hasTrack; self.age = age
        }

        /// The place now: a running song moved on since the state came. Past the end of a known
        /// length, the song starts at 0.
        public var place: Double {
            let place = max(0, position + (running ? age : 0))
            return duration > 0 && place >= duration ? 0 : place
        }
    }

    /// A context that the bridge can load again: Liked Songs, a playlist, an album, or an artist.
    public static func canLoad(_ context: String) -> Bool {
        context.hasSuffix(":collection") || context.hasPrefix("spotify:playlist:") || Album.isID(context)
            || context.hasPrefix("spotify:artist:")  // CLA-195: a song from Artists
    }

    /// Picks the step, in order: take back, the song that played last elsewhere, the Mac's
    /// last song, a new pick. `device` is the Spotify app on this Mac. `movedAway` is true
    /// after the user moved playback to another device. Only then does the newest state
    /// come from elsewhere; after a quit or a stop, the Mac's own place is newer.
    public static func pick(device: String?, movedAway: Bool, seen: Seen?, hasResumePoint: Bool) -> ResumePlan {
        if movedAway, let device, let seen, !seen.activeDevice.isEmpty, seen.activeDevice != device {
            return .takeBack(from: seen.activeDevice)
        }
        if movedAway, let seen, seen.hasTrack, !seen.track.isEmpty, canLoad(seen.context) {
            let playlist = seen.context.hasSuffix(":collection") ? Playlist.likedSongsID : seen.context
            return .load(track: seen.track, playlist: playlist, at: seen.place)
        }
        return hasResumePoint ? .resumePoint : .pickASong
    }
}
