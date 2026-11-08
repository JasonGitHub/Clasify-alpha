import Testing
@testable import ClasifyCore

struct TrackTests {
    @Test func aTrackKeepsItsAlbumAndItsPlaceOnIt() {
        let album = Album.from(id: "spotify:album:a", name: "Record", artist: "X, Y")
        let track = Track(id: "spotify:track:1", title: "One", artist: "X", duration: 1, album: album, disc: 2, number: 7)
        #expect(track.album == Album(id: "spotify:album:a", name: "Record", artist: "X, Y"))
        #expect(track.disc == 2 && track.number == 7)
    }

    @Test func missingAlbumFieldsAreNil() {
        // The bridge sends "" and 0 for a field that Spotify does not give.
        #expect(Album.from(id: "", name: "Record", artist: "X") == nil)
        #expect(Album.from(id: nil, name: nil, artist: nil) == nil)
        #expect(Album.from(id: "spotify:album:a", name: nil, artist: "")?.artist == nil)
        #expect(Album.from(id: "spotify:album:a", name: nil, artist: "") == Album(id: "spotify:album:a", name: ""))
        let track = Track(id: "spotify:track:1", title: "One", artist: "X", duration: 1, disc: 0, number: 0)
        #expect(track.album == nil && track.disc == nil && track.number == nil)
    }
}
