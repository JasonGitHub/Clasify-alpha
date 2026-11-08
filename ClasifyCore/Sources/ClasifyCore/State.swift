import Foundation

public struct Track: Equatable, Sendable {
    public var id: String  // Spotify URI
    public var title: String
    public var artist: String
    public var duration: Double  // seconds
    /// The album cover's Spotify image file ID (hex), or nil when the track has none.
    public var coverID: String?
    /// The large cover (about 640 px), for the main menu's large covers. Nil when there is none.
    public var largeCoverID: String?
    /// The album, for the Albums menu. Nil when Spotify does not give it.
    public var album: Album?
    /// The disc and the track's place on it, from 1. Nil when Spotify does not give them.
    public var disc: Int?, number: Int?

    public init(
        id: String, title: String, artist: String, duration: Double, coverID: String? = nil,
        album: Album? = nil, disc: Int? = nil, number: Int? = nil, largeCoverID: String? = nil
    ) {
        self.id = id; self.title = title; self.artist = artist; self.duration = duration
        self.coverID = coverID.flatMap { $0.isEmpty ? nil : $0 }
        self.largeCoverID = largeCoverID.flatMap { $0.isEmpty ? nil : $0 }
        self.album = album
        self.disc = disc.flatMap { $0 > 0 ? $0 : nil }
        self.number = number.flatMap { $0 > 0 ? $0 : nil }
    }
}

/// An album, as a liked song names it.
public struct Album: Equatable, Hashable, Sendable {
    public var id: String  // Spotify URI, like "spotify:album:<id>"
    public var name: String
    /// The album's artists, joined with ", ". Nil when Spotify gives none.
    public var artist: String?

    public init(id: String, name: String, artist: String? = nil) {
        self.id = id; self.name = name
        self.artist = artist.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// True for an album URI. A song list of an album (`Screen.tracks` with this ID) shows the
    /// album's songs from Liked Songs.
    public static func isID(_ id: String) -> Bool { id.hasPrefix("spotify:album:") }

    /// The songs of album `id` among `tracks`, in disc and track order. Songs with no number
    /// keep their order, after the numbered ones of their disc.
    public static func songs(_ id: String, in tracks: [Track]) -> [Track] {
        let songs = tracks.enumerated().filter { $0.element.album?.id == id }
        let order = { (e: (offset: Int, element: Track)) in (e.element.disc ?? 1, e.element.number ?? Int.max, e.offset) }
        return songs.sorted { order($0) < order($1) }.map(\.element)
    }

    /// The album from the bridge's fields, where "" means missing. Nil with no album URI.
    public static func from(id: String?, name: String?, artist: String?) -> Album? {
        guard let id, !id.isEmpty else { return nil }
        return Album(id: id, name: name ?? "", artist: artist)
    }
}

extension Album {
    /// Sorts names that start with a letter after the others, then by the name with no case or accents.
    struct SortKey: Comparable {
        var letter: Bool, name: String

        init(_ name: String) {
            self.name = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            letter = self.name.first?.isLetter ?? false
        }

        static func < (a: SortKey, b: SortKey) -> Bool { (a.letter ? 1 : 0, a.name) < (b.letter ? 1 : 0, b.name) }
    }

