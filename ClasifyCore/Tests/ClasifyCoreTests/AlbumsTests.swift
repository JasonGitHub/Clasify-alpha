import Testing
@testable import ClasifyCore

/// Liked Songs on four albums, in the order the user liked them.
let likedAlbums: [Track] = {
    let nevermind = Album(id: "spotify:album:n", name: "Nevermind", artist: "Nirvana")
    let unplugged = Album(id: "spotify:album:u", name: "MTV Unplugged In New York", artist: "Nirvana")
    let magic = Album(id: "spotify:album:m", name: "Magic")  // no album artist from Spotify
    let numbers = Album(id: "spotify:album:1", name: "1989", artist: "Taylor Swift")
    func song(_ id: String, _ album: Album, disc: Int? = nil, _ number: Int?) -> Track {
        Track(id: id, title: id, artist: "a-\(id)", duration: 200, album: album, disc: disc, number: number)
    }
    return [
        song("u3", unplugged, 3), song("n2", nevermind, 2), song("m1", magic, 1), song("u1", unplugged, 1),
        song("x", nevermind, disc: 2, 1), song("n1", nevermind, 1), song("y", numbers, 4),
        Track(id: "lone", title: "Lone", artist: "z", duration: 100),  // no album: not on the list
    ]
}()

/// Signed in, with Liked Songs read.
func withLikedAlbums() -> AppState {
    var s = mainMenu()
    s.library = [Playlist(id: Playlist.likedSongsID, name: "Liked Songs", tracks: likedAlbums)]
    s.loadedTracks = [Playlist.likedSongsID]
    s.readAt[Playlist.likedSongsID] = 100
    return s
}

@Suite struct AlbumsTests {
    @Test func theMainMenuHasAnAlbumsRowAfterPlaylists() {
        let s = mainMenu()
        #expect(s.rows(for: s.top) == [.coverFlow, .playlists, .albums, .likedSongs, .shuffleSongs, .settings])
    }

    @Test func albumsAreLikedSongsGroupedNumbersFirstThenAToZ() {
        let s = withLikedAlbums()
        #expect(s.albums.map(\.name) == ["1989", "Magic", "MTV Unplugged In New York", "Nevermind"])
        // An album with no album artist takes the artist of its first liked song.
        #expect(s.albums[1].artist == "a-m1" && s.album("spotify:album:m")?.artist == "a-m1")
        #expect(s.albums[3].artist == "Nirvana")
        // Case and accents do not change the order.
        #expect(Album.SortKey("éclair") < Album.SortKey("Fame") && Album.SortKey("#1s") < Album.SortKey("abba"))
    }

