import Testing
@testable import ClasifyCore

/// `QueueMatch` maps an Apple Music queue entry back to the store ID that the library gave.
@Suite struct QueueMatchTests {
    let a = SongKeys(ids: ["i.A", "100"], isrc: "USA1", title: "Song", artist: "Band")
    let b = SongKeys(ids: ["i.B", "200"], isrc: "USB2", title: "Song", artist: "Band")  // same name

    @Test func anIDWinsOverTheTitleAndArtist() {
        let match = QueueMatch([(id: "applemusic:song:i.A", keys: a), (id: "applemusic:song:i.B", keys: b)])
        // The entry carries B's catalog ID only: B, not A, which has the same title and artist.
        #expect(match.id(for: SongKeys(ids: ["200"], title: "Song", artist: "Band")) == "applemusic:song:i.B")
        #expect(match.id(for: SongKeys(ids: ["999"], isrc: "USB2", title: "Song", artist: "Band")) == "applemusic:song:i.B")
        #expect(match.id(for: SongKeys(ids: ["i.A"], title: "Other", artist: "X")) == "applemusic:song:i.A")
        // Only the name matches: the first song with it.
        #expect(match.id(for: SongKeys(ids: ["999"], title: "Song", artist: "Band")) == "applemusic:song:i.A")
        #expect(match.id(title: "Song", artist: "Band") == "applemusic:song:i.A")
    }

    @Test func aSongThatWasNotQueuedGivesNoID() {
        let match = QueueMatch([(id: "applemusic:song:i.A", keys: a)])
        #expect(match.id(for: SongKeys(ids: ["999"], isrc: "XX", title: "New", artist: "Band")) == nil)
        #expect(match.id(title: "Song", artist: "Other") == nil)
        #expect(QueueMatch().id(title: "Song", artist: "Band") == nil)
    }
}

@Suite struct QueueStartTests {
    static func keys(_ ids: [String], isrc: String? = nil, _ title: String) -> SongKeys {
        SongKeys(ids: ids, isrc: isrc, title: title, artist: "x")
    }
    static let list: [(id: String, keys: SongKeys)] = [
        ("s:1", keys(["1"], isrc: "A", "One")),
        ("s:2", keys(["2", "c2"], isrc: "B", "Two")),
        ("s:3", keys(["3"], "Two")),  // the same title and artist as row 2
    ]

    @Test func theRowWithThePickedIDWinsEvenWhenTheReadSongHasAnotherID() {
        // Build 206: "Favorite Songs" row 3 picked, and the song read by its ID came back with ID 9.
        let start = QueueMatch.start(of: "s:3", keys: Self.keys(["9"], "Two"), in: Self.list)
        #expect(start?.index == 2 && start?.byID == true)
    }

    @Test func elseTheStrongestKeyFindsTheRow() {
        #expect(QueueMatch.start(of: "s:x", keys: Self.keys(["c2"], "Other"), in: Self.list).map { [$0.index] } == [1])
        #expect(QueueMatch.start(of: "s:x", keys: Self.keys(["9"], isrc: "A", "Two"), in: Self.list)?.index == 0)  // ISRC before name
        let byName = QueueMatch.start(of: "s:x", keys: Self.keys(["9"], "Two"), in: Self.list)
        #expect(byName?.index == 1 && byName?.byID == false)  // the first row with that name
    }

    @Test func aSongNotInTheListHasNoStart() {
        #expect(QueueMatch.start(of: "s:x", keys: Self.keys(["9"], "Nine"), in: Self.list) == nil)
        #expect(QueueMatch.start(of: "s:1", keys: Self.keys(["1"], "One"), in: []) == nil)
    }
}