    /// The letter that an album name sorts under, as Cover Flow's letter jump shows it: the
    /// first letter in capitals, with no accent, or "#" for a number or a symbol.
    public static func letter(_ name: String) -> String {
        let key = SortKey(name)
        guard key.letter, let first = key.name.first else { return "#" }
        return String(first).uppercased()
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
    /// `tracks` shows a playlist, Liked Songs, or an album's songs from Liked Songs (`Album.isID`).
    /// `albums` lists the albums in Liked Songs. `coverFlow` shows the same albums as covers,
    /// one at a time: `Frame.sel` is the index of the album in the middle. `albumPanel` is
    /// the song panel that a Cover Flow cover turns into: an album's songs from Liked Songs.
    case login, auth, main, playlists, albums, tracks(playlist: String), settings, confirm, about, now, coverFlow
    case albumPanel(album: String)

    /// Screens that show a scrollable list the wheel moves through.
    public var isList: Bool {
        switch self {
        case .login, .main, .playlists, .albums, .tracks, .settings, .confirm, .albumPanel: true
        case .auth, .about, .now, .coverFlow: false
        }
    }

    /// The list that this screen's song rows play from: a playlist, Liked Songs or an album.
    /// Nil on screens with no song rows.
    public var songList: String? {
        switch self {
        case .tracks(let id), .albumPanel(let id): id
        default: nil
        }
    }
}

/// How a screen change moves. Most changes push: the new screen slides in from one side.
public enum NavMove: Equatable, Sendable {
    case push
    /// Between the main menu and Cover Flow: the menu opens like two doors (card AE, change 82).
    case doors
    /// Between Cover Flow and the song panel: the cover turns over (card AF).
    case flip
    /// Between the song panel and Now Playing: the cover flies to its place (card AH).
    case fly
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
    case logIn, nowPlaying, coverFlow, playlists, albums, likedSongs, shuffleSongs, settings
    case playlist(String), album(String), track(String)
    case shuffle, repeatMode, skin, albumArt, deviceColor, clicker, about, logOut
    case cancel, confirmLogOut
}

/// The playing track, by ID, so a library reload that reorders things can't point it elsewhere.
public struct TrackRef: Equatable, Sendable {
    public var playlist: String, track: String
    public init(playlist: String, track: String) { self.playlist = playlist; self.track = track }
}

/// The playing track and its play state before a load.
public struct BeforeLoad: Equatable, Sendable {
    public var current: TrackRef, t: Double, isPlaying: Bool
}

/// What the wheel changes on Now Playing. A center press steps through them in this order.
public enum NowMode: CaseIterable, Sendable { case volume, scrub, shuffle, repeatMode }
public enum RepeatMode: String, CaseIterable, Sendable {
    case off = "Off", all = "All", one = "One"

    /// The repeat slider on Now Playing, from left to right.
    public static let sliderOrder: [RepeatMode] = [.off, .one, .all]
}
/// Where album covers show. The Settings row goes All, Now Playing, Off, then All again.
public enum AlbumArt: String, CaseIterable, Sendable {
    /// Covers beside the main menu and Playlists, and on Now Playing.
    case all = "All"
    /// The cover on Now Playing only. The menus are full width.
    case nowPlaying = "Now Playing"
    /// No covers. Now Playing centers its text.
    case off = "Off"
}
/// The Pocket skin's body color (round 8, card Z). The Settings row goes Silver, Black, then Silver again.
public enum DeviceColor: String, CaseIterable, Sendable { case silver = "Silver", black = "Black" }

/// The Mac's battery, shown in the title bar (round 7, card Y).
public struct Battery: Equatable, Sendable {
    /// From 0 (empty) to 1 (full).
    public var level: Double
    /// The battery is charging now.
    public var charging: Bool
    /// The Mac runs on power from the adapter. It can be on power and not charging, when the
    /// battery is full or macOS holds the charge.
    public var onPower: Bool

    public init(level: Double, charging: Bool, onPower: Bool) {
        self.level = min(max(level, 0), 1); self.charging = charging; self.onPower = onPower
    }

