import Foundation
import Testing
@testable import ClasifyCore

/// CLA-186: `app_closed` at a normal quit (`.willQuit`), with the minutes open and the kind of screen.
@Suite struct AppClosedTests {
    func events(_ s: inout AppState, _ action: Action, now: Double = 1_000) -> [BetaEvent] {
        reduce(&s, action, Dependencies(now: { now }, random: { _ in 0 })).compactMap { (fx: Effect) -> BetaEvent? in
            if case .track(let event) = fx { return event }
            return nil
        }
    }

    @Test func aQuitSendsTheMinutesOpenTheScreenAndTheService() {
        var s = mainMenu()
        let sent = events(&s, .willQuit(openSeconds: 90))
        #expect(sent == [.appClosed(minutes: 1.5, screen: "main_menu", service: .spotify)])
        #expect(sent.first?.name == "app_closed")
        #expect(sent.first?.properties == [
            "minutes": .decimal(1.5), "screen": .text("main_menu"), "service": .text("spotify"),
            "plays": .number(0), "pauses": .number(0), "skips": .number(0), "longest_pause_s": .number(0),
            "stops_playing": .number(0), "stops_paused": .number(0), "outside_music_s": .number(0),
        ])
    }

    @Test func withNoOpenTimeTheMinutesAreLeftOut() {
        var s = mainMenu()
        let sent = events(&s, .willQuit(openSeconds: nil))
        #expect(sent == [.appClosed(minutes: nil, screen: "main_menu", service: .spotify)])
        #expect(sent.first?.properties["minutes"] == nil)
    }

    @Test func itNamesOnlyTheKindOfScreenNeverTheList() {
        var s = mainMenu()
        s.stack.append(Frame(screen: .tracks(playlist: "My secret list")))
        #expect(events(&s, .willQuit(openSeconds: 60)) == [.appClosed(minutes: 1, screen: "songs", service: .spotify)])
        s.stack.append(Frame(screen: .now))
        s.service = .local
        #expect(events(&s, .willQuit(openSeconds: 60)) == [.appClosed(minutes: 1, screen: "now_playing", service: .local)])
    }

    @Test func itComesAfterTheDayOfTheSameQuit() {
        var s = mainMenu()
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "l0"); s.isPlaying = true
        _ = events(&s, .position(1, generation: s.playGen), now: 1_000)
        let sent = events(&s, .willQuit(openSeconds: 30), now: 1_010)
        #expect(sent.map(\.name) == ["day_active", "app_closed"])
    }

    @Test func everyScreenHasAShortFixedName() {
        let screens: [Screen] = [
            .login, .auth, .main, .playlists, .albums, .tracks(playlist: "x"), .settings, .confirm, .about, .now, .coverFlow,
            .albumPanel(album: "x"), .hello, .color, .spotifyApp, .yourMusic, .loginFailed, .loggedIn, .premium, .pickMusic,
            .accessOff, .licenses, .license(3), .artists, .betaSoon, .betaEnded, .betaNew, .activate, .activation, .noSongs, .search,
        ]
        let names = screens.map(\.eventName)
        #expect(Set(names).count == screens.count)
        #expect(names.allSatisfy { $0.allSatisfy { $0.isLowercase || $0 == "_" } })
    }
}
