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
    public static func isID(_ id: String) -> Bool { id.hasPrefix("spotify:album:") || id.hasPrefix("applemusic:album:") }

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
    /// The songs of the library's albums, each carrying its album (Apple Music only, where
    /// Albums and Cover Flow show the library's own albums, as the Music app's Library does). It is never a Playlists row, a play context or a playlist count.
    public static let libraryID = "library:all"

    /// All songs of the library, for the Songs row (Apple Music only, card BN), in title order
    /// (`Track.titleOrder`). It is never a Playlists row or a playlist count.
    public static let songsID = "library:songs"
    /// An artist's songs, for a row of the Artists screen (card BN): its ID from the `Library`.
    public static func isArtistID(_ id: String) -> Bool { id.hasPrefix("applemusic:artist:") || id.hasPrefix("spotify:artist:") }

    /// The list is not a playlist: Liked Songs, the whole library, all songs, an artist or an album.
    public static func isHidden(_ id: String) -> Bool {
        id == likedSongsID || id == libraryID || id == songsID || isArtistID(id) || Album.isID(id)
    }

    /// Names in list order (card BN): numbers and symbols first, then A to Z, with no regard to
    /// case or accents, and a leading "The " left out, so "The Lowlights" sorts under L.
    public static func nameOrder(_ a: String, _ b: String) -> Bool { Album.SortKey(dropThe(a)) < Album.SortKey(dropThe(b)) }
    static func dropThe(_ name: String) -> String {
        name.lowercased().hasPrefix("the ") && name.count > 4 ? String(name.dropFirst(4)) : name
    }

    public init(id: String, name: String, tracks: [Track], trackCount: Int? = nil) {
        self.id = id; self.name = name; self.tracks = tracks; self.trackCount = trackCount ?? tracks.count
    }
}

public enum Screen: Equatable, Sendable {
    /// `tracks` shows a playlist, Liked Songs, or all songs of an album (`Album.isID`).
    /// `albums` lists the albums in Liked Songs. `coverFlow` shows the same albums as covers,
    /// one at a time: `Frame.sel` is the index of the album in the middle. `albumPanel` is
    /// the song panel that a Cover Flow cover turns into: all songs of the album (CLA-46).
    case login, auth, main, playlists, albums, tracks(playlist: String), settings, confirm, about, now, coverFlow
    case albumPanel(album: String)
    /// The first launch setup (Round 13), in order: `hello` (card AT), `color` (AW), then
    /// `login`, `auth`, `loginFailed` and `loggedIn` (AX), `spotifyApp` (BB, only when the Spotify app is missing) and
    /// `yourMusic` (AY, the first library read). BB also shows at a later launch when the
    /// Spotify app is missing.
    case hello, color, spotifyApp, yourMusic
    /// The login (card AX, changes 171 and 175): it failed, or it worked. `loggedIn` shows for
    /// `AppState.beatTime`, then the next step opens. Every login uses them, not only setup.
    case loginFailed, loggedIn
    /// The login worked, but the account is not Spotify Premium (card AX, screen 135). Clasify
    /// needs Premium to play. "Check again" logs in again with the stored login.
    case premium
    /// Card BM: the music service pick of the first run, after the color pick (257), and
    /// Apple Music's screen after a "Don't Allow" in the macOS prompt (258).
    case pickMusic, accessOff
    /// About's Licenses list, and the text of license `License.all[i]` with the names of the
    /// parts under it (card BF, change 213).
    case licenses, license(Int)
    /// The library's artists (Apple Music, card BN). An artist's songs show on `tracks`.
    case artists
    /// Card BI v2: the one warning on day 27 of a beta (change 233), and its end on day 30 (234).
    case betaSoon, betaEnded