    /// Below 20%, the level shows in red.
    public var low: Bool { level < 0.2 }
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
    /// The last seek: its target, when it was sent, and its generation. The engine can still
    /// report a position from an earlier seek with the new generation. During a fast scrub,
    /// that old position made the diamond jump back, so `.position` ignores it for a short time.
    public var seekTarget: Double = 0
    public var seekAt: Double = 0
    public var seekGen = -1
    /// The track of the last seek. A seek near the end can move to the next track in the same
    /// generation, and the filter must not hold back that track's positions.
    public var seekTrack: String?
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
    /// The covers that take turns on the main menu's right side. `refreshArt` sets them.
    public var mainArt: [Track] = []
    /// The main menu row whose covers show. It follows the selection `artDelay` after the last
    /// change, so a fast scroll does not flicker.
    public var artRow: Row?
    /// When `artRow` takes the selected row. 0 when it already has it.
    public var artUntil: Double = 0
    /// Sets the random order of the covers. The reducer picks a new one with `env.random`
    /// each time the main menu opens.
    public var artSeed = 0
    /// The playlist list was read in this session.
    public var playlistsLoaded = false
    /// The playlists (and `Playlist.likedSongsID`) whose tracks were read in this session.
    public var loadedTracks: Set<String> = []
    public var current: TrackRef?
    /// What `current` showed before the newest load, so a load that fails can show it again.
    public var beforeLoad: BeforeLoad?
    /// A load started and the engine did not report it yet. A new load then keeps `beforeLoad`.
    public var loadPending = false
    /// Tracks that Spotify played from outside our copy of the list, read one at a time.
    /// Memory only, at most `extraTrackLimit`, the oldest goes first. Emptied at sign-out.
    public var extraTracks: [Track] = []
    /// Track IDs whose read runs or failed in this session, so each is read only once.
    public var trackReads: Set<String> = []
    /// When each list was last read, by `readKey`. Opening a list older than `staleAfter`
    /// reads it again in the background.
    public var readAt: [String: Double] = [:]
    /// The `readKey`s whose background re-read runs, so each runs once at a time.
    public var refreshing: Set<String> = []
    /// Playlists whose tracks are read for the covers, with the token of each read, so each is
    /// read once and a late result from before a logout or reset is ignored.
    public var artReads: [String: Int] = [:]
    /// The token of the last cover read. Kept apart from `tok`, so cover reads do not change list tokens.
    public var artTok = 0
    public var t: Double = 0
    public var isPlaying = false
    public var volume = 60
    public var shuffle = false
    public var repeatMode = RepeatMode.off
    public var skin = Skin.pocket
    public var albumArt = AlbumArt.all
    /// Now Playing shows the playing track's cover.
    public var showsNowPlayingArt: Bool { albumArt != .off }
    public var deviceColor = DeviceColor.silver
    public var clicker = true
    /// The About art scene that shows, from 0. Each open of About shows the next scene, and the
    /// first open after launch shows scene 0. In memory only: nothing is saved.
    public var aboutScene = 0
    /// How many times About opened since launch.
    public var aboutOpens = 0
    /// The About art scenes: the castle, the takoyaki, then Dotonbori.
    public static let aboutScenes = 3
    /// nil when the Mac has no battery, or before the app reads it.
    public var battery: Battery?
    public var nowMode = NowMode.volume
    /// When the volume bar hides, or when a scrub, shuffle or repeat slider goes back to the
    /// progress bar. 0 when nothing is timed.
    public var overlayUntil: Double = 0
    /// When a list's scroll bar fades out: `scrollBarTime` after the last wheel step on a
    /// list or the last screen change. 0 when the bar is hidden.
    public var scrollUntil: Double = 0
    /// Counts screen changes, so a skin can slide the new screen in. `navForward` is true when
    /// a screen opened, false on a way back.
    public var navSeq = 0
    public var navForward = true
    /// Counts the moves between a half screen (`isHalf`) and a full one. On those, a skin
    /// pushes the whole screen, with its title bar; on other moves only the content slides.
    public var wholeSeq = 0
    /// How the last screen change moves, so a skin can draw it (Round 9, cards AE, AF, AH).
    public var navMove = NavMove.push
    /// Quick wheel steps on a list move more rows.
    public var wheelSpeed = WheelSpeed()
    /// The album that Cover Flow showed last, so it opens there again when nothing plays.
    public var coverFlowAlbum: String?
    /// The times of the last Cover Flow wheel steps, at most `fastSpinSteps`.
    public var coverFlowSteps: [Double] = []
    /// While Cover Flow shows the big letter: each wheel step jumps to the next or previous
    /// letter. 0 when the letter is hidden.
    public var letterUntil: Double = 0
    public var toast = ""
    public var toastUntil: Double = 0
    public var offline = false

    public init() {}

    public var top: Frame {
        get { stack[stack.count - 1] }
        set { stack[stack.count - 1] = newValue }
    }

    /// The bar for the playing track shows only under song lists. Menus, Playlists and Now
    /// Playing show no bar, so the menus keep all their rows.
    public var showsBar: Bool {
        guard current != nil, case .tracks = top.screen else { return false }
        return true
    }

    /// The Cover Flow frame, while Cover Flow or its song panel shows. Its `sel` is the album
    /// in the middle, also while the panel shows the album's songs.
    public var coverFlowFrame: Frame? {
        switch top.screen {
        case .coverFlow, .albumPanel: stack.last { $0.screen == .coverFlow }
        default: nil
        }
    }

    /// The list rows that show at once: `visibleRows`, or `trackRows` for the taller two-line
    /// song rows. The bar takes no row: the song rows get shorter while it shows.
    public var shownRows: Int {
        switch top.screen {
        case .tracks, .albums: return trackRows  // two-line rows
        case .albumPanel: return panelRows
        default: return visibleRows
        }
    }

    /// The selected row of the main menu, or nil on another screen.
    public var mainRow: Row? {
        guard top.screen == .main else { return nil }
        let rows = rows(for: top)
        return rows.indices.contains(top.sel) ? rows[top.sel] : nil
    }

    /// The screen is a half screen: a list pane on the left half with the covers on its right. With Album
    /// Art set to All, these are the main menu, Playlists and Albums.
    public func isHalf(_ screen: Screen) -> Bool {
        albumArt == .all && (screen == .main || screen == .playlists || screen == .albums)
    }

