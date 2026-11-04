import Foundation

public enum Action: Equatable, Sendable {
    case wheel(Int)  // detents, + is clockwise
    case select, menu, play, next, prev
    case tick  // every `tickInterval` seconds
    /// A load finished. `library` is nil when the fetch failed.
    case loaded(token: Int, library: [Playlist]?)
    case authDone
    case offline(Bool)
    case expire
    case reset
}

/// Side inputs the reducer reads, injected so tests are deterministic.
public struct Dependencies: Sendable {
    public var now: @Sendable () -> Double
    public var random: @Sendable (Int) -> Int  // uniform in 0..<n

    public init(now: @escaping @Sendable () -> Double, random: @escaping @Sendable (Int) -> Int) {
        self.now = now; self.random = random
    }

    public static let live = Dependencies(
        now: { Date().timeIntervalSinceReferenceDate },
        random: { Int.random(in: 0..<$0) })
}

public let tickInterval = 0.25
public let visibleRows = 6

func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { max(lo, min(hi, v)) }

public func reduce(_ s: inout AppState, _ action: Action, _ env: Dependencies) {
    let now = env.now()
    func toast(_ msg: String) { s.toast = msg; s.toastUntil = now + 1.8 }
    func load(_ screen: Screen) { s.tok += 1; s.stack.append(Frame(screen: screen, loading: true, token: s.tok)) }
    func play(_ pl: Int, _ i: Int) {
        s.current = TrackRef(playlist: pl, track: i)
        s.t = 0; s.isPlaying = true; s.nowMode = .volume
        s.stack.append(Frame(screen: .now))
    }
    func signOut(_ msg: String) {
        s.stack = [Frame(screen: .login)]
        s.signedIn = false; s.isPlaying = false; s.current = nil; s.t = 0
        toast(msg)
    }
    func advance(_ d: Int) {
        guard let c = s.current else { return }
        let n = s.tracks(in: c.playlist).count
        s.t = 0
        if s.shuffle && n > 1 {
            let i = env.random(n - 1)  // any track but the current one
            s.current?.track = i >= c.track ? i + 1 : i
            return
        }
        let i = c.track + d
        if i >= n && s.repeatMode != .all { s.isPlaying = false; return }
        s.current?.track = i >= n ? 0 : max(i, 0)
    }
    let offlineStart = "Offline. Can’t start playback"

    switch action {
    case .wheel(let d):
        if s.top.screen == .now {
            guard let c = s.current else { return }
            if s.nowMode == .scrub {
                s.t = clamp(s.t + Double(d * 5), 0, max((s.track(c)?.duration ?? 0) - 1, 0))
                s.overlayUntil = now + 2.5
            } else {
                s.volume = clamp(s.volume + d * 5, 0, 100)
                s.overlayUntil = now + 1.5
            }
            return
        }
        guard s.top.screen.isList, !s.top.loading, !s.top.error else { return }
        let n = s.rows(for: s.top).count
        guard n > 0 else { return }
        let sel = clamp(s.top.sel + d, 0, n - 1)
        s.top.off = clamp(s.top.off, sel - visibleRows + 1, sel)
        s.top.sel = sel

    case .select:
        if s.top.screen == .now {
            s.nowMode = s.nowMode == .volume ? .scrub : .volume
            s.overlayUntil = now + 2.5
            return
        }
        if s.top.error {  // retry
            s.tok += 1
            s.top.loading = true; s.top.error = false; s.top.token = s.tok
            return
        }
        guard s.top.screen.isList, !s.top.loading else { return }
        let rows = s.rows(for: s.top)
        guard rows.indices.contains(s.top.sel) else { return }
        switch rows[s.top.sel] {
        case .logIn: s.stack.append(Frame(screen: .auth))
        case .nowPlaying: s.stack.append(Frame(screen: .now)); s.nowMode = .volume
        case .playlists: load(.playlists)
        case .likedSongs: load(.tracks(playlist: 0))
        case .shuffleSongs:
            if s.offline { return toast(offlineStart) }
            let n = s.tracks(in: 0).count
            guard n > 0 else { return }
            play(0, env.random(n)); s.shuffle = true
        case .settings: s.stack.append(Frame(screen: .settings))
        case .playlist(let i): load(.tracks(playlist: i))
        case .track(let i):
            if s.offline { return toast(offlineStart) }
            if case .tracks(let pl) = s.top.screen { play(pl, i) }
        case .shuffle: s.shuffle.toggle()
        case .repeatMode: s.repeatMode = s.repeatMode.next
        case .eq: s.eq = s.eq.next
        case .skin:
            s.skin = s.skin.next
            toast(s.skin == .pocket ? "Pocket skin" : "Window switches to \(s.skin.rawValue) skin")
        case .engine:
            s.engine = s.engine.next
            toast(s.engine == .builtIn ? "Built-in playback" : "Plays through the Spotify app")
        case .albumArt: s.showArt.toggle()
        case .clicker: s.clicker.toggle()
        case .about: s.stack.append(Frame(screen: .about))
        case .logOut: s.stack.append(Frame(screen: .confirm))
        case .cancel: s.stack.removeLast()
        case .confirmLogOut: signOut("Logged out")
        }

    case .menu:
        if s.top.screen == .now && s.nowMode == .scrub { s.nowMode = .volume; s.overlayUntil = 0; return }
        if s.top.screen == .auth || s.stack.count < 2 { return }
        s.stack.removeLast(); s.nowMode = .volume

    case .play:
        guard s.current != nil else { return toast("Nothing playing yet") }
        if !s.isPlaying && s.offline { return toast("Offline. Can’t resume") }
        s.isPlaying.toggle()

    case .next:
        advance(1)

    case .prev:
        guard s.current != nil else { return }
        if s.t > 3 { s.t = 0 } else { advance(-1) }

    case .tick:
        if s.toastUntil > 0 && now > s.toastUntil { s.toast = ""; s.toastUntil = 0 }
        if s.overlayUntil > 0 && now > s.overlayUntil && s.nowMode != .scrub { s.overlayUntil = 0 }
        guard s.isPlaying, let c = s.current, let track = s.track(c) else { return }
        let t = s.t + tickInterval
        if t < track.duration { s.t = t } else if s.repeatMode == .one { s.t = 0 } else { advance(1) }

    case .loaded(let token, let library):
        guard s.top.loading, s.top.token == token else { return }  // stale load
        if let library { s.library = library }
        s.top.loading = false
        s.top.error = s.offline || library == nil

    case .authDone:
        guard s.top.screen == .auth else { return }
        if s.offline { s.stack.removeLast(); return toast("Can’t reach Spotify") }
        s.stack = [Frame(screen: .main)]; s.signedIn = true
        toast("Signed in")

    case .offline(let on):
        if on && s.isPlaying { s.isPlaying = false; toast("Connection lost. Paused") }
        s.offline = on

    case .expire:
        if s.signedIn { signOut("Session expired. Log in again") }

    case .reset:
        s = AppState()
    }
}
