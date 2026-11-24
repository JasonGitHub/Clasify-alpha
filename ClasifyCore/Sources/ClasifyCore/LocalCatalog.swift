/// Local music (CLA-179): the songs and playlists of the Music app library, read by the app with
/// Apple's iTunesLibrary framework and kept here as plain values. This file only maps and sorts,
/// so the rules are tested on Linux. Read-only, in memory only.

/// The store IDs of local items: "local:track:<persistent ID in hex>", "local:playlist:<hex>",
/// "local:album:<hex>" and "local:artist:<name>". No other service's ID starts with "local:".
public enum LocalID {
    public static let trackPrefix = "local:track:"
    public static let playlistPrefix = "local:playlist:"
    public static let albumPrefix = "local:album:"
    public static let artistPrefix = "local:artist:"

    public static func track(_ persistentID: UInt64) -> String { trackPrefix + String(persistentID, radix: 16) }
    public static func playlist(_ persistentID: UInt64) -> String { playlistPrefix + String(persistentID, radix: 16) }
    public static func album(_ persistentID: UInt64) -> String { albumPrefix + String(persistentID, radix: 16) }
    public static func artist(_ name: String) -> String { artistPrefix + name }

    /// The persistent ID in a store ID with this prefix, or nil.
    public static func persistentID(_ id: String, prefix: String) -> UInt64? {
        guard id.hasPrefix(prefix) else { return nil }
        return UInt64(id.dropFirst(prefix.count), radix: 16)
    }
}

/// One song of the Music app library, as the app read it.
public struct LocalItem: Equatable, Sendable {
    public var persistentID: UInt64
    public var title: String
    public var artist: String
    /// The album's title, its persistent ID and its album artist. An empty title: no album.
    public var album: String, albumID: UInt64, albumArtist: String?
    public var disc: Int?, number: Int?
    /// Seconds.
    public var duration: Double
    /// The library item has a cover that `AppleMusicArt` can read.
    public var hasCover: Bool
    /// A song in a local file that can play: not protected, not a video, not in the cloud only.
    public var playable: Bool

    public init(
        persistentID: UInt64, title: String, artist: String, album: String, albumID: UInt64, albumArtist: String? = nil,
        disc: Int? = nil, number: Int? = nil, duration: Double, hasCover: Bool, playable: Bool
    ) {
        self.persistentID = persistentID; self.title = title; self.artist = artist
        self.album = album; self.albumID = albumID; self.albumArtist = albumArtist.flatMap { $0.isEmpty ? nil : $0 }
        self.disc = disc; self.number = number; self.duration = duration; self.hasCover = hasCover; self.playable = playable
    }
}

/// One user playlist of the Music app library: its songs in order, by persistent ID.
public struct LocalList: Equatable, Sendable {
    public var persistentID: UInt64
    public var name: String
    public var items: [UInt64]

    public init(persistentID: UInt64, name: String, items: [UInt64]) {
        self.persistentID = persistentID; self.name = name; self.items = items
    }
}

/// The lists that the `Library` answers for local music, made once from one library read.
public struct LocalCatalog: Sendable {
    /// `Playlist.libraryID`: every song that can play, grouped by album (albums by name, songs
    /// in disc and track order), each carrying its album. A song with no album title has no
    /// album: it shows in Songs and Artists, not in Albums.
    public let library: [Track]
    /// The user playlists that still have a song after the hidden songs leave, in library order.
    public let playlists: [Playlist]
    /// The artists, in `Playlist.nameOrder`: every artist and album artist of `library`.
    public let artists: [Playlist]
    private let lists: [String: [Track]]
    private let byID: [String: Track]

    public init(items: [LocalItem], lists: [LocalList]) {
        let tracks = items.filter(\.playable).map { Self.track(from: $0) }
        let byID = Dictionary(tracks.map { ($0.id, $0) }) { first, _ in first }
        self.byID = byID
        // Albums by name, then songs in disc and track order; songs with no album last.
        var albums: [String: (album: Album, songs: [Track])] = [:]
        var loose: [Track] = []
        for track in tracks {
            guard let album = track.album else { loose.append(track); continue }
            albums[album.id, default: (album, [])].songs.append(track)
        }
        let ordered = albums.values.sorted {
            let (a, b) = (Album.SortKey($0.album.name), Album.SortKey($1.album.name))
            return a < b || (!(b < a) && $0.album.id < $1.album.id)
        }
        library = ordered.flatMap { Album.songs($0.album.id, in: $0.songs) } + loose
        var playlists: [Playlist] = [], kept: [String: [Track]] = [:]
        for list in lists {
            let songs = list.items.compactMap { byID[LocalID.track($0)] }
            guard !songs.isEmpty else { continue }
            let id = LocalID.playlist(list.persistentID)
            playlists.append(Playlist(id: id, name: list.name, tracks: [], trackCount: songs.count))
            kept[id] = songs
        }
        self.playlists = playlists
        self.lists = kept
        var names = Set<String>()
        for track in library {
            if !track.artist.isEmpty { names.insert(track.artist) }
            if let artist = track.album?.artist { names.insert(artist) }
        }
        artists = names.sorted(by: Playlist.nameOrder).map { Playlist(id: LocalID.artist($0), name: $0, tracks: []) }
    }

    /// The songs of a list: the library, all songs, an album, an artist or a playlist. Liked
    /// Songs is empty: the Music app library gives no list of favorites here. nil for an
    /// unknown ID.
    public func tracks(of id: String) -> [Track]? {
        switch id {
        case Playlist.libraryID: return library
        case Playlist.songsID: return Track.titleOrder(library)
        case Playlist.likedSongsID: return []
        default: break
        }
        if id.hasPrefix(LocalID.albumPrefix) { return Album.songs(id, in: library) }
        if id.hasPrefix(LocalID.artistPrefix) {
            let name = String(id.dropFirst(LocalID.artistPrefix.count))
            return Track.artistOrder(library.filter { $0.artist == name || $0.album?.artist == name })
        }
        return lists[id]
    }

    /// One song that can play, by its store ID.
    public func track(_ id: String) -> Track? { byID[id] }

    /// The store `Track` of a song. Its album's artist is the album artist, else the song's
    /// artist. Covers come from the library item (`LibraryCover`), as for Apple Music.
    static func track(from item: LocalItem) -> Track {
        let album = item.album.isEmpty ? nil : Album(
            id: LocalID.album(item.albumID == 0 ? item.persistentID : item.albumID), name: item.album,
            artist: item.albumArtist ?? item.artist)
        return Track(
            id: LocalID.track(item.persistentID), title: item.title, artist: item.artist, duration: item.duration,
            coverID: item.hasCover ? LibraryCover.coverID(persistentID: item.persistentID, side: 300) : nil,
            album: album, disc: item.disc, number: item.number,
            largeCoverID: item.hasCover ? LibraryCover.coverID(persistentID: item.persistentID, side: 640) : nil)
    }
}

extension LibraryWords {
    /// Local music's words. Placeholders until the design card names them (CLA-179).
    public static let local = LibraryWords(
        likedSongs: "Favorite Songs", service: "Music Library", like: "Favorite",
        needPlan: "Can’t play", needPlanLine: "These songs can’t play here.",
        getPlan: "Open Music", noPlan: "No songs",
        albumsList: Playlist.libraryID, oneSong: "song", manySongs: "songs", libraryRows: true)
}