    /// The selected row of a half screen, whose covers show. Nil on other screens, and while
    /// the list has no rows.
    public var halfRow: Row? {
        guard isHalf(top.screen) else { return nil }
        let rows = rows(for: top)
        return rows.indices.contains(top.sel) ? rows[top.sel] : nil
    }

    /// Picks the covers of the main menu's right side for `artRow`, into `mainArt`:
    /// - Now Playing: the playing track's cover only.
    /// - Playlists: albums from the playlists already read, or Liked Songs until one is read.
    /// - Liked Songs, Shuffle Songs and Settings: albums from Liked Songs.
    /// - A playlist on the Playlists screen: albums from that playlist. Until its tracks are
    ///   read, or when the read failed or has no covers, the covers that show stay.
    /// - An album on the Albums screen: that album's cover.
    /// Up to `mainArtCount` albums, each cover once, in a random order that `artSeed` sets.
    /// With none of these, the playing track's cover. Tracks with no cover are left out.
    public mutating func refreshArt() {
        let playing = current.flatMap { track($0) }.flatMap { $0.coverID == nil ? nil : $0 }
        let liked = tracks(in: Playlist.likedSongsID)
        var pool: [Track]
        switch artRow {
        case .playlist(let id)?, .album(let id)?:
            let picks = Self.albums(isLoaded(.tracks(playlist: id)) ? tracks(in: id) : [], seed: artSeed, count: mainArtCount)
            if !picks.isEmpty { mainArt = picks }
            return
        case .nowPlaying?:
            pool = []
        case .playlists?:
            pool = library.filter { $0.id != Playlist.likedSongsID && loadedTracks.contains($0.id) }.flatMap(\.tracks)
            if !pool.contains(where: { $0.coverID != nil }) { pool = liked }
        default:
            pool = liked
        }
        var picks = Self.albums(pool, seed: artSeed, count: mainArtCount)
        if picks.isEmpty, let playing { picks = [playing] }
        mainArt = picks
    }

    /// Up to `count` tracks with distinct covers, in a random order that `seed` sets.
    static func albums(_ tracks: [Track], seed: Int, count: Int) -> [Track] {
        var seen: Set<String> = []
        var pool: [(key: UInt64, id: String, track: Track)] = []
        for track in tracks {
            guard let id = track.coverID, seen.insert(id).inserted else { continue }
            pool.append((mix(seed, id), id, track))
        }
        pool.sort { $0.key != $1.key ? $0.key < $1.key : $0.id < $1.id }
        return pool.prefix(count).map(\.track)
    }

    /// A stable hash of the seed and a cover ID (FNV-1a). Swift's `Hasher` changes with each launch.
    static func mix(_ seed: Int, _ id: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325 ^ UInt64(truncatingIfNeeded: seed)
        for byte in id.utf8 { h = (h ^ UInt64(byte)) &* 0x100_0000_01b3 }
        return h
    }

    /// How a change from screen `a` to screen `b`, either way, moves. `whole` is true when one
    /// of them is a half screen and the other is not.
    public static func move(between a: Screen, and b: Screen, whole: Bool) -> NavMove {
        func isPanel(_ s: Screen) -> Bool { if case .albumPanel = s { true } else { false } }
        func either(_ x: (Screen) -> Bool, _ y: (Screen) -> Bool) -> Bool { (x(a) && y(b)) || (y(a) && x(b)) }
        if whole && either({ $0 == .main }, { $0 == .coverFlow }) { return .doors }
        if either({ $0 == .coverFlow }, isPanel) { return .flip }
        if either(isPanel, { $0 == .now }) { return .fly }
        return .push
    }

    /// The screen's list is already in the state, so it opens without a read.
    public func isLoaded(_ screen: Screen) -> Bool {
        switch screen {
        case .playlists: playlistsLoaded
        case .tracks(let id): loadedTracks.contains(Self.source(id))
        case .albums, .coverFlow, .albumPanel: loadedTracks.contains(Playlist.likedSongsID)
        default: true
        }
    }

    /// The list that a song list reads: Liked Songs for an album, else the playlist itself.
    public static func source(_ id: String) -> String { Album.isID(id) ? Playlist.likedSongsID : id }

    /// The `readAt` key of a list screen: the playlist ID that it reads, or "" for the playlist list.
    public static func readKey(_ screen: Screen) -> String {
        switch screen {
        case .tracks(let id): source(id)
        case .albums, .coverFlow, .albumPanel: Playlist.likedSongsID
        default: ""
        }
    }

