#if DEBUG
import ClasifyCore
import Foundation

/// CLA-202 spike: one heavy reducer path (login, main menu, Playlists, a playlist, play), with
/// a fake player and library, to check the reducer's stack on the phone. A crash is the result.
enum ReducerRun {
    static let songs = (0..<8).map { Track(id: "f\($0)", title: "f\($0)", artist: "x", duration: 30) }
    static let listInfo = Playlist(id: "focus", name: "Focus", tracks: [], trackCount: 8)

    /// The state of a later launch: setup done, activated, hints done (as the tests' `afterSetup`).
    static func launched() -> AppState {
        var s = AppState()
        s.setupDone = true
        s.activated = true
        s.hintsDone = Set(Hint.allCases)
        return s
    }

    /// The real `Store` on the main thread, its effects through the fakes.
    @MainActor static func storeOnMain() async -> String {
        let player = FakePlayer(), library = FakeLibrary()
        let store = Store(player: player, library: library, state: launched())
        let clock = ContinuousClock.now
        func step(_ action: Action) async {
            store.send(action)
            try? await Task.sleep(for: .milliseconds(200))  // the fakes answer at once; the store's tasks deliver
        }
        for action: Action in [.select, .select, .wheel(1), .select, .select, .select] { await step(action) }
        let ok = player.loads == 1 && store.state.current != nil && store.state.top.screen == .now
        return ok ? "pass in \(clock.duration(to: .now)) (1.2 s of it waits)" : "no crash, but ended on \(store.state.top.screen), loads \(player.loads)"
    }

    /// `reduce` alone, as the core tests run it: login, main menu, Playlists, Focus, play.
    nonisolated static func reduceOnly() -> String {
        var s = launched()
        let env = Dependencies(now: { 100 }, random: { _ in 0 })
        let actions: [Action] = [
            .select, .authDone(token: 1, ok: true), .select,
            .wheel(1), .select, .playlistsLoaded(token: 1, playlists: [listInfo]),
            .select, .tracksLoaded(token: 2, playlist: "focus", tracks: songs), .select,
        ]
        let clock = ContinuousClock.now
        let effects = actions.flatMap { reduce(&s, $0, env) }
        let loaded = effects.contains { if case .load = $0 { true } else { false } }
        return loaded && s.current != nil ? "pass in \(clock.duration(to: .now))" : "no crash, but ended on \(s.top.screen)"
    }

    /// `reduceOnly` on a new thread with a 512 KB stack (a secondary thread's default).
    static func onSmallThread() async -> String {
        await withCheckedContinuation { (done: CheckedContinuation<String, Never>) in
            let thread = Thread { done.resume(returning: reduceOnly()) }
            thread.stackSize = 512 * 1024
            thread.start()
        }
    }
}

@MainActor final class FakePlayer: Player {
    var loads = 0
    func load(trackID: String, context: String?, autoplay: Bool, generation: Int) { loads += 1 }
    func pause() {}
    func resume() {}
    func stop() {}
    func next(generation: Int) {}
    func prev(generation: Int) {}
    func setShuffle(_ on: Bool) {}
    func setRepeat(_ mode: RepeatMode) {}
    func seek(to seconds: Double, generation: Int) {}
    func setVolume(_ percent: Int) {}
}

@MainActor final class FakeLibrary: Library {
    var onProgress: (@MainActor (_ playlist: String, _ done: Int, _ total: Int, _ albums: Int) -> Void)?
    func playlists() async -> [Playlist]? { [ReducerRun.listInfo] }
    func tracks(of playlist: String) async -> [Track]? { playlist == "focus" ? ReducerRun.songs : [] }
    func rereadPlaylists() async -> [Playlist]? { await playlists() }
    func reread(_ playlist: String) async -> [Track]? { await tracks(of: playlist) }
    func track(_ id: String) async -> Track? { ReducerRun.songs.first { $0.id == id } }
    func prefetch() async -> LibraryCount { LibraryCount(playlists: [ReducerRun.listInfo], songs: ReducerRun.songs) }
    func logIn(page: String?) async -> LoginResult { .ok }
    func cancelLogIn() async {}
    func restoreSession() async -> LoginResult { .ok }
    func logOut() {}
}
#endif
