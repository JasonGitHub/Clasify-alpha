import Foundation
import Testing
@testable import ClasifyCore

/// CLA-183, card CS: matching and result order of Search on the device.
@Suite struct SearchTests {
    static let glass = Album(id: "spotify:album:glass", name: "Glass Rooms", artist: "Vera Lune")
    static let halfway = Album(id: "spotify:album:half", name: "Halfway Home", artist: "Mara Kei")

    static func song(_ id: String, _ title: String, _ artist: String = "Mara Kei", album: Album? = nil, missing: Bool = false) -> Track {
        Track(id: id, title: title, artist: artist, duration: 200, album: album, missing: missing)
    }

    /// A Spotify library: Liked Songs (the albums list), two playlists, one not read yet.
    static func state() -> AppState {
        var s = AppState()
        s.library = [
            Playlist(id: Playlist.likedSongsID, name: "Liked Songs", tracks: [
                song("t1", "Glasshouse", "Vera Lune", album: glass), song("t2", "Halfway Home", album: halfway),
                song("t3", "Tail Lights", album: halfway),
            ]),
            Playlist(id: "spotify:playlist:drive", name: "Late Night Drive", tracks: [song("t3", "Tail Lights", album: halfway), song("t4", "Rearview")]),
            Playlist(id: "spotify:playlist:focus", name: "Focus", tracks: [], trackCount: 1),
        ]
        s.artists = [Playlist(id: "spotify:artist:mara", name: "Mara Kei", tracks: [])]
        return s
    }

    @Test func anEmptyOrBlankQueryHasNoResults() {
        #expect(Search.results("", in: Self.state()).isEmpty)
        #expect(Search.results("   ", in: Self.state()).isEmpty)
    }

    @Test func kindsComeInOrderArtistsAlbumsPlaylistsSongs() {
        var s = Self.state()
        s.library[1].name = "Halfway Mix"
        s.artists.append(Playlist(id: "spotify:artist:half", name: "Halfway Band", tracks: []))
        #expect(Search.results("halfway", in: s).map(\.kind) == [.artist, .album, .playlist, .song])
    }

