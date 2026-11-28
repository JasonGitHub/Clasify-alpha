import Testing
@testable import ClasifyCore

/// CLA-203: a quit of myPod stops or pauses our Spotify, and the player then sees no device.
/// That sends no `control_lost`. A loss before the quit is still sent.
@Suite struct QuitLossTests {
    func events(_ s: inout AppState, _ action: Action, now: Double = 1_000) -> [BetaEvent] {
        reduce(&s, action, Dependencies(now: { now }, random: { _ in 0 })).compactMap { (fx: Effect) -> BetaEvent? in
            if case .track(let event) = fx { return event }
            return nil
        }
    }

    @Test func aLossAfterTheQuitIsNotSent() {
        var s = mainMenu()
        #expect(!s.quitting)
        _ = events(&s, .willQuit(openSeconds: 60))
        #expect(s.quitting)
        #expect(events(&s, .controlLost(.stoppedInSpotify), now: 1_000.2).isEmpty)
        #expect(events(&s, .controlLost(.spotifyQuit), now: 1_000.4).isEmpty)
        #expect(s.controlLostAt == nil)
    }

    @Test func aLossBeforeTheQuitIsSent() {
        var s = mainMenu()
        #expect(events(&s, .controlLost(.spotifyQuit), now: 990) == [.controlLost(.spotifyQuit, service: .spotify)])
        let quit = events(&s, .willQuit(openSeconds: 60))
        #expect(!quit.contains { $0.name == "control_lost" })
        #expect(s.controlLostAt == 990)
    }
}
