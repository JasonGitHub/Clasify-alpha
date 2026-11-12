import Testing
@testable import ClasifyCore

/// UserDefaults in memory: string values by key.
final class FakeSettings: SettingsStore {
    var values: [String: String] = [:]
    var writes = 0
    func string(forKey key: String) -> String? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value as? String; writes += 1 }
}

@Test func settingsLoadTheDefaultsWhenNothingIsSaved() {
    #expect(Settings(from: FakeSettings()) == Settings())
    #expect(Settings() == AppState().settings)
}

@Test func settingsLoadTheSavedValuesAndSkipUnknownOnes() {
    let store = FakeSettings()
    var saved = Settings()
    saved.shuffle = true; saved.repeatMode = .one; saved.albumArt = .nowPlaying; saved.deviceColor = .black; saved.clicker = false
    saved.nowPlayingBar = true
    saved.setupDone = true
    saved.hintsDone = [.menu]
    saved.tourOn = true; saved.tourHides = [.tourPlay: 2, .tourNext: 1]
    saved.save(to: store)
    #expect(store.values == [
        "settings.shuffle": "true", "settings.repeat": "One",
        "settings.albumArt": "Now Playing", "settings.deviceColor": "Black", "settings.clicker": "false",
        "settings.nowPlayingBar": "true", "setup.done": "true", "hints.done": "menu",
        "hints.tour": "true", "hints.hides": "tour.next:1,tour.play:2",
    ])
    #expect(Settings(from: store) == saved)
    store.values = [
        "settings.shuffle": "yes", "settings.repeat": "Twice", "settings.albumArt": "On", "settings.deviceColor": "Gold",
        "settings.clicker": "1", "setup.done": "yes", "hints.done": "later",
        "hints.tour": "yes", "hints.hides": "later:2,tour.play:x",
    ]
    #expect(Settings(from: store) == Settings())  // unknown values give the defaults
}

@MainActor @Test func storeLoadsSettingsAtLaunchAndSavesThemWhenTheyChange() {
    let saved = FakeSettings()
    saved.values = ["settings.albumArt": "Off", "settings.clicker": "false", "settings.repeat": "One"]
    let player = FakePlayer()
    let store = Store(player: player, library: FakeLibrary(), state: mainMenu(), env: Dependencies(now: { 0 }, random: { _ in 0 }), settings: saved)
    #expect(store.state.albumArt == .off && !store.state.clicker && !store.state.shuffle && store.state.repeatMode == .one)
    #expect(player.calls == ["shuffle false", "repeat One"])  // the player knows them before it plays
    store.send(.wheel(1))  // no setting changes: nothing is written
    #expect(saved.writes == 0)
    store.send(.toggleShuffle)
    #expect(saved.values["settings.shuffle"] == "true" && saved.values["settings.albumArt"] == "Off")
    store.send(.cycleRepeat)
    #expect(saved.values["settings.repeat"] == "Off")  // One, then Off
    store.send(.reset)  // the saved settings stay
    #expect(store.state.shuffle && store.state.albumArt == .off)
    #expect(Settings(from: saved) == store.state.settings)
}
