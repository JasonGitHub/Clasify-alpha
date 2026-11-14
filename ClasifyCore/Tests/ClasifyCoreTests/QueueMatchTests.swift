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
