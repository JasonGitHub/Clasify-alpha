public struct Track: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var duration: Double  // seconds

    public init(title: String, artist: String, duration: Double) {
        self.title = title; self.artist = artist; self.duration = duration
    }
}

public struct Playlist: Equatable, Sendable {
    public var name: String
    public var tracks: [Track]

    public init(name: String, tracks: [Track]) { self.name = name; self.tracks = tracks }
}

public enum Screen: Equatable, Sendable {
    case login, auth, main, playlists, tracks(playlist: Int), settings, confirm, about, now

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
    case playlist(Int), track(Int)
    case shuffle, repeatMode, eq, skin, albumArt, clicker, engine, about, logOut
    case cancel, confirmLogOut
}

public struct TrackRef: Equatable, Sendable {
    public var playlist: Int, track: Int
    public init(playlist: Int, track: Int) { self.playlist = playlist; self.track = track }
}

public enum NowMode: Sendable { case volume, scrub }
public enum RepeatMode: String, CaseIterable, Sendable { case off = "Off", all = "All", one = "One" }
public enum EQPreset: String, CaseIterable, Sendable { case off = "Off", rock = "Rock", pop = "Pop", vocal = "Vocal", bass = "Bass" }
public enum Skin: String, CaseIterable, Sendable { case pocket = "Pocket", aqua = "Aqua", dark = "Dark" }
public enum Engine: String, CaseIterable, Sendable { case builtIn = "Built-in", spotifyApp = "Spotify app" }

extension CaseIterable where Self: Equatable {
    var next: Self {
        let all = Array(Self.allCases)
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

public struct AppState: Equatable, Sendable {
    public var stack = [Frame(screen: .login)]
    public var tok = 0
    public var signedIn = false
    /// Index 0 is Liked Songs; the rest are the user's playlists.
    public var library: [Playlist] = []
    public var current: TrackRef?
    public var t: Double = 0
    public var isPlaying = false
    public var volume = 60
    public var shuffle = false
    public var repeatMode = RepeatMode.off
    public var eq = EQPreset.off
    public var skin = Skin.pocket
    public var showArt = true
    public var clicker = true
    public var engine = Engine.builtIn
    public var nowMode = NowMode.volume
    public var overlayUntil: Double = 0
    public var toast = ""
    public var toastUntil: Double = 0
    public var offline = false

    public init() {}

    public var top: Frame {
        get { stack[stack.count - 1] }
        set { stack[stack.count - 1] = newValue }
    }

    public func tracks(in playlist: Int) -> [Track] {
        library.indices.contains(playlist) ? library[playlist].tracks : []
    }

    public func track(_ ref: TrackRef) -> Track? {
        let list = tracks(in: ref.playlist)
        return list.indices.contains(ref.track) ? list[ref.track] : nil
    }

    public func rows(for frame: Frame) -> [Row] {
        switch frame.screen {
        case .login: [.logIn]
        case .main: (current == nil ? [] : [.nowPlaying]) + [.playlists, .likedSongs, .shuffleSongs, .settings]
        case .playlists: library.indices.dropFirst().map(Row.playlist)
        case .tracks(let pl): tracks(in: pl).indices.map(Row.track)
        case .settings: [.shuffle, .repeatMode, .eq, .skin, .albumArt, .clicker, .engine, .about, .logOut]
        case .confirm: [.cancel, .confirmLogOut]
        case .auth, .about, .now: []
        }
    }
}
