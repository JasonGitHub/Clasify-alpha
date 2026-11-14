/// The keys that can name one song in a player's queue, strongest first (Apple Music, CLA-103):
/// its IDs (library and catalog), its ISRC, and last its title with its artist.
public struct SongKeys: Sendable, Equatable {
    public var ids: [String]
    public var isrc: String?
    public var title: String
    public var artist: String

    public init(ids: [String], isrc: String? = nil, title: String, artist: String) {
        self.ids = ids; self.isrc = isrc; self.title = title; self.artist = artist
    }

    /// Title with artist stays the last key: two songs can share it.
    var ordered: [String] {
        ids.map { "id:" + $0 } + (isrc.map { ["isrc:" + $0] } ?? []) + [Self.name(title, artist)]
    }

    static func name(_ title: String, _ artist: String) -> String { "name:" + title + "\u{1F}" + artist }
}

/// Finds the store ID of the queued song that a player entry plays. A queue entry can carry
/// another ID than the song that was queued (a catalog ID for a library song), so it looks at
/// each key in turn. It never gives an ID that was not queued.
public struct QueueMatch: Sendable {
    private var byKey: [String: String] = [:]

    /// The queued songs with the store IDs that the library gave them. The first song with a
    /// key keeps it.
    public init(_ songs: [(id: String, keys: SongKeys)] = []) {
        for song in songs {
            for key in song.keys.ordered where byKey[key] == nil { byKey[key] = song.id }
        }
    }

    /// The store ID for a resolved entry: the first of its keys, strongest first, that matches.
    public func id(for keys: SongKeys) -> String? {
        keys.ordered.lazy.compactMap { byKey[$0] }.first
    }

    /// The store ID for an entry with no resolved song, by the title and artist that it shows.
    public func id(title: String, artist: String) -> String? {
        byKey[SongKeys.name(title, artist)]
    }
}
