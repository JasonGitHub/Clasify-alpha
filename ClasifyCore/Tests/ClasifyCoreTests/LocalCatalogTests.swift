import Testing
@testable import ClasifyCore

/// Local music (CLA-179): the lists that the local `Library` answers from one Music app library read.
@Suite struct LocalCatalogTests {
    static func item(
        _ pid: UInt64, _ title: String, artist: String = "Band", album: String = "Record", albumID: UInt64 = 100,
        albumArtist: String? = nil, disc: Int? = nil, number: Int? = nil, cover: Bool = true, playable: Bool = true
    ) -> LocalItem {
        LocalItem(
            persistentID: pid, title: title, artist: artist, album: album, albumID: albumID, albumArtist: albumArtist,
            disc: disc, number: number, duration: 180, hasCover: cover, playable: playable)
    }

    @Test func idsGoBothWaysAndNeverMixWithOtherServices() {
        #expect(LocalID.track(0xABC) == "local:track:abc")
        #expect(LocalID.playlist(0xFEDC_BA98_7654_3210) == "local:playlist:fedcba9876543210")
        #expect(LocalID.persistentID("local:track:abc", prefix: LocalID.trackPrefix) == 0xABC)
        #expect(LocalID.persistentID("local:track:", prefix: LocalID.trackPrefix) == nil)
        #expect(LocalID.persistentID("local:playlist:abc", prefix: LocalID.trackPrefix) == nil)
        #expect(LocalID.persistentID("applemusic:song:abc", prefix: LocalID.trackPrefix) == nil)
        #expect(Album.isID(LocalID.album(1)))
        #expect(Playlist.isArtistID(LocalID.artist("Band")))
        #expect(Playlist.isHidden(LocalID.album(1)) && Playlist.isHidden(LocalID.artist("Band")))
        #expect(!Playlist.isHidden(LocalID.playlist(1)))
    }

    @Test func aSongBecomesATrackWithItsAlbumAndLibraryCovers() {
        let track = LocalCatalog.track(from: Self.item(0x1F, "Song", album: "Record", albumID: 0x64, albumArtist: "Various", disc: 2, number: 3))
        #expect(track.id == "local:track:1f")
        #expect(track.title == "Song" && track.artist == "Band" && track.duration == 180)
        #expect(track.album == Album(id: "local:album:64", name: "Record", artist: "Various"))
        #expect(track.disc == 2 && track.number == 3)
        #expect(track.coverID == LibraryCover.coverID(persistentID: 0x1F, side: 300))
        #expect(track.largeCoverID == LibraryCover.coverID(persistentID: 0x1F, side: 640))
        let plain = LocalCatalog.track(from: Self.item(2, "B", album: "", cover: false))
        #expect(plain.album == nil && plain.coverID == nil && plain.largeCoverID == nil)
        #expect(LocalCatalog.track(from: Self.item(3, "C", albumArtist: "")).album?.artist == "Band")  // no album artist: the song's
    }

    @Test func songsThatCannotPlayAreHiddenEverywhere() {
        let catalog = LocalCatalog(
            items: [Self.item(1, "Plays"), Self.item(2, "Protected", playable: false)],
            lists: [LocalList(persistentID: 9, name: "Mix", items: [2, 1])])
        #expect(catalog.library.map(\.title) == ["Plays"])
        #expect(catalog.track(LocalID.track(2)) == nil)
        #expect(catalog.tracks(of: LocalID.playlist(9))?.map(\.title) == ["Plays"])
        #expect(catalog.playlists.first?.trackCount == 1)
    }

