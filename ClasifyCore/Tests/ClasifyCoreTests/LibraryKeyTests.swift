import Testing
@testable import ClasifyCore

/// `LibraryKey` matches one Apple Music library song across two lists with different IDs.
@Suite struct LibraryKeyTests {
    @Test func caseAccentsAndSpacesDoNotCount() {
        #expect(LibraryKey.of(title: "Café ", artist: "BAND", album: "Ａlbum")
            == LibraryKey.of(title: "cafe", artist: "band", album: "album"))
    }

    @Test func eachPartCounts() {
        let key = LibraryKey.of(title: "Song", artist: "Band", album: "One")
        #expect(key != LibraryKey.of(title: "Song", artist: "Band", album: "Two"))
        #expect(key != LibraryKey.of(title: "Song", artist: "Other", album: "One"))
        #expect(key != LibraryKey.of(title: "Song", artist: "Band", album: nil))
        // The parts stay apart: "ab" + "c" is not "a" + "bc".
        #expect(LibraryKey.of(title: "ab", artist: "c", album: nil) != LibraryKey.of(title: "a", artist: "bc", album: nil))
    }

    @Test func anAppleTemplateIsFilledAndChecked() {
        #expect(CoverURL.apple(template: "https://is1-ssl.mzstatic.com/image/thumb/a/{w}x{h}{c}.{f}", size: 300)
            == "https://is1-ssl.mzstatic.com/image/thumb/a/300x300bb.jpg")
        #expect(CoverURL.apple(template: "https://is1-ssl.mzstatic.com/image/thumb/a/{w}x{h}bb.jpg", size: 640)
            == "https://is1-ssl.mzstatic.com/image/thumb/a/640x640bb.jpg")
        #expect(CoverURL.apple(template: "http://is1-ssl.mzstatic.com/a/{w}x{h}bb.jpg", size: 300) == nil)
        #expect(CoverURL.apple(template: "https://example.com/a/{w}x{h}bb.jpg", size: 300) == nil)
        #expect(CoverURL.apple(template: "musicKit://artwork/a", size: 300) == nil)
    }
}
