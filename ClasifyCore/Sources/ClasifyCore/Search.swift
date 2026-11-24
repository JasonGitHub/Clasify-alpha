import Foundation

/// CLA-183, card CS: Search on the device. It finds names in the active service's library that
/// the app has read (never the catalog): artists, albums, playlists and songs, in that order.
/// Pure: the skins and the reducer only show and open what it gives.
public enum Search {
    public enum Kind: Equatable, Sendable { case artist, album, playlist, song }

    /// One result row: what it shows and what opening it needs.
    public struct Result: Equatable, Sendable {
        public var kind: Kind
        /// The artist, album, playlist or song ID.
        public var id: String
        public var name: String
        /// The row's second line, such as "Album · Mara Kei".
        public var detail: String
        /// For a song, the list it plays in. nil for the other kinds.
        public var list: String?

        public init(kind: Kind, id: String, name: String, detail: String, list: String? = nil) {
            self.kind = kind; self.id = id; self.name = name; self.detail = detail; self.list = list
        }
    }

    /// The most results of one kind, so typing stays fast in a large library and the wheel
    /// still reaches the other kinds.
    public static let limit = 50

    /// The text as matching sees it: no case, no accents, no full-width forms.
    public static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// The results for `query`, anywhere in the name. Spaces around the query are left out; an
    /// empty query has no results. For each key while Search is open, keep an `Index` instead.
    public static func results(_ query: String, in state: AppState) -> [Result] {
        Index(state).results(query)
    }

    /// The library's names, folded and in result order once, so each key only compares
    /// (CTO on #451: typing must stay fast on 10,000 songs). Make it when Search opens and
    /// again when library data arrives.
    public struct Index: Equatable, Sendable {
        struct Entry: Equatable, Sendable {
            var result: Result, folded: String
            init(_ result: Result) { self.result = result; folded = Search.fold(result.name) }
        }
        /// Each kind in its result order.
        var artists: [Entry], albums: [Entry], playlists: [Entry], songs: [Entry]

        public init(_ state: AppState) {
            artists = state.artists.map { Entry(Result(kind: .artist, id: $0.id, name: $0.name, detail: "Artist")) }
            albums = state.albums.map {
                Entry(Result(kind: .album, id: $0.id, name: $0.name, detail: $0.artist.map { "Album · \($0)" } ?? "Album"))
            }
            playlists = state.library.filter { !Playlist.isHidden($0.id) }.map {
                Entry(Result(kind: .playlist, id: $0.id, name: $0.name, detail: "Playlist · \($0.trackCount) \($0.trackCount == 1 ? "song" : "songs")"))
            }
            songs = Search.songs(in: state).map(Entry.init)
        }

        public func results(_ query: String) -> [Result] {
            let q = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !q.isEmpty else { return [] }
            var found: [Result] = []
            for kind in [artists, albums, playlists, songs] {
                found += kind.lazy.filter { $0.folded.contains(q) }.prefix(limit).map(\.result)
            }
            return found
        }
    }

    /// Every song of the lists read so far, each once, in the Songs list's title order. A song
    /// that can't be found on this Mac (card CR) is left out.
    static func songs(in state: AppState) -> [Result] {
        var found: [String: (track: Track, list: String, rank: Int, order: Int)] = [:]
        for list in state.library {
            let rank = playRank(list.id)
            for track in list.tracks where !track.missing {
                if let had = found[track.id] {
                    if rank < had.rank { found[track.id] = (had.track, list.id, rank, had.order) }
                } else {
                    found[track.id] = (track, list.id, rank, found.count)
                }
            }
        }
        let sorted = found.values
            .map { (key: Album.SortKey(Playlist.dropThe($0.track.title)), song: $0) }
            .sorted { ($0.key, $0.song.order) < ($1.key, $1.song.order) }
        return sorted.map { entry in
            let (track, list) = (entry.song.track, entry.song.list)
            // The whole library is never a play context: its songs play in their album.
            let plays = list == Playlist.libraryID ? track.album?.id ?? list : list
            return Result(
                kind: .song, id: track.id, name: track.title,
                detail: track.artist.isEmpty ? "Song" : "Song · \(track.artist)", list: plays)
        }
    }

    /// The list a song found in several lists plays in: the library's Songs list, then the
    /// liked list, then the first playlist, then an album or artist, the whole library last.
    static func playRank(_ id: String) -> Int {
        if id == Playlist.songsID { return 0 }
        if id == Playlist.likedSongsID { return 1 }
        if !Playlist.isHidden(id) { return 2 }
        return id == Playlist.libraryID ? 4 : 3
    }
}
