import Testing
@testable import ClasifyCore

@MainActor @Test func servicePlayerSendsCallsToTheActiveServiceOnly() {
    let spotify = FakePlayer(), appleMusic = FakePlayer()
    let player = ServicePlayer(spotify: spotify, appleMusic: appleMusic, service: .spotify)
    player.load(trackID: "a", context: "list", autoplay: true, generation: 1)
    player.pause(); player.resume(); player.next(generation: 2); player.prev(generation: 3)
    player.seek(to: 5, generation: 4); player.setVolume(40); player.stop()
    #expect(spotify.calls == ["load a list true", "pause", "resume", "next", "prev", "seek 5.0", "volume 40", "stop"])
    #expect(appleMusic.calls.isEmpty)
}

@MainActor @Test func servicePlayerStopsTheOldServiceOnASwitch() {
    let spotify = FakePlayer(), appleMusic = FakePlayer()
    let player = ServicePlayer(spotify: spotify, appleMusic: appleMusic, service: .spotify)
    player.service = .spotify  // no change: nothing stops
    #expect(spotify.calls.isEmpty)
    player.service = .appleMusic
    player.load(trackID: "b", context: nil, autoplay: false, generation: 1)
    #expect(spotify.calls == ["stop"])
    #expect(appleMusic.calls == ["load b - false"])
    player.service = .spotify
    #expect(appleMusic.calls == ["load b - false", "stop"])
}

@MainActor @Test func servicePlayerGivesShuffleAndRepeatToBothServices() {
    let spotify = FakePlayer(), appleMusic = FakePlayer()
    let player = ServicePlayer(spotify: spotify, appleMusic: appleMusic, service: .appleMusic)
    player.setShuffle(true)
    player.setRepeat(.all)
    #expect(spotify.calls == ["shuffle true", "repeat All"])
    #expect(appleMusic.calls == ["shuffle true", "repeat All"])
}
