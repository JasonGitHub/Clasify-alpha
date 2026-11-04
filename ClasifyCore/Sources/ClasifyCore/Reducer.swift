import Foundation

public enum Action: Equatable, Sendable {
    case wheel(Int)  // detents, + is clockwise
    case select, menu, play, next, prev
    case tick  // drives toast and overlay timers
    /// A load finished. `library` is nil when the fetch failed.
    case loaded(token: Int, library: [Playlist]?)
    case authDone
    case offline(Bool)
    case expire
    case reset
    /// Reported by the playback engine.
    /// Each carries the `generation` of the `.load` it is about, so a late callback from an earlier load is ignored.
    case position(Double, generation: Int), trackEnded(generation: Int)
}

/// What the reducer asks the `Player` to do. The `Store` runs these.
public enum Effect: Equatable, Sendable {
    case load(trackID: String, autoplay: Bool, generation: Int)
    case pause, resume, stop
    case seek(Double)
    case setVolume(Int)
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

public let visibleRows = 6

func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { max(lo, min(hi, v)) }

@discardableResult
public func reduce(_ s: inout AppState, _ action: Action, _ env: Dependencies) -> [Effect] {
    let now = env.now()
    var fx: [Effect] = []
    func toast(_ msg: String) { s.toast = msg; s.toastUntil = now + 1.8 }
    func load(_ screen: Screen) { s.tok += 1; s.stack.append(Frame(screen: screen, loading: true, token: s.tok)) }
    func loadTrack(_ id: String, autoplay: Bool) { s.playGen += 1; fx.append(.load(trackID: id, autoplay: autoplay, generation: s.playGen)) }
    func play(_ pl: String, _ id: String) {
        s.current = TrackRef(playlist: pl, track: id)
        s.t = 0; s.isPlaying = true; s.nowMode = .volume
        s.stack.append(Frame(screen: .now))
        loadTrack(id, autoplay: true)
    }
    func stop() {
        if s.current != nil { fx.append(.stop) }
        s.isPlaying = false; s.current = nil; s.t = 0
    }
    func signOut(_ msg: String) {
        stop()
        s.stack = [Frame(screen: .login)]; s.signedIn = false; s.library = []  // library belongs to that account
        toast(msg)
    }
    func advance(_ d: Int) {
        guard let c = s.current else { return }
        let list = s.tracks(in: c.playlist)
        guard let at = list.firstIndex(where: { $0.id == c.track }) else { return stop() }  // gone after a reload
        s.t = 0
        var i = at + d
        if s.shuffle && list.count > 1 {
            i = env.random(list.count - 1)  // any track but the current one
            if i >= at { i += 1 }
        } else if i >= list.count {
            guard s.repeatMode == .all else { s.isPlaying = false; fx += [.pause, .seek(0)]; return }
            i = 0
        } else if i < 0 {
            i = s.repeatMode == .all ? list.count - 1 : 0
        }
        s.current?.track = list[i].id
        loadTrack(list[i].id, autoplay: s.isPlaying)
    }
    func shuffleLiked() {
        let liked = s.tracks(in: Playlist.likedSongsID)
        guard !liked.isEmpty else { return }
        play(Playlist.likedSongsID, liked[env.random(liked.count)].id); s.shuffle = true
    }
    let offlineStart = "Offline. Can’t start playback"

    func apply() {
        switch action {
        case .wheel(let d):
            if s.top.screen == .now {
                guard let c = s.current else { return }
                if s.nowMode == .scrub {
                    s.t = clamp(s.t + Double(d * 5), 0, max((s.track(c)?.duration ?? 0) - 1, 0))
                    s.overlayUntil = now + 2.5
                    fx.append(.seek(s.t))
                } else {
                    s.volume = clamp(s.volume + d * 5, 0, 100)
                    s.overlayUntil = now + 1.5
                    fx.append(.setVolume(s.volume))
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
                if s.shuffleToken == s.top.token { s.shuffleToken = s.tok }  // a pending shuffle follows the retry
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
            case .likedSongs: load(.tracks(playlist: Playlist.likedSongsID))
            case .shuffleSongs:
                if s.offline { return toast(offlineStart) }
                if s.tracks(in: Playlist.likedSongsID).isEmpty {  // not fetched yet: load, then shuffle
                    load(.tracks(playlist: Playlist.likedSongsID)); s.shuffleToken = s.tok
                } else {
                    shuffleLiked()
                }
            case .settings: s.stack.append(Frame(screen: .settings))
            case .playlist(let id): load(.tracks(playlist: id))
            case .track(let id):
                if s.offline { return toast(offlineStart) }
                if case .tracks(let pl) = s.top.screen { play(pl, id) }
            case .shuffle: s.shuffle.toggle()
            case .repeatMode: s.repeatMode = s.repeatMode.next
            case .eq: s.eq = s.eq.next
            case .skin:
                s.skin = s.skin.next
                toast(s.skin == .pocket ? "Pocket skin" : "Window switches to \(s.skin.rawValue) skin")
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
            fx.append(s.isPlaying ? .resume : .pause)

        case .next:
            guard s.current != nil else { return }
            if s.offline { return toast(offlineStart) }  // a load offline would leave UI and player on different tracks
            advance(1)

        case .prev:
            guard s.current != nil else { return }
            if s.t > 3 { s.t = 0; fx.append(.seek(0)) } else if s.offline { toast(offlineStart) } else { advance(-1) }

        case .tick:
            if s.toastUntil > 0 && now > s.toastUntil { s.toast = ""; s.toastUntil = 0 }
            if s.overlayUntil > 0 && now > s.overlayUntil && s.nowMode != .scrub { s.overlayUntil = 0 }

        case .position(let t, let gen):
            if s.current != nil && gen == s.playGen { s.t = t }

        case .trackEnded(let gen):
            guard s.isPlaying, let c = s.current, gen == s.playGen else { return }
            if s.repeatMode == .one { s.t = 0; loadTrack(c.track, autoplay: true) } else { advance(1) }

        case .loaded(let token, let library):
            guard s.top.loading, s.top.token == token else { return }  // stale load
            if let library { s.library = library }
            s.top.loading = false
            s.top.error = s.offline || library == nil
            if s.shuffleToken == token && !s.top.error {
                s.shuffleToken = nil
                shuffleLiked()
            }

        case .authDone:
            guard s.top.screen == .auth else { return }
            if s.offline { s.stack.removeLast(); return toast("Can’t reach Spotify") }
            s.stack = [Frame(screen: .main)]; s.signedIn = true
            toast("Signed in")

        case .offline(let on):
            if on && s.isPlaying { s.isPlaying = false; fx.append(.pause); toast("Connection lost. Paused") }
            s.offline = on

        case .expire:
            if s.signedIn { signOut("Session expired. Log in again") }

        case .reset:
            stop()
            let (tok, gen) = (s.tok, s.playGen)  // keep tokens unique so callbacks from before the reset stay stale
            s = AppState()
            s.tok = tok; s.playGen = gen
        }
    }
    apply()
    return fx
}