    @Test func eachRowHasItsWordsAndWhatOpensIt() {
        let s = Self.state()
        #expect(Search.results("mara", in: s).first == Search.Result(kind: .artist, id: "spotify:artist:mara", name: "Mara Kei", detail: "Artist"))
        #expect(Search.results("glass r", in: s).first == Search.Result(kind: .album, id: Self.glass.id, name: "Glass Rooms", detail: "Album · Vera Lune"))
        #expect(Search.results("late", in: s) == [Search.Result(kind: .playlist, id: "spotify:playlist:drive", name: "Late Night Drive", detail: "Playlist · 2 songs")])
        #expect(Search.results("focus", in: s).first?.detail == "Playlist · 1 song")  // the count before its songs are read
        #expect(Search.results("rear", in: s) == [
            Search.Result(kind: .song, id: "t4", name: "Rearview", detail: "Song · Mara Kei", list: "spotify:playlist:drive"),
        ])
    }

    @Test func matchingIgnoresCaseAndAccentsInBothAndFindsAnyPart() {
        var s = Self.state()
        s.library[1].tracks.append(Self.song("t5", "Café Björk"))
        #expect(Search.results("CAFE", in: s).map(\.id) == ["t5"])
        #expect(Search.results("bjórk", in: s).map(\.id) == ["t5"])
        #expect(Search.results("  lights ", in: s).map(\.id) == ["t3"])
        #expect(Search.results("ｒｅａｒ", in: s).map(\.id) == ["t4"])  // full-width letters
        #expect(Search.results("xyz", in: s).isEmpty)
    }

    /// Jason's test of build 458: "green day" found nothing. Each word of the query is found in
    /// the name or, for a song or an album, in its artist names, in any order.
    @Test func songsAndAlbumsAlsoMatchByArtist() {
        var s = Self.state()
        let dookie = Album(id: "spotify:album:dookie", name: "Dookie", artist: "Green Day")
        s.library[0].tracks += [  // Liked Songs: the albums come from it
            Self.song("g1", "Basket Case", "Green Day", album: dookie),
            Self.song("g2", "Longview", "Green Day, Guest Star", album: dookie),
            Self.song("g3", "Holiday", "Other Band"),
        ]
        func found(_ q: String) -> [String] { Search.results(q, in: s).map(\.name) }
        #expect(found("green day") == ["Dookie", "Basket Case", "Longview"])  // album, then songs
        #expect(found("green day dookie") == ["Dookie"])  // a song's own album name does not count
        #expect(found("dookie green day") == found("green day dookie"))
        #expect(found("guest") == ["Longview"])  // any of a song's artists
        #expect(found("case green") == ["Basket Case"])
        #expect(found("green   day ") == found("green day") && found("green ") == found("green"))
        #expect(found("day") == ["Dookie", "Basket Case", "Holiday", "Longview"])  // in a name or an artist
        #expect(found("green xyz").isEmpty)  // every word must be found
    }

    /// Playlists and artists use the same word rule, on the name only.
    @Test func playlistsAndArtistsMatchEachWordOfTheName() {
        let s = Self.state()
        #expect(Search.results("night late", in: s).map(\.id) == ["spotify:playlist:drive"])
        #expect(Search.results("kei mara", in: s).first?.id == "spotify:artist:mara")
        #expect(Search.results("late kei", in: s).isEmpty)  // a playlist has no artist text
    }

    @Test func otherScriptsMatch() {
        var s = Self.state()
        s.library[1].tracks.append(Self.song("t6", "纸飞机日记", "陈一"))
        #expect(Search.results("飞机", in: s).map(\.id) == ["t6"])
    }

    @Test func aSongInSeveralListsShowsOnceAndPlaysInTheLikedList() {
        let found = Search.results("tail", in: Self.state())
        #expect(found.count == 1)
        #expect(found.first?.list == Playlist.likedSongsID)
    }

    @Test func theSongsListWinsThenThePlaylistNeverTheWholeLibrary() {
        var s = AppState()
        s.words = .appleMusic
        let album = Album(id: "applemusic:album:1", name: "Westbound")
        let west = Self.song("a1", "Westbound", album: album)
        s.library = [
            Playlist(id: Playlist.libraryID, name: "", tracks: [west, Self.song("a2", "Exit 22", album: album)]),
            Playlist(id: "applemusic:playlist:p", name: "Road", tracks: [Self.song("a2", "Exit 22", album: album)]),
            Playlist(id: Playlist.songsID, name: "", tracks: [west]),
        ]
        #expect(Search.results("westbound", in: s).last?.list == Playlist.songsID)
        #expect(Search.results("exit", in: s).first?.list == "applemusic:playlist:p")
        s.library.removeAll { $0.id != Playlist.libraryID }
        #expect(Search.results("westbound", in: s).last?.list == album.id)  // its album, not the library
    }

    @Test func hiddenListsAreNotPlaylistResults() {
        var s = Self.state()
        s.library.append(Playlist(id: Self.halfway.id, name: "Halfway Home", tracks: []))
        #expect(Search.results("liked", in: s).isEmpty)
        #expect(Search.results("halfway", in: s).map(\.kind) == [.album, .song])
    }

    /// Design check of #458 (card CS): inside each kind the rows sort like the library lists,
    /// where a leading "The" does not count. The plain name order put "Hello Glow" before
    /// "The Glow".
    @Test func eachKindSortsLikeTheLibraryListsWithoutALeadingThe() {
        var s = Self.state()
        s.artists = [
            Playlist(id: "spotify:artist:hello", name: "Hello Glow", tracks: []),
            Playlist(id: "spotify:artist:the", name: "The Glow", tracks: []),
        ]
        s.library[1].name = "The Glow Mix"
        s.library.append(Playlist(id: "spotify:playlist:hello", name: "Hello Glow Mix", tracks: []))
        s.library[0].tracks += [
            Self.song("t10", "The Glow Song", album: Album(id: "spotify:album:the", name: "The Glow Album", artist: "Mara Kei")),
            Self.song("t11", "Hello Glow Song", album: Album(id: "spotify:album:hello", name: "Hello Glow Album", artist: "Mara Kei")),
        ]
        let found = Search.results("glow", in: s)
        #expect(found.filter { $0.kind == .artist }.map(\.name) == ["The Glow", "Hello Glow"])
        #expect(found.filter { $0.kind == .album }.map(\.name) == ["The Glow Album", "Hello Glow Album"])
        #expect(found.filter { $0.kind == .playlist }.map(\.name) == ["The Glow Mix", "Hello Glow Mix"])
        #expect(found.filter { $0.kind == .song }.map(\.name) == ["The Glow Song", "Hello Glow Song"])
        #expect(found.map(\.kind) == [.artist, .artist, .album, .album, .playlist, .playlist, .song, .song])
    }

    /// The limit keeps the first names in that order, not the first rows of the library.
    @Test func theLimitKeepsTheFirstNamesInOrder() {
        var s = Self.state()
        s.artists = (0..<(Search.limit + 5)).reversed().map {
            Playlist(id: "spotify:artist:\($0)", name: "Echo \(1000 + $0)", tracks: [])
        }
        s.artists.append(Playlist(id: "spotify:artist:the", name: "The Echo", tracks: []))  // last in the library
        let names = Search.results("echo", in: s).map(\.name)
        #expect(names.count == Search.limit)
        #expect(names.first == "The Echo" && names[1] == "Echo 1000" && names.last == "Echo 1048")
    }

    @Test func songsComeInTitleOrderAndAMissingSongIsLeftOut() {
        var s = Self.state()
        s.library[1].tracks += [Self.song("t7", "The Arrow"), Self.song("t8", "Zero Arrow"), Self.song("t9", "Arrow Gone", missing: true)]
        #expect(Search.results("arrow", in: s).map(\.id) == ["t7", "t8"])  // "The Arrow" sorts under A
    }

    @Test func eachKindStopsAtTheLimit() {
        var s = Self.state()
        s.library[1].tracks = (0..<(Search.limit + 20)).map { Self.song("x\($0)", "Echo \($0)") }
        #expect(Search.results("echo", in: s).count == Search.limit)
    }

    /// One index serves every key; it sees new library data only when it is made again.
    @Test func anIndexGivesTheSameResultsForEveryKeyUntilItIsMadeAgain() {
        var s = Self.state()
        let index = Search.Index(s)
        for query in ["", "a", "halfway", "MARA", "tail", "glass r", "late", "xyz"] {
            #expect(index.results(query) == Search.results(query, in: s))
        }
        s.library[1].tracks.append(Self.song("t5", "Halfway Gone"))
        #expect(index.results("gone").isEmpty)
        #expect(Search.Index(s).results("gone").map(\.id) == ["t5"])
    }

    /// Typing stays fast: 10,000 songs in 3 lists, a one-letter query that matches most of them.
    /// The CI log shows the times (a debug build; a release build is faster).
    @Test func tenThousandSongsAreFast() {
        var s = AppState()
        let words = ["Neon", "Glass", "Paper", "Still", "Halfway", "Sodium", "Pulse", "Rear", "Café", "Björk"]
        let songs = (0..<10_000).map { i in
            Self.song("s\(i)", "\(words[i % 10]) \(words[(i / 10) % 10]) \(i)", album: Album(id: "spotify:album:\(i / 12)", name: "Album \(i / 12)"))
        }
        s.library = [
            Playlist(id: Playlist.likedSongsID, name: "Liked Songs", tracks: songs),
            Playlist(id: "spotify:playlist:a", name: "A", tracks: Array(songs.prefix(5_000))),
            Playlist(id: "spotify:playlist:b", name: "B", tracks: Array(songs.suffix(5_000))),
        ]
        let clock = ContinuousClock()
        var index: Search.Index?
        let build = clock.measure { index = Search.Index(s) }
        var found: [Search.Result] = []
        let key = clock.measure { found = index?.results("e") ?? [] }
        print("Search on 10,000 songs: index \(build), one key \(key)")
        #expect(found.filter { $0.kind == .song }.count == Search.limit)
        #expect(key < .milliseconds(500), "one key took \(key)")
        #expect(build < .seconds(5), "the index took \(build)")
    }
}
