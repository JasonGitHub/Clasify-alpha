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
        #expect(s.rows(for: s.top) == [.playlists, .albums, .likedSongs, .shuffleSongs, .settings])
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
        #expect(send(&s, .wheel(1), .select, now: 150) == [])  // read 50 s ago: no read again
        #expect(s.top.screen == .albums && !s.top.loading && s.isHalf(.albums) && s.shownRows == trackRows)
        #expect(s.rows(for: s.top) == [.album("spotify:album:1"), .album("spotify:album:m"),
                                       .album("spotify:album:u"), .album("spotify:album:n")])
        send(&s, .menu)
        #expect(send(&s, .select, now: 300) == [.refreshTracks(playlist: Playlist.likedSongsID)])  // stale: read again
    }

    @Test func albumsLoadsLikedSongsFirst() {
        var s = mainMenu()
        #expect(send(&s, .wheel(1), .select) == [.fetchTracks(token: 1, playlist: Playlist.likedSongsID)])
        #expect(s.top.screen == .albums && s.top.loading)
        send(&s, .tracksLoaded(token: 1, playlist: Playlist.likedSongsID, tracks: likedAlbums))
        #expect(!s.top.loading && s.rows(for: s.top).count == 4)
    }

    @Test func anAlbumOpensItsLikedSongsInDiscAndTrackOrder() {
        var s = withLikedAlbums()
        send(&s, .wheel(1), .select, .wheel(3), .select)  // Albums, then Nevermind
        #expect(s.top.screen == .tracks(playlist: "spotify:album:n") && !s.top.loading)
        #expect(s.rows(for: s.top) == [.track("n1"), .track("n2"), .track("x")])  // disc 1, then disc 2
        #expect(s.showsBar == false && s.shownRows == trackRows)
    }

    @Test func aSongOfAnAlbumPlaysInTheAlbum() {
        var s = withLikedAlbums()
        send(&s, .wheel(1), .select, .wheel(2), .select, .wheel(1))  // MTV Unplugged, its second song
        let load: [Effect] = [.setShuffle(false), .setRepeat(.off),
                              .load(trackID: "u3", context: "spotify:album:u", autoplay: true, generation: 1)]
        #expect(send(&s, .select) == load)
        let ref = TrackRef(playlist: "spotify:album:u", track: "u3")
        #expect(s.current == ref && s.track(ref)?.title == "u3" && s.top.screen == .now)
        // A Liked Songs re-read keeps it, and does not keep a copy for a track that left.
        s.refreshing = [Playlist.likedSongsID]
        send(&s, .tracksRefreshed(playlist: Playlist.likedSongsID, tracks: likedAlbums))
        #expect(s.extraTracks.isEmpty && s.track(ref) != nil)
        s.refreshing.insert(AppState.readKey(.playlists))
        send(&s, .playlistsRefreshed([]))  // a playlist list re-read: Liked Songs stays, so no copy either
        #expect(s.extraTracks.isEmpty)
    }

    @Test func aLikedSongsRereadKeepsTheSelectedAlbum() {
        var s = withLikedAlbums()
        send(&s, .wheel(1), .select, .wheel(3))  // Nevermind, the last album
        let more = [Track(id: "a", title: "a", artist: "b", duration: 1, album: Album(id: "spotify:album:a", name: "Abbey Road"))]
        s.refreshing = [Playlist.likedSongsID]
        send(&s, .tracksRefreshed(playlist: Playlist.likedSongsID, tracks: more + likedAlbums))
        #expect(s.rows(for: s.top)[s.top.sel] == .album("spotify:album:n") && s.top.sel == 4)
    }

    @Test func theAlbumsCoverIsTheSelectedAlbum() {
        var s = withLikedAlbums()
        s.library[0].tracks = likedAlbums.map { var t = $0; t.coverID = "c-\($0.album?.id ?? "")"; return t }
        send(&s, .wheel(1), .select, .wheel(3), now: 200)
        send(&s, .tick, now: 201)
        #expect(s.artRow == .album("spotify:album:n") && s.mainArt.map(\.coverID) == ["c-spotify:album:n"])
    }
}
