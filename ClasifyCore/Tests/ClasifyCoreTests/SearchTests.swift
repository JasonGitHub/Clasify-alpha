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
        #expect(Search.results("mara", in: s) == [Search.Result(kind: .artist, id: "spotify:artist:mara", name: "Mara Kei", detail: "Artist")])
        #expect(Search.results("glass r", in: s) == [Search.Result(kind: .album, id: Self.glass.id, name: "Glass Rooms", detail: "Album · Vera Lune")])
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