    /// Screens that show a scrollable list the wheel moves through.
    public var isList: Bool {
        switch self {
        case .login, .auth, .loginFailed, .main, .playlists, .albums, .tracks, .settings, .confirm, .albumPanel, .color,
            .spotifyApp, .premium, .licenses, .pickMusic, .accessOff, .artists, .betaSoon, .betaEnded:
            true
        case .about, .now, .coverFlow, .hello, .yourMusic, .loggedIn, .license: false
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
    /// Card BN (Apple Music): the main menu's Artists and Songs, and one artist by its ID.
    case artists, songs, artist(String)
    case shuffle, repeatMode, skin, albumArt, deviceColor, clicker, nowPlayingBar, about, logOut
    /// Card BM, change 256: the active music service, first in Settings.
    case service
    case cancel, confirmLogOut
    /// Rows of the login (card AX): open the browser again while it waits (170), and try
    /// again after a failed login (171). `cancel` stops the login.
    case openBrowser, tryAgain
    /// The Spotify App screen's row (card BB): opens the Spotify download page in the browser.
    case getSpotifyApp
    /// Rows of the Premium screen (card AX, screen 135): log in again with the stored login,
    /// open Spotify's Premium page in the browser, and forget the login.
    case checkPremium, getPremium, premiumLogOut
    /// Card BM: a service on Pick Your Music (257), "Open Settings" (258), "Use Spotify" (262).
    case pickService(MusicService), openPrivacy, useSpotify
    /// A row of the setup screen `color` (card AW).
    case color(DeviceColor)
    /// A row of the Licenses list: license `License.all[i]` (card BF, change 213).
    case license(Int)
    /// Card BI v2: the beta screens' rows. "Get New Beta" opens the download page, "Later"
    /// closes the warning, and "Quit" quits the app (changes 233 and 234).
    case getNewBeta, later, quit
}

/// A beta build (card BI v2, CLA-96): a Developer ID signed build. It warns once on day 27 and
/// ends on day 30 after it was signed. Ad-hoc builds are not betas and never end.
public struct BetaBuild: Equatable, Sendable {
    /// When the build was signed, in `Dependencies.now` time.
    public var signed: Double
    public init(signed: Double) { self.signed = signed }

    public static let day = 86_400.0
    /// Change 233: the one warning, 3 days before the end.
    public var warnsAt: Double { signed + 27 * Self.day }
    /// Change 234: the beta ends.
    public var endsAt: Double { signed + 30 * Self.day }
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
    /// Token of a Liked Songs load that should start Liked Songs when it finishes.
    public var shuffleToken: Int?
    /// That start comes from Play with nothing to resume (CLA-61): it follows the Shuffle
    /// setting when the load ends. Else it comes from Shuffle Songs and always shuffles.
    public var pendingPlay = false
    public var signedIn = false
    /// The first launch setup ended once. Saved with the settings, so later launches skip
    /// Hello, the color pick and the first library read.
    public var setupDone = false
    /// The Spotify app is on this Mac, as the app last found it. Nil before the first check:
    /// setup then counts it as there, so that a slow check does not stop it.
    public var spotifyApp: Bool?
    /// This build is a beta (card BI v2), as the app read it from its signature. Nil for an
    /// ad-hoc build: it shows no BETA tag and never ends.
    public var beta: BetaBuild?
    /// The signing time of the beta whose warning showed (change 233: once). Saved with the
    /// settings, so a new beta warns again.
    public var betaWarned: Double?
    /// When Hello (card AT) opened, in `Dependencies.now` time. A skin times the hello word,
    /// the center glow and the begin text from it.
    public var helloAt: Double = 0
    /// When the color pick (card AW) opened, and when the wheel first turned on it (0 before
    /// that). A skin times the waiting comet, the hint and the center glow from them.
    public var colorAt: Double = 0, colorTurnAt: Double = 0
    /// When "You’re in" (card AX, change 175) or "Linked" on the Spotify App screen (card BB,
    /// change 174) moves on by itself. 0 when neither shows.
    public var beatUntil: Double = 0
    /// "Premium" shows on the Premium screen (card AX, screen 135): "Check again" found it,
    /// and Clasify goes on after `beatTime`.
    public var premiumFound = false
    /// When "Check again" was pressed, or Premium was found: the sync cable's light flows once
    /// from then. 0 before that.
    public var premiumAt: Double = 0
    /// Seconds that "You’re in", "Linked" and "Premium" show before the next step.
    public static let beatTime = 1.5
    /// Seconds that "You’re all set" (card AY, change 140) shows before the main menu: no hurry.
    /// Change 267: 1.5 s for `songs` 20 or fewer, 2.5 s for 100 or more, or when the count is
    /// not known.
    public static func allSetTime(songs: Int?) -> Double { 1.5 + setupPace(songs: songs) }
    /// Card AY, changes 266 and 267: a small first read goes faster. 0 for 20 songs or fewer,
    /// 1 for 100 or more, and a straight line between. 1 when the count is not known yet.
    static func setupPace(songs: Int?) -> Double {
        guard let songs else { return 1 }
        return min(max(Double(songs - 20) / 80, 0), 1)
    }
    /// The song count of the first read: its first total, or the songs it read. nil until the
    /// library gives one. It stays as it was first given, so the pace never slows down.
    public var firstReadSongs: Int?
    /// When the playlist names came during the first library read (card AY). A skin fills
    /// them in one by one from then. 0 before they come.
    public var namesAt: Double = 0
    /// How far the first library read is: `readDone` of `readTotal` songs, on `readAlbums`
    /// albums (card AY, change 188). 0 of 0 before the library knows the total.
    public var readDone = 0, readTotal = 0, readAlbums = 0
    /// The first library read ended before all its playlist names showed (card AY, change
    /// 191): "Getting your music" stays until then. 0 when it does not wait. Like every
    /// deadline that `.tick` ends, the app's ticker must check it, or `.tick` never comes.
    /// `.infinity` while the read has ended and the playlist list has not come yet (CLA-74):
    /// `.playlistsRefreshed` then sets the deadline, or ends the read.
    public var namesHold: Double = 0
    /// The names on the small screen during the first read: each fades in and rises over
    /// `nameFade`, `nameGap` after the one before it, from `nameStart` after they came. Six
    /// names have shown 2.5 s after they came (CLA-80). The 191 hold and the skin use these too.
    public static let nameStart = 0.5, nameGap = 0.34, nameFade = 0.3
    /// Change 266: seconds from when the names came until the last of `names` has shown. 1 s
    /// for `songs` 20 or fewer, up to 2.5 s for 100 or more, and never longer than the time
    /// above for that many names. The time above while the count is not known.
    public static func namesTime(names: Int, songs: Int?) -> Double {
        guard names > 0 else { return 0 }
        return min(fullNamesTime(names), 1 + 1.5 * setupPace(songs: songs))
    }
    static func fullNamesTime(_ names: Int) -> Double { nameStart + nameGap * Double(names - 1) + nameFade }
    /// Seconds that the rest takes when the count comes after the names (Apple Music gives it
    /// only at the end of the read).
    public static let lateFinish = 0.2
    /// When the names are done, in seconds after they came. `late`: the count came that many
    /// seconds after the names; nil when it came before them, or has not come. A late count
    /// moves the end to its own time, but the rest takes at least `lateFinish`, and never ends
    /// later than the old time. The 191 hold, the names and the bar all end here.
    public static func namesEnd(names: Int, songs: Int?, late: Double?) -> Double {
        guard names > 0 else { return 0 }
        let stay = namesTime(names: names, songs: songs)
        guard let late else { return stay }
        let full = fullNamesTime(names)
        if late >= full { return late }  // every name had shown
        return max(stay, min(full, late + lateFinish))
    }
    /// How far the names are, 0 to 1, `t` seconds after they came: steady until `namesEnd`.
    /// Before a late count, at the time above; after it, from there to the end. It never goes
    /// back, so the bar and the names never jump back.
    public static func namesProgress(at t: Double, names: Int, songs: Int?, late: Double?) -> Double {
        guard names > 0 else { return 1 }
        let end = namesEnd(names: names, songs: songs, late: late)
        let p: Double
        if let late, t >= late {
            let from = min(1, late / fullNamesTime(names))
            p = end > late ? from + (1 - from) * (t - late) / (end - late) : 1
        } else {
            p = t / (late == nil ? end : fullNamesTime(names))
        }
        return min(max(p, 0), 1)
    }
    /// Name `i`'s opacity, `t` seconds after the names came. The times above, made shorter in
    /// step with `namesProgress`, so the last name has shown at `namesEnd`.
    public static func nameOpacity(_ i: Int, of names: Int, at t: Double, songs: Int?, late: Double?) -> Double {
        guard names > 0 else { return 0 }
        let u = namesProgress(at: t, names: names, songs: songs, late: late) * fullNamesTime(names)
        return min(max((u - nameStart - nameGap * Double(i)) / nameFade, 0), 1)
    }
    /// When `firstReadSongs` came. 0 before.
    public var firstReadSongsAt: Double = 0
    /// Seconds from when the names came until the count came, when it came after them.
    public var namesLate: Double? {
        namesAt > 0 && firstReadSongs != nil && firstReadSongsAt > namesAt ? firstReadSongsAt - namesAt : nil
    }
    /// The playlist names that show on the small screen during the first read: up to 6.
    public var firstReadNames: [String] {
        Array(library.lazy.filter { !Playlist.isHidden($0.id) }.prefix(6).map(\.name))
    }
    /// The number of playlists, for the first read's count (change 188).
    public var playlistCount: Int {
        library.filter { !Playlist.isHidden($0.id) }.count
    }
    /// The Spotify session expired (card AX, change 181). The login screen then says "Log in
    /// again". A logout, a login that works and a reset clear it.
    public var sessionEnded = false
    /// A restore of the stored login runs. The login screen offers no Log in row meanwhile,
    /// so a browser login cannot race it. Skins show "Signing in…".
    public var restoring = false
    /// Liked Songs (once read) first, then the playlists. Each part loads when its screen opens.
    public var library: [Playlist] = []
    /// The words of the active service's library ("Liked Songs" on Spotify), from the `Library`.
    public var words = LibraryWords.spotify
    /// The list that Albums and Cover Flow group into albums, from the `Library`.
    public var albumsList: String { words.albumsList }
    /// The list Shuffle Songs plays. With the library rows (Apple Music), all library songs,
    /// the same as the Songs list, as on an iPod (change 278). Else the liked list.
    public var shuffleList: String { words.libraryRows ? Playlist.songsID : Playlist.likedSongsID }
    /// The liked list's name on the active service.
    public var likedSongsName: String {
        get { words.likedSongs }
        set { words.likedSongs = newValue }
    }
    /// The service that the Settings "Service" row shows after a press, until Settings closes.
    /// Leaving Settings switches to it (card BM, change 256). nil: no press since Settings opened.
    public var pendingService: MusicService?
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
    /// The library's artists in `Playlist.nameOrder`, with no tracks (card BN), and whether
    /// they were read in this session.
    public var artists: [Playlist] = []
    public var artistsLoaded = false
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
    /// The color the device shows: on the color pick (card AW), the selected row's color, so a
    /// turn tries it on at once; else the setting.
    public var shownColor: DeviceColor {
        let colors = DeviceColor.allCases
        guard top.screen == .color, colors.indices.contains(top.sel) else { return deviceColor }
        return colors[top.sel]
    }
    public var clicker = true
    /// The Now Playing Bar setting (Round 11 card AK, change 109): the bar for the playing song
    /// on every list. Off by default.
    public var nowPlayingBar = false
    /// The music service that plays and that the lists come from (CLA-103). Spotify by default.
    public var service = MusicService.spotify
    /// When About opened (card BF). Its scroll bar shows from 0.3 s after (change 207).
    public var aboutAt: Double = 0
    /// About is one page that scrolls 5 wheel steps (card BF, change 207). Its step is the
    /// frame's `off`. From step 3 the Licenses row is selected (change 211).
    public static let aboutSteps = 5, aboutLicensesStep = 3
    /// When the capybara's last wave started: 0.35 s after About opens, and on a press or a
    /// wake (change 210). The tagline's glint starts with it (change 209).
    public var aboutWaveAt: Double = 0
    /// The last About input that restarted the idle clock, and the pose at that moment.
    public var aboutIdleAt: Double = 0
    public var aboutIdleHold = AboutPoseNow(pose: .stand, since: 0, from: .stand, cut: true)
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
    /// Counts the moves between a half screen (`isHalf`) and a full one, and to and from Hello.
    /// On those, a skin pushes the whole screen, with its title bar; on other moves only the
    /// content slides.
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
    /// The first-time hint that shows now (Round 14 card BA): its wheel label glows from
    /// `hintAt`, and after `hintTipAfter` its tip shows (`hintTip`). nil when none shows.
    /// Only one shows at a time.
    public var hint: Hint?
    public var hintAt: Double = 0
    public var hintTip = false
    /// The hints that ended for good: their action was done, or their tip showed in full.
    /// Saved with the settings.
    public var hintsDone: Set<Hint> = []
    /// A status toast that came while a hint showed. It shows when the hint ends.
    public var heldToast = ""
    /// The tip comes after 3 glow pulses of 2.4 s (change 195), and stays for at most 10 s.
    public static let hintTipAfter = 7.2, hintTipTime = 10.0
    /// The play/pause and next hints wait until a song has played this many seconds on Now
    /// Playing (changes 176 and 177).
    public static let hintPlayTime = 10.0
    /// `navSeq` when the play/pause hint ended. The next hint waits for a later visit to Now
    /// Playing (change 177). -1 before.
    public var hintPlaySeq = -1
    /// When `.tick` next moves the hint on: its tip shows, or it ends. 0 when nothing is due: no
    /// hint, or a tour tip that shows (it waits for its press). Like every deadline that `.tick`
    /// ends, the app's ticker must check it, or `.tick` never comes.
    public var hintDue: Double {
        guard let hint else { return tourPlace && toast.isEmpty ? tourShowAt : 0 }  // a tour hint waits to show
        if hint.isTour { return hintTip ? 0 : hintAt + Self.tourTipAfter }
        return hintAt + Self.hintTipAfter + (hintTip ? Self.hintTipTime : 0)
    }
    /// When the tip of the hint that shows starts to fade in.
    public var hintTipAt: Double {
        guard let hint, hint.isTour else { return hintAt + Self.hintTipAfter }
        return hint == .tourPlay ? hintAt + Self.tourTipAfter : hintAt
    }
    /// The first-run hints (card BA.2, change 238): a queue of Play, Next and MENU. It starts
    /// at "You’re all set" after the first setup and runs until all three are done. Saved.
    public var tourOn = false
    /// How many times other input hid each tour hint while its words showed. At
    /// `tourHideMax` that hint is done. Saved.
    public var tourHides: [Hint: Int] = [:]
    /// The last input. A tour hint shows after `tourRest` with no input, on its screen.
    public var tourRestAt: Double = 0
    /// The tour step that runs, also while it waits to show: the first one not done. `hint` is
    /// that step while it shows. nil when no tour runs.
    public var tour: Hint? {
        tourOn ? [Hint.tourPlay, .tourNext, .tourMenu].first(where: { !hintsDone.contains($0) }) : nil
    }
    /// The tour step is on its screen: Play on the main menu, Next and MENU on Now Playing
    /// with the time bar row. A scrub, shuffle or repeat bar needs that row, as for the BA hints.
    public var tourPlace: Bool {
        guard let tour, setupDone, signedIn, stack.first?.screen == .main else { return false }
        return tour == .tourPlay ? top.screen == .main : top.screen == .now && current != nil && nowMode == .volume
    }
    /// When the waiting tour hint shows. Play glows first and its words come `tourTipAfter`
    /// later, so they show after `tourRest` like the words of Next and MENU. Next and MENU
    /// also wait for the volume bar to hide.
    public var tourShowAt: Double {
        tour == .tourPlay ? tourRestAt + Self.tourRest - Self.tourTipAfter : max(tourRestAt + Self.tourRest, overlayUntil)
    }
    public static let tourTipAfter = 2.4, tourRest = 3.0, tourHideMax = 3
    public var offline = false

    public init() {}

    public var top: Frame {
        get { stack[stack.count - 1] }
        set { stack[stack.count - 1] = newValue }
    }

    /// The wheel moves a bar: Now Playing's volume, time, shuffle and repeat sliders. Then a
    /// trackpad scroll with the fingers up is +1 (more). Elsewhere the wheel moves a list, and
    /// fingers down are +1 (the next row), whatever the natural scrolling setting (CLA-48).
    public var wheelMovesBar: Bool { top.screen == .now }

    /// The bar for the playing track, at the bottom of the screen (card AK, change 110): only
    /// with the Now Playing Bar setting on, while a song is loaded, on the main menu, Playlists,
    /// Albums, song lists and Settings. Not on Now Playing or the Cover Flow covers. The song
    /// panel shows its own bar inside it (`showsPanelBar`).
    public var showsBar: Bool {
        guard nowPlayingBar, current != nil else { return false }
        switch top.screen {
        case .main, .playlists, .albums, .tracks, .settings: return true
        default: return false
        }
    }

    /// Cover Flow's song panel shows the bar inside its bottom edge (change 112).
    public var showsPanelBar: Bool { nowPlayingBar && current != nil }

    /// The warning (change 233) may open now: on the main screens, signed in, after setup. It
    /// waits while a list loads, because a load ends only on its own frame.
    var canWarnBeta: Bool {
        signedIn && stack.first?.screen == .main && !top.loading && top.screen != .spotifyApp && top.screen != .betaSoon
    }

    /// When `.tick` must next look at the beta: the warning, or the end. 0 when nothing is due.
    /// Like every deadline that `.tick` ends, the app's ticker must check it.
    public var betaDue: Double {
        guard let beta, top.screen != .betaEnded else { return 0 }
        return betaWarned != beta.signed && canWarnBeta ? beta.warnsAt : beta.endsAt
    }

    /// The Cover Flow frame, while Cover Flow or its song panel shows. Its `sel` is the album
    /// in the middle, also while the panel shows the album's songs.
    public var coverFlowFrame: Frame? {
        switch top.screen {
        case .coverFlow, .albumPanel: stack.last { $0.screen == .coverFlow }
        default: nil
        }
    }

    /// The song panel's cover can fly to Now Playing and back (card AH): only when Now Playing
    /// shows the cover and Clasify is online.
    public var canFly: Bool { albumArt != .off && !offline }

    /// Now Playing over Cover Flow's song panel, reached by the cover's flight (card AH). Only
    /// while the panel's album plays: after a failed load brings back another track, Now
    /// Playing shows that track's cover, so no panel cover may fly back.
    public var nowOverPanel: Bool {
        guard canFly, top.screen == .now, stack.count >= 2, case .albumPanel(let album) = stack[stack.count - 2].screen else {
            return false
        }
        return current?.playlist == album
    }

    /// The list rows that show at once: `visibleRows`, or `trackRows` for the taller two-line
    /// song rows. With the bar, one-line lists show one row less (change 111), and the song
    /// rows get shorter instead. The song panel's bar takes a row of the panel.
    public var shownRows: Int {
        switch top.screen {
        case .tracks, .albums: return trackRows  // two-line rows
        case .albumPanel: return showsPanelBar ? panelRows - 1 : panelRows
        default: return showsBar ? visibleRows - 1 : visibleRows
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
    /// - Playlists: albums from the playlists already read, or `albumsList` until one is read.
    /// - Liked Songs, Shuffle Songs and Settings: albums from `albumsList` (Liked Songs on
    ///   Spotify, the library on Apple Music), which setup reads.
    /// - A playlist on the Playlists screen: albums from that playlist. Until its tracks are
    ///   read, or when the read failed or has no covers, the covers that show stay.
    /// - An album on the Albums screen: that album's cover.
    /// Up to `mainArtCount` albums, each cover once, in a random order that `artSeed` sets.
    /// With none of these, the playing track's cover. Tracks with no cover are left out.
    public mutating func refreshArt() {
        let playing = current.flatMap { track($0) }.flatMap { $0.coverID == nil ? nil : $0 }
        let liked = tracks(in: albumsList)
        var pool: [Track]
        switch artRow {
        case .playlist(let id)?, .album(let id)?:
            let known = Album.isID(id) || isLoaded(.tracks(playlist: id))  // an album has its liked songs before a read
            let picks = Self.albums(known ? tracks(in: id) : [], seed: artSeed, count: mainArtCount)
            if !picks.isEmpty { mainArt = picks }
            return
        case .nowPlaying?:
            pool = []
        case .playlists?:
            pool = library.filter { !Playlist.isHidden($0.id) && loadedTracks.contains($0.id) }
                .flatMap(\.tracks)
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
    /// of them is a half screen and the other is not. `fly` is false when the cover cannot fly
    /// to Now Playing (`canFly`): then that change pushes.
    public static func move(between a: Screen, and b: Screen, whole: Bool, fly: Bool = true) -> NavMove {
        func isPanel(_ s: Screen) -> Bool { if case .albumPanel = s { true } else { false } }
        func either(_ x: (Screen) -> Bool, _ y: (Screen) -> Bool) -> Bool { (x(a) && y(b)) || (y(a) && x(b)) }
        if whole && either({ $0 == .main }, { $0 == .coverFlow }) { return .doors }
        if either({ $0 == .coverFlow }, isPanel) { return .flip }
        if fly && either(isPanel, { $0 == .now }) { return .fly }
        return .push
    }

    /// The screen's list is already in the state, so it opens without a read.
    public func isLoaded(_ screen: Screen) -> Bool {
        switch screen {
        case .playlists: playlistsLoaded
        case .artists: artistsLoaded
        case .tracks(let id), .albumPanel(let id): loadedTracks.contains(id)
        case .albums, .coverFlow, .yourMusic: loadedTracks.contains(albumsList)
        default: true
        }
    }

    /// The `readAt` key of a list screen: the playlist ID that it reads, or "" for the playlist list.
    /// `albums` is the list that Albums, Cover Flow and setup read (`albumsList`).
    public static func readKey(_ screen: Screen, albums: String = Playlist.likedSongsID) -> String {
        switch screen {
        case .tracks(let id), .albumPanel(let id): id  // an album reads all its songs (CLA-46)
        case .albums, .coverFlow, .yourMusic: albums  // setup reads it first
        default: ""
        }
    }
    /// The `readAt` key of a list screen on the active service.
    public func readKey(_ screen: Screen) -> String { Self.readKey(screen, albums: albumsList) }

    /// A playlist's tracks. For an album ID, all songs of the album in album order, once read
    /// (CLA-46). Before that, its songs in Liked Songs in disc and track order, so the album's
    /// cover and a playing song from it can show.
    public func tracks(in playlist: String) -> [Track] {
        if let list = library.first(where: { $0.id == playlist }) { return list.tracks }
        guard Album.isID(playlist) else { return [] }
        return Album.songs(playlist, in: tracks(in: albumsList))
    }

    /// An album in Liked Songs, by its URI, with the artist as `albums` gives it. When its last
    /// song left Liked Songs, the album from its read songs (CLA-49), or of a kept track (such
    /// as the playing one), so the title bar, the song panel and Now Playing keep its name.
    public func album(_ id: String) -> Album? {
        let read = Album.isID(id) ? library.first(where: { $0.id == id })?.tracks : nil
        let track = tracks(in: albumsList).first { $0.album?.id == id }
            ?? read?.first { $0.album?.id == id } ?? extraTracks.first { $0.album?.id == id }
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
        for track in tracks(in: albumsList) {
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

    /// The name of a song list for its title bar and its row: a playlist, the liked list,
    /// "Songs" (card BN) or an artist. Nil for an unknown ID.
    public func listName(_ id: String) -> String? {
        if id == Playlist.likedSongsID { return likedSongsName }
        if id == Playlist.songsID { return "Songs" }
        if Playlist.isArtistID(id) { return artists.first { $0.id == id }?.name }
        return library.first { $0.id == id }?.name
    }

    /// The track in its playlist, else in `extraTracks`.
    public func track(_ ref: TrackRef) -> Track? {
        tracks(in: ref.playlist).first { $0.id == ref.track } ?? extraTracks.first { $0.id == ref.track }
    }

    public func rows(for frame: Frame) -> [Row] {
        switch frame.screen {
        case .login: restoring ? [] : [.logIn]
        case .main:
            (current == nil ? [] : [.nowPlaying])
                + (words.libraryRows
                    ? [.coverFlow, .playlists, .artists, .albums, .songs, .shuffleSongs, .settings]  // card BN
                    : [.coverFlow, .playlists, .albums, .likedSongs, .shuffleSongs, .settings])
        case .playlists:
            (words.libraryRows ? [.playlist(Playlist.likedSongsID)] : [])  // card BN: Favorite Songs first
                + library.filter { !Playlist.isHidden($0.id) }.map { .playlist($0.id) }
        case .artists: artists.map { .artist($0.id) }
        case .albums, .coverFlow: albums.map { .album($0.id) }
        case .tracks(let pl), .albumPanel(let pl): tracks(in: pl).map { .track($0.id) }
        // No Skin row: 1.0 has only the Pocket skin. Dark and Aqua come later (design doc).
        case .settings: [.service, .shuffle, .repeatMode, .albumArt, .deviceColor, .clicker, .nowPlayingBar, .about, .logOut]
        case .confirm: [.cancel, .confirmLogOut]
        case .color: DeviceColor.allCases.map { .color($0) }
        case .auth: [.openBrowser, .cancel]
        case .loginFailed: [.tryAgain, .cancel]
        case .spotifyApp: [.getSpotifyApp]
        // Card BM, change 259: Apple Music has "Use Spotify" in place of "Log out".
        case .premium: [.checkPremium, .getPremium, service == .spotify ? .premiumLogOut : .useSpotify]
        case .pickMusic: MusicService.allCases.map { .pickService($0) }
        case .accessOff: [.openPrivacy, .useSpotify]
        case .betaSoon: [.getNewBeta, .later]
        case .betaEnded: [.getNewBeta, .quit]
        case .licenses: License.all.indices.map { .license($0) }
        case .about, .now, .hello, .yourMusic, .loggedIn, .license: []
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
        for track in tracks(in: albumsList) {
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

/// A first-time hint (Round 14 card BA). Each shows once in Clasify's life.
public enum Hint: String, CaseIterable, Sendable {
    /// Change 139: on the first list opened from the main menu, until the first MENU press.
    case menu
    /// Change 176: on Now Playing, after the first song played 10 s, until the first play/pause press.
    case playPause
    /// Change 177: after the play/pause hint, on a later visit to Now Playing, until the first next press.
    case next
    /// The first-run hints (card BA.2, change 238), a queue after the first setup: Play on the
    /// main menu, then Previous or Next on Now Playing, then MENU. In `hintsDone`: that step is
    /// done. Other input only hides the hint (see `AppState.tour`).
    case tourPlay = "tour.play", tourNext = "tour.next", tourMenu = "tour.menu"

    public var isTour: Bool { self == .tourPlay || self == .tourNext || self == .tourMenu }
}

extension Track {
    /// The Songs list's order (card BN): by title in `Playlist.nameOrder`; equal titles keep
    /// their order. The `Library` gives `Playlist.songsID` in this order, so the list and the
    /// player's queue match.
    public static func titleOrder(_ tracks: [Track]) -> [Track] {
        tracks.enumerated().sorted { a, b in
            let (x, y) = (a.element.title, b.element.title)
            if Playlist.nameOrder(x, y) { return true }
            if Playlist.nameOrder(y, x) { return false }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// One artist's songs (card BN): by album name in `Playlist.nameOrder`, then disc, then
    /// track number; songs with no number keep their order after the numbered ones.
    public static func artistOrder(_ tracks: [Track]) -> [Track] {
        tracks.enumerated().sorted { a, b in
            let (x, y) = (a.element.album?.name ?? "", b.element.album?.name ?? "")
            if Playlist.nameOrder(x, y) { return true }
            if Playlist.nameOrder(y, x) { return false }
            let ka = (a.element.disc ?? 1, a.element.number ?? Int.max, a.offset)
            let kb = (b.element.disc ?? 1, b.element.number ?? Int.max, b.offset)
            return ka < kb
        }.map(\.element)
    }
}
