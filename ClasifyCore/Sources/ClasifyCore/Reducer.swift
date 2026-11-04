import Foundation

public enum Action: Equatable, Sendable {
    case wheel(Int)  // detents, + is clockwise
    case select, menu, play, next, prev
    case tick  // drives toast and overlay timers
    /// A load finished. `library` is nil when the fetch failed.
    case loaded(token: Int, library: [Playlist]?)
    /// The app started. It tries to log in again with the stored login.
    case launch
    /// Login finished for the attempt whose token is on the `.auth` frame. `ok` is false when it failed.
    case authDone(token: Int, ok: Bool)
    /// The restore that `.launch` started finished.
    case restored(token: Int, ok: Bool)
    case offline(Bool)
    case expire
    case reset
    /// Reported by the playback engine.
    /// Each carries the `generation` of the `.load` it is about, so a late callback from an earlier load is ignored.
    /// `.trackEnded` means the engine stopped at the end of the context.
    case position(Double, generation: Int), trackEnded(generation: Int)
    /// The engine moved on to another track in the same context (its own next, prev or auto-advance).
    case trackChanged(String, generation: Int)
    /// The engine can't play the load with this `generation`. The message is shown as a toast.
    case playbackFailed(String, generation: Int)
}

/// What the reducer asks the `Player` to do. The `Store` runs these.
public enum Effect: Equatable, Sendable {
    /// `context` is the playlist ID the track plays from. The engine uses it as the Spotify play context.
    case load(trackID: String, context: String?, autoplay: Bool, generation: Int)
    case pause, resume, stop
    /// The engine owns the play order of a context: it picks the next and previous track.
    case next, prev
    /// Sent when the setting changes and before each load, so the engine's order follows Clasify's settings.
    case setShuffle(Bool), setRepeat(RepeatMode)
    case seek(Double, generation: Int)  // a seek starts a new generation too
    case setVolume(Int)
    /// Fetch the library; the result comes back as `.loaded(token:library:)` with this token.
    case fetchLibrary(token: Int)
    /// Log in through the browser; the result comes back as `.authDone` with this token.
    case logIn(token: Int)
    case cancelLogIn
    /// Log in with the stored login; the result comes back as `.restored` with this token.
    case restoreSession(token: Int)
    /// Forget the stored login.
    case logOut
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
    func load(_ screen: Screen) {
        s.tok += 1
        s.stack.append(Frame(screen: screen, loading: true, token: s.tok))
        fx.append(.fetchLibrary(token: s.tok))
    }
    func loadTrack(_ id: String, autoplay: Bool) {
        s.playGen += 1
        fx.append(.load(trackID: id, context: s.current?.playlist, autoplay: autoplay, generation: s.playGen))
    }
    func seek(_ t: Double) { s.playGen += 1; fx.append(.seek(t, generation: s.playGen)) }  // callbacks from before the seek go stale
    func play(_ pl: String, _ id: String) {
        s.current = TrackRef(playlist: pl, track: id)
        s.t = 0; s.isPlaying = true; s.nowMode = .volume
        s.stack.append(Frame(screen: .now))
        fx.append(.setShuffle(s.shuffle)); fx.append(.setRepeat(s.repeatMode))
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
    func shuffleLiked() {
        let liked = s.tracks(in: Playlist.likedSongsID)
        guard !liked.isEmpty else { return }
        s.shuffle = true  // before play, so the engine gets shuffle on with the load
        play(Playlist.likedSongsID, liked[env.random(liked.count)].id)
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
                    seek(s.t)
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
                fx.append(.fetchLibrary(token: s.tok))
                return
            }
            guard s.top.screen.isList, !s.top.loading else { return }
            let rows = s.rows(for: s.top)
            guard rows.indices.contains(s.top.sel) else { return }
            switch rows[s.top.sel] {
            case .logIn:
                s.authAttempt += 1
                s.stack.append(Frame(screen: .auth, token: s.authAttempt))
                fx.append(.logIn(token: s.authAttempt))
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
            case .shuffle: s.shuffle.toggle(); fx.append(.setShuffle(s.shuffle))
            case .repeatMode: s.repeatMode = s.repeatMode.next; fx.append(.setRepeat(s.repeatMode))
            case .skin:
                s.skin = s.skin.next
                toast(s.skin == .pocket ? "Pocket skin" : "Window switches to \(s.skin.rawValue) skin")
            case .albumArt: s.showArt.toggle()
            case .clicker: s.clicker.toggle()
            case .about: s.stack.append(Frame(screen: .about))
            case .logOut: s.stack.append(Frame(screen: .confirm))
            case .cancel: s.stack.removeLast()
            case .confirmLogOut: signOut("Logged out"); fx.append(.logOut)
            }

        case .menu:
            if s.top.screen == .now && s.nowMode == .scrub { s.nowMode = .volume; s.overlayUntil = 0; return }
            // Not in the mockup: a closed browser tab would leave the login waiting forever.
            if s.top.screen == .auth { s.stack.removeLast(); fx.append(.cancelLogIn); return }
            if s.stack.count < 2 { return }
            s.stack.removeLast(); s.nowMode = .volume

        case .play:
            guard s.current != nil else { return toast("Nothing playing yet") }
            if !s.isPlaying && s.offline { return toast("Offline. Can’t resume") }
            s.isPlaying.toggle()
            fx.append(s.isPlaying ? .resume : .pause)

        case .next:
            guard s.current != nil else { return }
            if s.offline { return toast(offlineStart) }  // a skip offline would leave UI and player on different tracks
            fx.append(.next)  // `current` follows when the engine reports `.trackChanged`

        case .prev:
            guard s.current != nil else { return }
            if s.t > 3 { s.t = 0; seek(0) } else if s.offline { toast(offlineStart) } else { fx.append(.prev) }

        case .tick:
            if s.toastUntil > 0 && now > s.toastUntil { s.toast = ""; s.toastUntil = 0 }
            if s.overlayUntil > 0 && now > s.overlayUntil && s.nowMode != .scrub { s.overlayUntil = 0 }

        case .position(let t, let gen):
            if s.current != nil && gen == s.playGen { s.t = t }

        case .trackEnded(let gen):  // the engine already stopped; Repeat One and All never end
            guard s.isPlaying, s.current != nil, gen == s.playGen else { return }
            s.isPlaying = false; s.t = 0

        case .trackChanged(let id, let gen):
            // Same playlist. A track that is not in our copy of it still shows as current, by ID.
            guard s.current != nil, gen == s.playGen, s.current?.track != id else { return }
            s.current?.track = id; s.t = 0

        case .playbackFailed(let msg, let gen):
            guard s.current != nil, gen == s.playGen else { return }
            s.isPlaying = false
            toast(msg)

        case .loaded(let token, let library):
            guard s.top.loading, s.top.token == token else { return }  // stale load
            if let library { s.library = library }
            s.top.loading = false
            s.top.error = s.offline || library == nil
            if s.shuffleToken == token && !s.top.error {
                s.shuffleToken = nil
                shuffleLiked()
            }

        case .launch:
            guard !s.signedIn, s.stack == [Frame(screen: .login)] else { return }
            s.authAttempt += 1; s.restoring = true
            fx.append(.restoreSession(token: s.authAttempt))

        case .restored(let token, let ok):
            guard s.restoring, s.authAttempt == token else { return }  // from before a reset
            s.restoring = false
            if ok { s.stack = [Frame(screen: .main)]; s.signedIn = true }

        case .authDone(let token, let ok):
            guard s.top.screen == .auth, s.top.token == token else { return }  // stale attempt
            // A login that worked counts even if the app went offline since: its token is saved.
            if !ok { s.stack.removeLast(); return toast("Can’t reach Spotify") }
            s.stack = [Frame(screen: .main)]; s.signedIn = true
            toast("Signed in")

        case .offline(let on):
            if on && s.isPlaying { s.isPlaying = false; fx.append(.pause); toast("Connection lost. Paused") }
            s.offline = on

        case .expire:
            // Forget the stored login too, so that a later .launch does not restore it.
            if s.signedIn { signOut("Session expired. Log in again"); fx.append(.logOut) }

        case .reset:
            stop()
            let (tok, gen, auth) = (s.tok, s.playGen, s.authAttempt)  // keep counters so callbacks from before the reset stay stale
            s = AppState()
            s.tok = tok; s.playGen = gen; s.authAttempt = auth
        }
    }
    apply()
    return fx
}
