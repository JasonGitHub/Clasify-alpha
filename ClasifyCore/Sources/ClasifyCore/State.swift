public struct Track: Equatable, Sendable {
    public var id: String  // Spotify URI
    public var title: String
    public var artist: String
    public var duration: Double  // seconds
    /// The album cover's Spotify image file ID (hex), or nil when the track has none.
    public var coverID: String?

    public init(id: String, title: String, artist: String, duration: Double, coverID: String? = nil) {
        self.id = id; self.title = title; self.artist = artist; self.duration = duration
        self.coverID = coverID.flatMap { $0.isEmpty ? nil : $0 }
    }
}

public struct Playlist: Equatable, Sendable {
    /// Spotify URI. Liked Songs uses `Playlist.likedSongsID`.
    public var id: String
    public var name: String
    /// Empty until the tracks are read. `AppState.loadedTracks` says which playlists are read.
    public var tracks: [Track]
    /// From the playlist list, so it is known before the tracks are read.
    public var trackCount: Int

    public static let likedSongsID = "liked"

    public init(id: String, name: String, tracks: [Track], trackCount: Int? = nil) {
        self.id = id; self.name = name; self.tracks = tracks; self.trackCount = trackCount ?? tracks.count
    }
}

public enum Screen: Equatable, Sendable {
    case login, auth, main, playlists, tracks(playlist: String), settings, confirm, about, now

    /// Screens that show a scrollable list the wheel moves through.
    public var isList: Bool {
        switch self {
        case .login, .main, .playlists, .tracks, .settings, .confirm: true
        case .auth, .about, .now: false
        }
    }
}

/// One entry on the navigation stack.
public struct Frame: Equatable, Sendable {
    public var screen: Screen
    public var sel = 0, off = 0
    public var loading = false, error = false
    public var token = 0

    public init(screen: Screen, loading: Bool = false, token: Int = 0) {
        self.screen = screen; self.loading = loading; self.token = token
    }
}

/// A selectable list row. Skins map rows to labels and values.
public enum Row: Equatable, Sendable {
    case logIn, nowPlaying, playlists, likedSongs, shuffleSongs, settings
    case playlist(String), track(String)
    case shuffle, repeatMode, skin, albumArt, clicker, about, logOut
    case cancel, confirmLogOut
}

/// The playing track, by ID, so a library reload that reorders things can't point it elsewhere.
public struct TrackRef: Equatable, Sendable {
    public var playlist: String, track: String
    public init(playlist: String, track: String) { self.playlist = playlist; self.track = track }
}

/// What the wheel changes on Now Playing. A center press steps through them in this order.
public enum NowMode: CaseIterable, Sendable { case volume, scrub, shuffle, repeatMode }
public enum RepeatMode: String, CaseIterable, Sendable {
    case off = "Off", all = "All", one = "One"

    /// The repeat slider on Now Playing, from left to right.
    public static let sliderOrder: [RepeatMode] = [.off, .one, .all]
}
public enum Skin: String, CaseIterable, Sendable { case pocket = "Pocket", aqua = "Aqua", dark = "Dark" }

extension CaseIterable where Self: Equatable {
    var next: Self {
        let all = Array(Self.allCases)
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

public struct AppState: Equatable, Sendable {
    public var stack = [Frame(screen: .login)]
    public var tok = 0
    /// Bumped on every track load; engine callbacks echo it back.
    public var playGen = 0
    /// Bumped on every login attempt; `.authDone` echoes it back.
    public var authAttempt = 0
    /// Token of a Liked Songs load that should start a shuffle when it finishes.
    public var shuffleToken: Int?
    public var signedIn = false
    /// A restore of the stored login runs. The login screen offers no Log in row meanwhile,
    /// so a browser login cannot race it. Skins show "Signing in…".
    public var restoring = false
    /// Liked Songs (once read) first, then the playlists. Each part loads when its screen opens.
    public var library: [Playlist] = []
    /// The playlist list was read in this session.
    public var playlistsLoaded = false
    /// The playlists (and `Playlist.likedSongsID`) whose tracks were read in this session.
    public var loadedTracks: Set<String> = []
    public var current: TrackRef?
    public var t: Double = 0
    public var isPlaying = false
    public var volume = 60
    public var shuffle = false
    public var repeatMode = RepeatMode.off
    public var skin = Skin.pocket
    public var showArt = true
    public var clicker = true
    public var nowMode = NowMode.volume
    /// When the volume bar hides, or when a scrub, shuffle or repeat slider goes back to the
    /// progress bar. 0 when nothing is timed.
    public var overlayUntil: Double = 0
    /// Quick wheel steps on a list move more rows.
    public var wheelSpeed = WheelSpeed()
    public var toast = ""
    public var toastUntil: Double = 0
    public var offline = false

    public init() {}

    public var top: Frame {
        get { stack[stack.count - 1] }
        set { stack[stack.count - 1] = newValue }
    }

    /// The bar for the playing track shows under every screen but Now Playing and the login wait.
    public var showsBar: Bool {
        guard current != nil else { return false }
        switch top.screen {
        case .now, .auth: return false
        default: return true
        }
    }

    /// The list rows that show at once: `visibleRows`, or `trackRows` for the taller two-line
    /// song rows, and one less while the bar shows.
    public var shownRows: Int {
        var rows = visibleRows
        if case .tracks = top.screen { rows = trackRows }
        return showsBar ? rows - 1 : rows
    }

    /// The screen's list is already in the state, so it opens without a read.
    public func isLoaded(_ screen: Screen) -> Bool {
        switch screen {
        case .playlists: playlistsLoaded
        case .tracks(let id): loadedTracks.contains(id)
        default: true
        }
    }

    public func tracks(in playlist: String) -> [Track] {
        library.first { $0.id == playlist }?.tracks ?? []
    }

    public func track(_ ref: TrackRef) -> Track? {
        tracks(in: ref.playlist).first { $0.id == ref.track }
    }

    public func rows(for frame: Frame) -> [Row] {
        switch frame.screen {
        case .login: restoring ? [] : [.logIn]
        case .main: (current == nil ? [] : [.nowPlaying]) + [.playlists, .likedSongs, .shuffleSongs, .settings]
        case .playlists: library.filter { $0.id != Playlist.likedSongsID }.map { .playlist($0.id) }
        case .tracks(let pl): tracks(in: pl).map { .track($0.id) }
        // No Skin row: 1.0 has only the Pocket skin. Dark and Aqua come later (design doc).
        case .settings: [.shuffle, .repeatMode, .albumArt, .clicker, .about, .logOut]
        case .confirm: [.cancel, .confirmLogOut]
        case .auth, .about, .now: []
        }
    }
}