    @Test func albumsOpensAtOnceWhenLikedSongsIsRead() {
        var s = withLikedAlbums()
        #expect(send(&s, .wheel(2), .select, now: 150) == [])  // read 50 s ago: no read again
        #expect(s.top.screen == .albums && !s.top.loading && s.isHalf(.albums) && s.shownRows == trackRows)
        #expect(s.rows(for: s.top) == [.album("spotify:album:1"), .album("spotify:album:m"),
                                       .album("spotify:album:u"), .album("spotify:album:n")])
        send(&s, .menu)
        #expect(send(&s, .select, now: 300) == [.refreshTracks(playlist: Playlist.likedSongsID)])  // stale: read again
    }

    @Test func albumsLoadsLikedSongsFirst() {
        var s = mainMenu()
        #expect(send(&s, .wheel(2), .select) == [.fetchTracks(token: 1, playlist: Playlist.likedSongsID)])
        #expect(s.top.screen == .albums && s.top.loading)
        send(&s, .tracksLoaded(token: 1, playlist: Playlist.likedSongsID, tracks: likedAlbums))
        #expect(!s.top.loading && s.rows(for: s.top).count == 4)
    }

    /// All songs of Nevermind, as Spotify reads the album: "n3" is not liked.
    static let nevermind: [Track] = {
        let album = Album(id: "spotify:album:n", name: "Nevermind", artist: "Nirvana")
        return ["n1", "n2", "n3", "x"].map { Track(id: $0, title: $0, artist: "a-\($0)", duration: 200, album: album) }
    }()

    /// All songs of MTV Unplugged: "u2" is not liked.
    static let unplugged: [Track] = {
        let album = Album(id: "spotify:album:u", name: "MTV Unplugged In New York", artist: "Nirvana")
        return ["u1", "u2", "u3"].map { Track(id: $0, title: $0, artist: "a-\($0)", duration: 200, album: album) }
    }()

    @Test func anAlbumOpensWithAllItsSongs() {
        var s = withLikedAlbums()
        send(&s, .wheel(2), .select, .wheel(3), now: 120)  // Albums, on Nevermind
        // CLA-46: the first open reads the whole album.
        #expect(send(&s, .select, now: 121) == [.fetchTracks(token: 1, playlist: "spotify:album:n")])
        #expect(s.top.screen == .tracks(playlist: "spotify:album:n") && s.top.loading)
        send(&s, .tracksLoaded(token: 1, playlist: "spotify:album:n", tracks: Self.nevermind), now: 122)
        #expect(!s.top.loading && s.rows(for: s.top) == [.track("n1"), .track("n2"), .track("n3"), .track("x")])
        #expect(s.showsBar == false && s.shownRows == trackRows)
        // Albums and Playlists still list only what they did.
        #expect(s.albums.count == 4 && s.rows(for: Frame(screen: .playlists)).isEmpty)
        // The next open shows it at once. A stale one reads it again in the background.
        send(&s, .menu)
        #expect(send(&s, .select, now: 130) == [] && !s.top.loading)
        send(&s, .menu)
        #expect(send(&s, .select, now: 400) == [.refreshTracks(playlist: "spotify:album:n")])
        // A playlist list re-read keeps the album.
        s.refreshing.insert(AppState.readKey(.playlists))
        send(&s, .playlistsRefreshed([]))
        #expect(s.isLoaded(.tracks(playlist: "spotify:album:n")) && s.tracks(in: "spotify:album:n").count == 4)
    }

    @Test func anAlbumThatFailsToReadShowsTheErrorAndRetries() {
        var s = withLikedAlbums()
        send(&s, .wheel(2), .select, .wheel(3), .select)
        send(&s, .tracksLoaded(token: 1, playlist: "spotify:album:n", tracks: nil))
        #expect(s.top.error && !s.top.loading && !s.isLoaded(.tracks(playlist: "spotify:album:n")))
        #expect(send(&s, .select) == [.fetchTracks(token: 2, playlist: "spotify:album:n")])  // center retries
        #expect(s.top.loading && !s.top.error)
        send(&s, .tracksLoaded(token: 2, playlist: "spotify:album:n", tracks: Self.nevermind))
        #expect(s.rows(for: s.top).count == 4)
    }

    @Test func aSongOfAnAlbumPlaysInTheAlbum() {
        var s = withLikedAlbums()
        send(&s, .wheel(2), .select, .wheel(2), .select)  // MTV Unplugged
        send(&s, .tracksLoaded(token: 1, playlist: "spotify:album:u", tracks: Self.unplugged))
        send(&s, .wheel(1))  // its second song, which is not liked
        let load: [Effect] = [.setShuffle(false), .setRepeat(.off),
                              .load(trackID: "u2", context: "spotify:album:u", autoplay: true, generation: 1)]
        #expect(send(&s, .select) == load)
        let ref = TrackRef(playlist: "spotify:album:u", track: "u2")
        #expect(s.current == ref && s.track(ref)?.title == "u2" && s.top.screen == .now)
        // A Liked Songs re-read does not change the read album.
        s.refreshing = [Playlist.likedSongsID]
        send(&s, .tracksRefreshed(playlist: Playlist.likedSongsID, tracks: likedAlbums))
        #expect(s.extraTracks.isEmpty && s.track(ref) != nil)
        // An album re-read without the playing song keeps its details for Now Playing.
        s.refreshing = ["spotify:album:u"]
        send(&s, .tracksRefreshed(playlist: "spotify:album:u", tracks: [Self.unplugged[0]]))
        #expect(s.extraTracks.map(\.id) == ["u2"] && s.track(ref)?.album?.id == "spotify:album:u")
    }

    @Test func anAlbumThatWasNotReadFollowsLikedSongs() {
        // Spotify plays an album that Clasify did not read: it shows the album's liked songs.
        var s = withLikedAlbums()
        s.current = TrackRef(playlist: "spotify:album:u", track: "u3")
        #expect(s.tracks(in: "spotify:album:u").map(\.id) == ["u1", "u3"])
        // A re-read that moves the playing song to another album keeps its details for Now Playing.
        var moved = likedAlbums
        moved[0].album = Album(id: "spotify:album:other", name: "Other")
        s.refreshing = [Playlist.likedSongsID]
        send(&s, .tracksRefreshed(playlist: Playlist.likedSongsID, tracks: moved))
        let ref = TrackRef(playlist: "spotify:album:u", track: "u3")
        #expect(s.extraTracks.map(\.id) == ["u3"] && s.track(ref)?.album?.id == "spotify:album:u")
        #expect(s.album("spotify:album:u")?.name == "MTV Unplugged In New York")
        s.extraTracks = []
        s.refreshing.insert(AppState.readKey(.playlists))
        send(&s, .playlistsRefreshed([]))  // a playlist list re-read: no copy
        #expect(s.extraTracks.isEmpty)
    }

    @Test func aLikedSongsRereadKeepsTheSelectedAlbum() {
        var s = withLikedAlbums()
        send(&s, .wheel(2), .select, .wheel(3))  // Nevermind, the last album
        let more = [Track(id: "a", title: "a", artist: "b", duration: 1, album: Album(id: "spotify:album:a", name: "Abbey Road"))]
        s.refreshing = [Playlist.likedSongsID]
        send(&s, .tracksRefreshed(playlist: Playlist.likedSongsID, tracks: more + likedAlbums))
        #expect(s.rows(for: s.top)[s.top.sel] == .album("spotify:album:n") && s.top.sel == 4)
    }

    @Test func theAlbumsCoverIsTheSelectedAlbum() {
        var s = withLikedAlbums()
        s.library[0].tracks = likedAlbums.map { var t = $0; t.coverID = "c-\($0.album?.id ?? "")"; return t }
        send(&s, .wheel(2), .select, .wheel(3), now: 200)
        send(&s, .tick, now: 201)
        #expect(s.artRow == .album("spotify:album:n") && s.mainArt.map(\.coverID) == ["c-spotify:album:n"])
    }
}