    @Test func playlistsThatAreEmptyAfterThatAreLeftOut() {
        let catalog = LocalCatalog(
            items: [Self.item(1, "A"), Self.item(2, "Video", playable: false)],
            lists: [
                LocalList(persistentID: 7, name: "Only videos", items: [2]), LocalList(persistentID: 8, name: "Empty", items: []),
                LocalList(persistentID: 9, name: "Keep", items: [1, 1]),
            ])
        #expect(catalog.playlists.map(\.name) == ["Keep"])
        #expect(catalog.playlists.map(\.id) == ["local:playlist:9"])
        #expect(catalog.tracks(of: "local:playlist:9")?.count == 2)  // a song twice stays twice, in list order
        #expect(catalog.playlists.first?.tracks.isEmpty == true)  // the list read gives no tracks
        #expect(catalog.tracks(of: "local:playlist:7") == nil)
    }

    @Test func theLibraryIsAlbumsByNameWithSongsInDiscAndTrackOrder() {
        let catalog = LocalCatalog(items: [
            Self.item(1, "Z2", album: "Zebra", albumID: 20, number: 2),
            Self.item(2, "No album", album: ""),
            Self.item(3, "A1-2", album: "apple", albumID: 10, disc: 1, number: 2),
            Self.item(4, "Z1", album: "Zebra", albumID: 20, number: 1),
            Self.item(5, "A2-1", album: "apple", albumID: 10, disc: 2, number: 1),
            Self.item(6, "A1-1", album: "apple", albumID: 10, disc: 1, number: 1),
            Self.item(7, "Num", album: "1999", albumID: 30),
        ], lists: [])
        #expect(catalog.library.map(\.title) == ["Num", "A1-1", "A1-2", "A2-1", "Z1", "Z2", "No album"])
        #expect(catalog.tracks(of: Playlist.libraryID) == catalog.library)
        #expect(catalog.tracks(of: "local:album:a")?.map(\.title) == ["A1-1", "A1-2", "A2-1"])
        #expect(catalog.tracks(of: "local:album:ff")?.isEmpty == true)
    }

    @Test func songsAreInTitleOrderAndLikedSongsIsEmpty() {
        let catalog = LocalCatalog(items: [Self.item(1, "The Bell"), Self.item(2, "apple"), Self.item(3, "Cello")], lists: [])
        #expect(catalog.tracks(of: Playlist.songsID)?.map(\.title) == ["apple", "The Bell", "Cello"])
        #expect(catalog.tracks(of: Playlist.likedSongsID) == [])
        #expect(catalog.tracks(of: "spotify:playlist:x") == nil)
    }

    @Test func artistsAreEverySongAndAlbumArtistInNameOrder() {
        let catalog = LocalCatalog(items: [
            Self.item(1, "One", artist: "The Zoo", album: "Hits", albumID: 1, albumArtist: "Various", number: 2),
            Self.item(2, "Two", artist: "Abba", album: "Hits", albumID: 1, albumArtist: "Various", number: 1),
            Self.item(3, "Three", artist: "Abba", album: "Gold", albumID: 2),
            Self.item(4, "Four", artist: "", album: ""),
        ], lists: [])
        #expect(catalog.artists.map(\.name) == ["Abba", "Various", "The Zoo"])
        #expect(catalog.artists.map(\.id) == ["local:artist:Abba", "local:artist:Various", "local:artist:The Zoo"])
        #expect(catalog.tracks(of: LocalID.artist("Abba"))?.map(\.title) == ["Three", "Two"])  // Gold before Hits
        #expect(catalog.tracks(of: LocalID.artist("Various"))?.map(\.title) == ["Two", "One"])
    }

    @Test func anEmptyLibraryIsEmptyListsNotAFailure() {
        let catalog = LocalCatalog(items: [], lists: [])
        #expect(catalog.library.isEmpty && catalog.playlists.isEmpty && catalog.artists.isEmpty)
        #expect(catalog.tracks(of: Playlist.libraryID) == [])
        #expect(catalog.tracks(of: Playlist.songsID) == [])
    }

    @Test func localWordsUseTheLibraryRowsAndTheLibraryForAlbums() {
        #expect(LibraryWords.local.albumsList == Playlist.libraryID)
        #expect(LibraryWords.local.libraryRows)
        #expect(LibraryWords.local.oneSong == "song" && LibraryWords.local.manySongs == "songs")
    }
}
