/// CLA-195: Spotify's Artists screen, made from Liked Songs with no read of its own. Each
/// artist of a liked song is a row, so a song with several artists shows under each of them.
public enum SpotifyArtists {
    /// The artists of `liked`, each once by ID, with the name of its first song. In the
    /// `Library`'s own order; the reducer puts them in `Playlist.nameOrder`.
    public static func list(_ liked: [Track]) -> [Playlist] {
        var seen = Set<String>(), list: [Playlist] = []
        for artist in liked.lazy.flatMap(\.artists) where Playlist.isArtistID(artist.id) && !artist.name.isEmpty {
            if seen.insert(artist.id).inserted { list.append(Playlist(id: artist.id, name: artist.name, tracks: [])) }
        }
        return list
    }

    /// What an artist's screen shows: its Popular songs from Spotify (`popular`, in Spotify's
    /// order) when they were read and are not empty, else its liked songs. `popular` is nil
    /// when the `artists.popular` switch is off or the read failed (offline too): then the
    /// screen shows the liked songs, with no error. Nil only when neither list is known.
    public static func shown(_ id: String, popular: [Track]?, liked: [Track]?) -> [Track]? {
        if let popular, !popular.isEmpty { return popular }
        return liked.map { songs(of: id, in: $0) }
    }

    /// The liked songs of one artist, in `Track.artistOrder`.
    public static func songs(of id: String, in liked: [Track]) -> [Track] {
        Track.artistOrder(liked.filter { $0.artists.contains { $0.id == id } })
    }
}