    /// A playlist's tracks. For an album ID, the album's songs in Liked Songs, in disc and track order.
    public func tracks(in playlist: String) -> [Track] {
        guard Album.isID(playlist) else { return library.first { $0.id == playlist }?.tracks ?? [] }
        return Album.songs(playlist, in: tracks(in: Playlist.likedSongsID))
    }

    /// An album in Liked Songs, by its URI, with the artist as `albums` gives it. When its last
    /// song left Liked Songs, the album of a kept track (such as the playing one), so the
    /// title bar and Now Playing keep its name.
    public func album(_ id: String) -> Album? {
        let track = tracks(in: Playlist.likedSongsID).first { $0.album?.id == id } ?? extraTracks.first { $0.album?.id == id }
        guard let track, var album = track.album else { return nil }
        if album.artist == nil { album.artist = track.artist.isEmpty ? nil : track.artist }
        return album
    }

    /// The albums in Liked Songs, each once: names that start with a number or a symbol first,
    /// then A to Z, with no regard to case or accents. An album with no album artist from
    /// Spotify takes the artist of its first song.
    public var albums: [Album] {
        var found: [String: Album] = [:]
        var order: [String] = []
        for track in tracks(in: Playlist.likedSongsID) {
            guard var album = track.album, found[album.id] == nil else { continue }
            if album.artist == nil { album.artist = track.artist.isEmpty ? nil : track.artist }
            found[album.id] = album
            order.append(album.id)
        }
        let keyed = order.compactMap { found[$0] }.map { album -> (key: Album.SortKey, album: Album) in
            (Album.SortKey(album.name), album)
        }
        return keyed.sorted { ($0.key, $0.album.id) < ($1.key, $1.album.id) }.map(\.album)
    }

    /// The track in its playlist, else in `extraTracks`.
    public func track(_ ref: TrackRef) -> Track? {
        tracks(in: ref.playlist).first { $0.id == ref.track } ?? extraTracks.first { $0.id == ref.track }
    }

    public func rows(for frame: Frame) -> [Row] {
        switch frame.screen {
        case .login: restoring ? [] : [.logIn]
        case .main:
            (current == nil ? [] : [.nowPlaying]) + [.coverFlow, .playlists, .albums, .likedSongs, .shuffleSongs, .settings]
        case .playlists: library.filter { $0.id != Playlist.likedSongsID }.map { .playlist($0.id) }
        case .albums, .coverFlow: albums.map { .album($0.id) }
        case .tracks(let pl), .albumPanel(let pl): tracks(in: pl).map { .track($0.id) }
        // No Skin row: 1.0 has only the Pocket skin. Dark and Aqua come later (design doc).
        case .settings: [.shuffle, .repeatMode, .albumArt, .deviceColor, .clicker, .about, .logOut]
        case .confirm: [.cancel, .confirmLogOut]
        case .auth, .about, .now: []
        }
    }

    /// The first album of the next letter (`step` 1) or of the previous one (`step` -1) from
    /// index `i` of `albums`, which are in A to Z order. On the last letter it stays, and on
    /// the first letter it goes to the first album.
    static func letterJump(from i: Int, by step: Int, in albums: [Album]) -> Int {
        let letters = albums.map { Album.letter($0.name) }
        func start(_ j: Int) -> Int {  // the first album of the letter at j
            var j = j
            while j > 0 && letters[j - 1] == letters[j] { j -= 1 }
            return j
        }
        if step > 0 {
            let next = letters[i...].firstIndex { $0 != letters[i] }
            return next ?? i
        }
        let here = start(i)
        return here > 0 ? start(here - 1) : 0
    }

    /// The cover ID of each album in Liked Songs, by album ID: the cover of its first song
    /// that has one. Cover Flow draws the albums with these.
    public var albumCovers: [String: String] {
        var covers: [String: String] = [:]
        for track in tracks(in: Playlist.likedSongsID) {
            guard let album = track.album?.id, covers[album] == nil, let cover = track.coverID else { continue }
            covers[album] = cover
        }
        return covers
    }

    /// The big letter that Cover Flow shows during a fast spin: the letter of the album in the
    /// middle. Nil when it is hidden.
    public var coverFlowLetter: String? {
        guard letterUntil > 0, top.screen == .coverFlow else { return nil }
        let list = albums
        return list.indices.contains(top.sel) ? Album.letter(list[top.sel].name) : nil
    }
}
