import Testing
@testable import ClasifyCore

private struct Refused: Error {}

@Suite @MainActor struct AlbumPlayTests {
    @Test func theTrackListIsTheAlbumsLikedSongsInPlayOrder() {
        #expect(AlbumPlay.trackList(album: "spotify:album:n", track: "x", liked: likedAlbums) == ["n1", "n2", "x"])
        #expect(AlbumPlay.trackList(album: "spotify:album:n", track: "u1", liked: likedAlbums) == nil)  // not on it
        #expect(AlbumPlay.trackList(album: "focus", track: "f1", liked: focus.tracks) == nil)  // not an album
        let many = (0...AlbumPlay.maxTracks).map {
            Track(id: "t\($0)", title: "", artist: "", duration: 1, album: Album(id: "spotify:album:big", name: "Big"))
        }
        #expect(AlbumPlay.trackList(album: "spotify:album:big", track: "t0", liked: many) == nil)  // too many
    }

    @Test func aTrackListThatPlaysIsTheOnlyTry() async throws {
        var calls: [String] = []
        let path = try await AlbumPlay.run(
            hasList: true, trackList: { calls.append("list") }, albumContext: { calls.append("album") })
        #expect(path == .trackList && calls == ["list"])
    }

    @Test func aRefusedTrackListFallsBackToTheAlbum() async throws {
        var calls: [String] = []
        var failures = 0
        let path = try await AlbumPlay.run(
            hasList: true, trackList: { calls.append("list"); throw Refused() },
            albumContext: { calls.append("album") }, trackListFailed: { _ in failures += 1 })
        #expect(path == .albumContext && calls == ["list", "album"] && failures == 1)
        // No list to try: the album at once.
        calls = []
        let direct = try await AlbumPlay.run(
            hasList: false, trackList: { calls.append("list") }, albumContext: { calls.append("album") })
        #expect(direct == .albumContext && calls == ["album"])
    }

    @Test func aNewerLoadStopsTheFallback() async throws {
        var calls: [String] = []
        let path = try await AlbumPlay.run(
            hasList: true, trackList: { calls.append("list"); throw Refused() },
            albumContext: { calls.append("album") }, stillWanted: { false })
        #expect(path == nil && calls == ["list"])
    }

    @Test func whenBothFailTheAlbumsErrorComesBack() async {
        await #expect(throws: Refused.self) {
            _ = try await AlbumPlay.run(hasList: true, trackList: { throw Refused() }, albumContext: { throw Refused() })
        }
    }

    @Test func aSongFromAlbumsPlaysWithTheFakePlayer() {
        let player = FakePlayer()
        var s = withLikedAlbums()
        let store = Store(player: player, library: FakeLibrary(), state: s, env: Dependencies(now: { 100 }, random: { _ in 0 }))
        store.send(.wheel(2)); store.send(.select); store.send(.wheel(3)); store.send(.select)  // Nevermind
        store.send(.select)  // its first song
        #expect(player.calls.last == "load n1 spotify:album:n true")
        s = store.state
        #expect(s.current == TrackRef(playlist: "spotify:album:n", track: "n1"))
    }
}
