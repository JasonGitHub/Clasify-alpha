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

    /// `text` folded, in one Unicode form (NFC), as UTF-8 bytes: the same letters give the
    /// same bytes, so a byte search finds what a text search finds.
    static func bytes(_ text: String) -> [UInt8] { Array(fold(text).precomposedStringWithCanonicalMapping.utf8) }

    /// Folded text as bytes, with the byte offsets where its letters (`Character`s) start and
    /// end. A match must start and end there, as in a text search: "क" is not in "क्ष", which
    /// is one letter (Codex on #465).
    struct Text: Equatable, Sendable {
        var bytes: [UInt8]
        /// `edges[i]`: a letter starts at byte `i` (`edges.count == bytes.count + 1`). nil when
        /// every byte is a letter of its own: ASCII text, the most common case, needs no array.
        var edges: [Bool]?
        /// Where each word starts: at a letter or digit after a space, a mark or the start.
        var starts: [Int]

        init(_ text: String) {
            let folded = fold(text).precomposedStringWithCanonicalMapping
            bytes = Array(folded.utf8)
            var starts: [Int] = [], wordBefore = false
            // In ASCII each byte is one letter, except CR LF, which never comes in a name.
            if bytes.allSatisfy({ $0 < 0x80 }) && !bytes.contains(13) {
                edges = nil
                for (i, byte) in bytes.enumerated() {
                    let inWord = (byte >= 0x30 && byte <= 0x39) || (byte >= 0x61 && byte <= 0x7A) || (byte >= 0x41 && byte <= 0x5A)
                    if inWord && !wordBefore { starts.append(i) }
                    wordBefore = inWord
                }
            } else {
                var edges = [Bool](repeating: false, count: bytes.count + 1), at = 0
                for letter in folded {
                    edges[at] = true
                    // Unicode letter and number properties: "—" and "・" end a word too.
                    let inWord = letter.isLetter || letter.isNumber
                    if inWord && !wordBefore { starts.append(at) }
                    wordBefore = inWord
                    at += letter.utf8.count
                }
                edges[at] = true
                self.edges = edges
            }
            self.starts = starts
        }

        /// A match of `count` bytes at `offset` starts and ends on a letter edge.
        func whole(_ offset: Int, _ count: Int) -> Bool {
            guard let edges else { return true }
            return edges[offset] && edges[offset + count]
        }

        /// `needle` is in the text, on letter edges. An empty needle is in every text. It runs
        /// on each key for each row, so it works on raw bytes, with `memchr` for the first byte
        /// and `memcmp` for the rest.
        func find(_ needle: [UInt8]) -> Bool {
            guard !needle.isEmpty else { return true }
            guard needle.count <= bytes.count else { return false }
            let edges = edges
            return bytes.withUnsafeBufferPointer { h in
                needle.withUnsafeBufferPointer { n in
                    guard let hBase = h.baseAddress, let nBase = n.baseAddress else { return false }
                    let first = Int32(n[0]), end = hBase + (h.count - n.count + 1)
                    var at = hBase
                    while at < end, let hit = memchr(at, first, end - at) {
                        let p = UnsafePointer(hit.assumingMemoryBound(to: UInt8.self))
                        if memcmp(p, nBase, n.count) == 0, edges.map({ $0[p - hBase] && $0[p - hBase + n.count] }) ?? true { return true }
                        at = p + 1
                    }
                    return false
                }
            }
        }

        /// The text has `needle` at `offset`, on letter edges.
        func has(_ needle: [UInt8], at offset: Int) -> Bool {
            guard !needle.isEmpty else { return true }
            guard offset + needle.count <= bytes.count, whole(offset, needle.count) else { return false }
            return bytes.withUnsafeBufferPointer { h in
                needle.withUnsafeBufferPointer { n in memcmp(h.baseAddress! + offset, n.baseAddress!, n.count) == 0 }
            }
        }
    }

    /// The results for `query`. The query is split at spaces, and each word must be found
    /// anywhere in the name, or for a song or an album in its artist names (Jason's test of
    /// build 458: "green day" found nothing). Inside each kind the better matches come first
    /// (`Index.Entry.rank`), then name order. More spaces change nothing; an empty query has no
    /// results. For each key while Search is open, keep an `Index` instead.
    public static func results(_ query: String, in state: AppState) -> [Result] {
        Index(state).results(query)
    }

    /// The library's names, folded and in result order once, so each key only compares
    /// (CTO on #451: typing must stay fast on 10,000 songs). Make it when Search opens and
    /// again when library data arrives.
    public struct Index: Equatable, Sendable {
        struct Entry: Equatable, Sendable {
            var result: Result
            /// The folded name and, for a song or an album, its folded artist names (empty for
            /// the other kinds), as UTF-8 bytes: each key compares bytes, which is much faster
            /// than `String` search on a large library (CTO on #461: 20,000 songs).
            var name: Text, artist: Text
            /// Where the name starts past a leading "The", for the rank of a match.
            var bare: Int
            init(_ result: Result, artist: String? = nil) {
                self.result = result
                name = Text(result.name); self.artist = Text(artist ?? "")
                bare = name.bytes.starts(with: Array("the ".utf8)) && name.bytes.count > 4 ? 4 : 0
            }

            /// Where a match ranks in its kind (Jason's test of build 458: "t" showed "39 Minutes"
            /// first), nil for no match: 0 the name starts with the query, also past a leading
            /// "The"; 1 a word of the name starts with it; 2 each word is in the name; 3 a word
            /// is only in the artist names. `phrase` is the words with one space between them.
            func rank(_ words: [[UInt8]], phrase: [UInt8]) -> Int? {
                var byArtist = false
                for word in words where !name.find(word) {
                    guard artist.find(word) else { return nil }
                    byArtist = true
                }
                if byArtist { return 3 }
                if name.has(phrase, at: 0) || name.has(phrase, at: bare) { return 0 }
                return name.starts.contains { name.has(phrase, at: $0) } ? 1 : 2
            }
        }
        /// Each kind in its result order: by name in `Playlist.nameOrder`, as the library lists
        /// sort (a leading "The" does not count), so the limit keeps the first names.
        var artists: [Entry], albums: [Entry], playlists: [Entry], songs: [Entry]

        public init(_ state: AppState) {
            artists = Self.byName(state.artists.map { Entry(Result(kind: .artist, id: $0.id, name: $0.name, detail: "Artist")) })
            albums = Self.byName(state.albums.map {
                Entry(Result(kind: .album, id: $0.id, name: $0.name, detail: $0.artist.map { "Album · \($0)" } ?? "Album"), artist: $0.artist)
            })
            playlists = Self.byName(state.library.filter { !Playlist.isHidden($0.id) }.map {
                Entry(Result(kind: .playlist, id: $0.id, name: $0.name, detail: "Playlist · \($0.trackCount) \($0.trackCount == 1 ? "song" : "songs")"))
            })
            songs = Search.songs(in: state).map { Entry($0.result, artist: $0.artist) }  // already in this order
        }

        /// `entries` in `Playlist.nameOrder`. Equal names keep their order.
        static func byName(_ entries: [Entry]) -> [Entry] {
            entries.enumerated().sorted {
                if Playlist.nameOrder($0.element.result.name, $1.element.result.name) { return true }
                if Playlist.nameOrder($1.element.result.name, $0.element.result.name) { return false }
                return $0.offset < $1.offset
            }.map(\.element)
        }

        public func results(_ query: String) -> [Result] {
            let split = fold(query).split(whereSeparator: \.isWhitespace)
            guard !split.isEmpty else { return [] }
            let words = split.map { Search.bytes(String($0)) }, phrase = Search.bytes(split.joined(separator: " "))
            var found: [Result] = []
            for kind in [artists, albums, playlists, songs] {
                // Each kind is in name order, so each rank keeps it. Once rank 0 has `limit`
                // rows, no later row can come in.
                var ranks: [[Result]] = [[], [], [], []]
                for entry in kind {
                    guard let rank = entry.rank(words, phrase: phrase), ranks[rank].count < limit else { continue }
                    ranks[rank].append(entry.result)
                    if rank == 0 && ranks[0].count == limit { break }
                }
                found += ranks.joined().prefix(limit)
            }
            return found
        }
    }

    /// Every song of the lists read so far, each once, in the Songs list's title order, with
    /// its artist names. A song that can't be found on this Mac (card CR) is left out.
    static func songs(in state: AppState) -> [(result: Result, artist: String)] {
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
            let result = Result(
                kind: .song, id: track.id, name: track.title,
                detail: track.artist.isEmpty ? "Song" : "Song · \(track.artist)", list: plays)
            return (result, track.artist)
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
