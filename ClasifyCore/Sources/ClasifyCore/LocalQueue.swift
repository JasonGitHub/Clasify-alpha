import Foundation

/// CLA-179: one local song that the local player can open: its ID ("local:track:<persistent ID hex>")
/// and the address of its file. The words and the length come from the library read, for the
/// Mac's Now Playing (CLA-179).
public struct LocalItem: Sendable, Equatable {
    public var id: String
    public var url: URL
    /// Empty when the library gives none.
    public var title: String, artist: String, album: String
    /// Seconds. 0 when the library gives none.
    public var duration: Double
    /// The song's library cover (`LibraryCover`), read in memory only. nil when it has none.
    public var coverID: String?

    public init(
        id: String, url: URL, title: String = "", artist: String = "", album: String = "", duration: Double = 0,
        coverID: String? = nil
    ) {
        self.id = id; self.url = url
        self.title = title; self.artist = artist; self.album = album; self.duration = duration; self.coverID = coverID
    }
}

/// CLA-179: where the local player gets the songs of a load. The local library conforms.
@MainActor
public protocol LocalSource: AnyObject {
    /// The songs of `context` in their order, to play from `track`: a playlist ("local:playlist:<hex>"),
    /// `Playlist.libraryID` (all songs), or nil (the song alone). Only songs that can play.
    /// nil when the context or the song is unknown.
    func items(context: String?, track: String) async -> [LocalItem]?
}

/// CLA-179: the play order of one local context. Spotify and Apple Music order their own queues;
/// for local songs this does it. A plain value: it holds indexes into the context's songs, never
/// the songs. `next`, `prev` and `trackEnded` answer the index to play, or nil at the end.
public struct LocalQueue: Sendable, Equatable {
    /// How many songs the context has.
    public let count: Int
    /// The play order: indexes into the context's songs. In order, or shuffled with the
    /// song that was playing first.
    public private(set) var order: [Int]
    /// Where in `order` the current song is.
    public private(set) var position: Int
    public private(set) var shuffle: Bool
    public var repeatMode: RepeatMode

    /// The index of the song that plays now, or nil when the context has no songs.
    public var current: Int? { order.isEmpty ? nil : order[position] }

    /// Starts at the song at `start`. With no start, the first song; in shuffle, a random one
    /// (Shuffle Songs).
    public init(count: Int, start: Int?, shuffle: Bool, repeatMode: RepeatMode,
                using random: inout some RandomNumberGenerator) {
        let n = max(0, count)
        self.count = n
        self.shuffle = shuffle
        self.repeatMode = repeatMode
        guard n > 0 else {
            order = []
            position = 0
            return
        }
        let first: Int
        if let start, (0..<n).contains(start) {
            first = start
        } else {
            first = shuffle ? Int.random(in: 0..<n, using: &random) : 0
        }
        order = shuffle ? Self.shuffled(count: n, first: first, using: &random) : Array(0..<n)
        position = shuffle ? 0 : first
    }

    public init(count: Int, start: Int?, shuffle: Bool, repeatMode: RepeatMode) {
        var random = SystemRandomNumberGenerator()
        self.init(count: count, start: start, shuffle: shuffle, repeatMode: repeatMode, using: &random)
    }

    /// Next, pressed: the next song, also with Repeat One. After the last song: the first with
    /// Repeat All, else nil (the end of the context).
    public mutating func next() -> Int? {
        guard !order.isEmpty else { return nil }
        if position + 1 < order.count {
            position += 1
        } else if repeatMode == .all {
            position = 0
        } else {
            return nil
        }
        return current
    }

    /// Previous, pressed: the song before. On the first song: the last with Repeat All, else
    /// the first song again.
    public mutating func prev() -> Int? {
        guard !order.isEmpty else { return nil }
        if position > 0 {
            position -= 1
        } else if repeatMode == .all {
            position = order.count - 1
        }
        return current
    }

    /// The song ended by itself: the same song with Repeat One, else as Next.
    public mutating func trackEnded() -> Int? {
        guard !order.isEmpty else { return nil }
        return repeatMode == .one ? current : next()
    }

    /// Shuffle on: the current song stays and comes first, the others follow in a random order.
    /// Off: the context's own order, at the current song.
    public mutating func setShuffle(_ on: Bool, using random: inout some RandomNumberGenerator) {
        guard on != shuffle else { return }
        shuffle = on
        guard let now = current else { return }
        if on {
            order = Self.shuffled(count: count, first: now, using: &random)
            position = 0
        } else {
            order = Array(0..<count)
            position = now
        }
    }

    public mutating func setShuffle(_ on: Bool) {
        var random = SystemRandomNumberGenerator()
        setShuffle(on, using: &random)
    }

    private static func shuffled(count: Int, first: Int, using random: inout some RandomNumberGenerator) -> [Int] {
        [first] + (0..<count).filter { $0 != first }.shuffled(using: &random)
    }
}
