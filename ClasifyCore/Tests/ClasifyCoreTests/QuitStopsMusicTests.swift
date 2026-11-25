import Testing
@testable import ClasifyCore

/// CLA-189: a normal quit stops our Spotify music. Apple Music and On This Mac get nothing.
@MainActor @Suite struct QuitStopsMusicTests {
    let spotify = FakePlayer(), appleMusic = FakePlayer(), local = FakePlayer()

    func quit(on service: MusicService, playing: Bool = true) -> [Effect] {
        var s = mainMenu()
        s.service = service
        if playing { s.current = TrackRef(playlist: Playlist.likedSongsID, track: "l0"); s.isPlaying = true }
        let player = ServicePlayer(spotify: spotify, appleMusic: appleMusic, local: local, service: service)
        let store = Store(player: player, library: FakeLibrary(), state: s, env: Dependencies(now: { 0 }, random: { _ in 0 }))
        store.send(.willQuit(openSeconds: nil))
        return reduce(&s, .willQuit(openSeconds: nil), Dependencies(now: { 0 }, random: { _ in 0 }))
    }

    @Test func aQuitOnSpotifyTellsTheSpotifyPlayer() {
        #expect(quit(on: .spotify).contains(.quitPlayer))
        #expect(spotify.calls == ["quit"] && appleMusic.calls.isEmpty && local.calls.isEmpty)
    }

    /// The Spotify app that myPod opened quits also when nothing plays: the engine decides.
    @Test func aQuitOnSpotifyWithNothingPlayingStillTellsIt() {
        #expect(quit(on: .spotify, playing: false).contains(.quitPlayer))
        #expect(spotify.calls == ["quit"])
    }

    @Test func aQuitOnAppleMusicOrOnThisMacDoesNothingToThePlayers() {
        for service in [MusicService.appleMusic, .local] {
            #expect(!quit(on: service).contains(.quitPlayer), "\(service)")
        }
        #expect(spotify.calls.isEmpty && appleMusic.calls.isEmpty && local.calls.isEmpty)
    }
}
