import Testing
@testable import ClasifyCore

/// `LibraryCover` names an Apple Music library cover that the app reads from iTunesLibrary.
@Suite struct LibraryCoverTests {
    @Test func aCoverIDGoesBothWays() {
        let id = LibraryCover.coverID(persistentID: 0xFEDC_BA98_7654_3210, side: 300)
        #expect(id == "itlib:fedcba9876543210:300")
        #expect(LibraryCover.parse(id)?.persistentID == 0xFEDC_BA98_7654_3210)
        #expect(LibraryCover.parse(id)?.side == 300)
    }

    @Test func otherCoverIDsAreNotLibraryCovers() {
        #expect(LibraryCover.parse("https://is1-ssl.mzstatic.com/a/300x300bb.jpg") == nil)
        #expect(LibraryCover.parse(String(repeating: "a", count: 40)) == nil)
        #expect(LibraryCover.parse("itlib:xyz:300") == nil)
        #expect(LibraryCover.parse("itlib:12:0") == nil)
        #expect(LibraryCover.parse("itlib:12:300:1") == nil)
        #expect(LibraryCover.parse("itlib::300") == nil)
    }

    @Test func coverURLNeverLoadsALibraryCover() {
        #expect(CoverURL.url(for: LibraryCover.coverID(persistentID: 1, side: 640)) == nil)
    }

    @Test func aMusicKitIDGivesItsPersistentID() {
        #expect(LibraryCover.persistentID(musicKitID: "1234567890123456789") == 1_234_567_890_123_456_789)
        #expect(LibraryCover.persistentID(musicKitID: "-1") == UInt64.max)
        #expect(LibraryCover.persistentID(musicKitID: "-1234567890123456789")
            == UInt64(bitPattern: -1_234_567_890_123_456_789))
        #expect(LibraryCover.persistentID(musicKitID: "i.AbCd123") == nil)
        #expect(LibraryCover.persistentID(musicKitID: "l.AbCd123") == nil)
        #expect(LibraryCover.persistentID(musicKitID: "") == nil)
    }
}
