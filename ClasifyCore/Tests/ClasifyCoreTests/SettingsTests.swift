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
    #expect(Settings().menuBar)  // card AN.1, 346: the menu bar icon is On by default
    var fresh = Settings()
    fresh.arrived = false  // a new Mac has not seen the arrival (change 288)
    #expect(Settings(from: FakeSettings()) == fresh)
    #expect(Settings() == AppState().settings)
}

/// Jason 15:33 JST 11-22: Black is the default color. A Mac that set up before, with no saved
/// color, set up on Silver and stays Silver.
@Test func blackIsTheDefaultColorAndAnOldSetUpMacStaysSilver() {
    #expect(AppState().deviceColor == .black && Settings().deviceColor == .black)
    #expect(Settings(from: FakeSettings()).deviceColor == .black)  // a fresh Mac
    let old = FakeSettings()
    old.values = ["setup.done": "true"]
    #expect(Settings(from: old).deviceColor == .silver)
    old.values["settings.deviceColor"] = "Black"
    #expect(Settings(from: old).deviceColor == .black)  // a saved color stays
    old.values = ["setup.done": "false"]
    #expect(Settings(from: old).deviceColor == .black)  // setup not done: the new default
}

@Test func settingsLoadTheSavedValuesAndSkipUnknownOnes() {
    let store = FakeSettings()
    var saved = Settings()
    saved.shuffle = true; saved.repeatMode = .one; saved.albumArt = .nowPlaying; saved.deviceColor = .black; saved.clicker = false
    saved.nowPlayingBar = true
    saved.menuBar = false
    saved.service = .appleMusic
    saved.setupDone = true
    saved.hintsDone = [.menu]
    saved.tourOn = true; saved.tourHides = [.tourPlay: 2, .tourNext: 1]
    saved.save(to: store)
    #expect(store.values == [
        "settings.shuffle": "true", "settings.repeat": "One",
        "settings.albumArt": "Now Playing", "settings.deviceColor": "Black", "settings.clicker": "false",
        "settings.nowPlayingBar": "true", "settings.menuBar": "false", "settings.service": "Apple Music", "setup.done": "true", "hints.done": "menu",
        "hints.tour": "true", "hints.hides": "tour.next:1,tour.play:2", "arrive.done": "true",
        "activate.done": "false",
    ])
    #expect(Settings(from: store) == saved)
    store.values = [
        "settings.shuffle": "yes", "settings.repeat": "Twice", "settings.albumArt": "On", "settings.deviceColor": "Gold",
        "settings.clicker": "1", "settings.menuBar": "no", "settings.service": "Tidal", "setup.done": "yes", "hints.done": "later",
        "hints.tour": "yes", "hints.hides": "later:2,tour.play:x", "arrive.done": "yes",
    ]
    var defaults = Settings()
    defaults.arrived = false
    #expect(Settings(from: store) == defaults)  // unknown values give the defaults
}

@MainActor @Test func storeLoadsSettingsAtLaunchAndSavesThemWhenTheyChange() {
    let saved = FakeSettings()
    saved.values = ["settings.albumArt": "Off", "settings.clicker": "false", "settings.repeat": "One", "arrive.done": "true"]
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

/// Change 288: the arrival shows once ever. Its own key, so a new setup does not show it again.
@MainActor @Test func storeSavesTheArrivalAndKeepsItThroughAReset() {
    let saved = FakeSettings()
    saved.values = ["setup.done": "true"]  // an install from before change 288
    let store = Store(player: FakePlayer(), library: FakeLibrary(), state: mainMenu(), env: Dependencies(now: { 0 }, random: { _ in 0 }), settings: saved)
    #expect(!store.state.arrived)  // it sees the arrival once
    store.send(.arrived)
    #expect(saved.values["arrive.done"] == "true")
    saved.values["setup.done"] = nil
    #expect(Settings(from: saved).arrived)  // deleting setup.done alone does not show it again
    store.send(.reset)
    #expect(store.state.arrived && saved.values["arrive.done"] == "true")
}
