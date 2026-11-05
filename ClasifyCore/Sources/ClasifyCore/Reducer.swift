import Foundation

public enum Action: Equatable, Sendable {
    case wheel(Int)  // detents, + is clockwise. Quick steps on a list move more rows: see `WheelSpeed`.
    case select, menu, play, next, prev
    /// The shuffle and repeat icons on Now Playing, and the S and R keys.
    case toggleShuffle, cycleRepeat
    case tick  // drives toast and overlay timers
    /// The playlist list was read: names and track counts, no tracks. nil when the read failed.
    case playlistsLoaded(token: Int, playlists: [Playlist]?)
    /// The tracks of one playlist (or Liked Songs) were read. nil when the read failed.
    case tracksLoaded(token: Int, playlist: String, tracks: [Track]?)
    /// The app started. It tries to log in again with the stored login.
    case launch
    /// Login finished for the attempt whose token is on the `.auth` frame. `ok` is false when it failed.
    case authDone(token: Int, ok: Bool)
    /// The restore that `.launch` started finished.
    case restored(token: Int, ok: Bool)
    case offline(Bool)
    /// Signs out and forgets the stored login. Send it only when Spotify refuses the refresh
    /// token (it was revoked). Never send it when the hourly access token expires or the
    /// network is down: a restore handles those, and this would delete a working login.
    case expire
    case reset
    /// Reported by the playback engine.
    /// Each carries the `generation` of the `.load` it is about, so a late callback from an earlier load is ignored.
    /// `.trackEnded` means the engine stopped at the end of the context.
    case position(Double, generation: Int), trackEnded(generation: Int)
    /// The engine moved on to another track in the same context (its own next, prev or auto-advance).
    /// `playing` is the engine's play state after the change.
    case trackChanged(String, playing: Bool, generation: Int)
    /// The details of one track that `.readTrack` asked for. nil when the read failed.
    case trackRead(String, Track?)
    /// The engine found a track that Spotify already plays on this Mac, with no load from
    /// Clasify, for example at launch. It becomes `current`, and Now Playing does not open.
    /// `playlist` is nil when the context is not a playlist or Liked Songs. A load wins.
    case adopted(track: String, playlist: String?, playing: Bool, position: Double, generation: Int)
    /// The engine can't play the load with this `generation`. The message is shown as a toast.
    case playbackFailed(String, generation: Int)
    /// The load with this `generation`, which `.select` started, did not start to play.
    /// Clasify shows again what it showed before the load, or nothing. The message is a toast.
    case loadFailed(String, generation: Int)
}

/// What the reducer asks the `Player` to do. The `Store` runs these.
public enum Effect: Equatable, Sendable {
    /// `context` is the playlist ID the track plays from. The engine uses it as the Spotify play context.
    case load(trackID: String, context: String?, autoplay: Bool, generation: Int)
    case pause, resume, stop
    /// The engine owns the play order of a context: it picks the next and previous track.
    case next(generation: Int), prev(generation: Int)  // a skip starts a new generation too
    /// Sent when the setting changes and before each load, so the engine's order follows Clasify's settings.
    case setShuffle(Bool), setRepeat(RepeatMode)
    case seek(Double, generation: Int)  // a seek starts a new generation too
    case setVolume(Int)
    /// Read the playlist list; the result comes back as `.playlistsLoaded` with this token.
    case fetchPlaylists(token: Int)
    /// Read one playlist's tracks; the result comes back as `.tracksLoaded` with this token.
    case fetchTracks(token: Int, playlist: String)
    /// Read Liked Songs and the playlist list in the background after a login, so that the
    /// first open is fast. Nothing comes back: the library keeps the result for the next fetch.
    case prefetch
    /// Log in through the browser; the result comes back as `.authDone` with this token.
    case logIn(token: Int)
    case cancelLogIn
    /// Log in with the stored login; the result comes back as `.restored` with this token.
    case restoreSession(token: Int)
    /// Forget the stored login.
    case logOut
    /// Read one track's details, for a track that Spotify plays from outside the library.
    /// The result comes back as `.trackRead`.
    case readTrack(String)
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

/// Rows of 22.5 points fill the list under the title bar, as in the mockup.
public let visibleRows = 8
/// Song lists show two lines a row (title and artist), so fewer rows fit.
public let trackRows = 5
/// Seconds without a wheel turn before a scrub, shuffle or repeat slider goes back to the progress bar.
public let sliderTimeout = 6.0
/// The most tracks from outside the library that `AppState.extraTracks` keeps.
public let extraTrackLimit = 50
/// Seconds that a list's scroll bar shows after a wheel step or a screen change.
public let scrollBarTime = 1.5

func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { max(lo, min(hi, v)) }

@discardableResult
public func reduce(_ s: inout AppState, _ action: Action, _ env: Dependencies) -> [Effect] {
    let now = env.now()
    var fx: [Effect] = []
    func toast(_ msg: String) { s.toast = msg; s.toastUntil = now + 1.8 }
    func fetch(_ screen: Screen) {
        switch screen {
        case .tracks(let id): fx.append(.fetchTracks(token: s.tok, playlist: id))
        default: fx.append(.fetchPlaylists(token: s.tok))
        }
    }
    /// Opens a list screen. Only a list that this session has not read yet loads.
    func open(_ screen: Screen) {
        if s.isLoaded(screen) { return s.stack.append(Frame(screen: screen)) }
        s.tok += 1
        s.stack.append(Frame(screen: screen, loading: true, token: s.tok))
        fetch(screen)
    }
    /// Ends the top frame's load. A pending shuffle starts when the load worked.
    func finishLoad(_ token: Int, ok: Bool) {
        s.top.loading = false
        s.top.error = s.offline || !ok
        if s.shuffleToken == token && !s.top.error {
            s.shuffleToken = nil
            shuffleLiked()
        }
    }
    func loadTrack(_ id: String, autoplay: Bool) {
        s.playGen += 1
        fx.append(.load(trackID: id, context: s.current?.playlist, autoplay: autoplay, generation: s.playGen))
    }
    func seek(_ t: Double) { s.playGen += 1; fx.append(.seek(t, generation: s.playGen)) }  // callbacks from before the seek go stale
    func skip(_ forward: Bool) { s.playGen += 1; fx.append(forward ? .next(generation: s.playGen) : .prev(generation: s.playGen)) }  // and from before the skip
    func play(_ pl: String, _ id: String) {
        if !s.loadPending { s.beforeLoad = s.current.map { BeforeLoad(current: $0, t: s.t, isPlaying: s.isPlaying) } }
        s.loadPending = true
        s.current = TrackRef(playlist: pl, track: id)
        s.t = 0; s.isPlaying = true; s.nowMode = .volume
        s.stack.append(Frame(screen: .now))
        fx.append(.setShuffle(s.shuffle)); fx.append(.setRepeat(s.repeatMode))
        loadTrack(id, autoplay: true)
    }
    /// A current track from outside our copy of the list, such as Spotify's autoplay: read its
    /// details once. A read in flight or a failed read is not started again.
    func readIfUnknown(_ id: String) {
        guard let ref = s.current, s.track(ref) == nil, id.hasPrefix("spotify:track:"), !s.trackReads.contains(id) else { return }
        s.trackReads.insert(id)
        fx.append(.readTrack(id))
    }
    func stop() {
        if s.current != nil { fx.append(.stop) }
        s.isPlaying = false; s.current = nil; s.t = 0; s.beforeLoad = nil; s.loadPending = false
    }
    func signOut(_ msg: String) {
        stop()
        s.stack = [Frame(screen: .login)]; s.signedIn = false  // the library belongs to that account
        s.library = []; s.playlistsLoaded = false; s.loadedTracks = []
        s.extraTracks = []; s.trackReads = []
        toast(msg)
    }
    func shuffleLiked() {
        let liked = s.tracks(in: Playlist.likedSongsID)
        guard !liked.isEmpty else { return }
        s.shuffle = true  // before play, so the engine gets shuffle on with the load
        play(Playlist.likedSongsID, liked[env.random(liked.count)].id)
    }
    let offlineStart = "Offline. Can’t start playback"
    func toggleShuffle() { s.shuffle.toggle(); fx.append(.setShuffle(s.shuffle)) }
    func setRepeat(_ mode: RepeatMode) {
        if mode != s.repeatMode { s.repeatMode = mode; fx.append(.setRepeat(mode)) }
    }

    func apply() {
        switch action {
        case .wheel(let d):
            if s.top.screen == .now {
                guard let c = s.current else { return }
                switch s.nowMode {
                case .scrub:
                    let end = s.track(c).map { max($0.duration - 1, 0) } ?? .infinity  // unknown track: the engine clamps
                    s.t = clamp(s.t + Double(d * 5), 0, end)
                    s.overlayUntil = now + sliderTimeout
                    seek(s.t)
                case .shuffle:  // the slider: Off on the left, Songs on the right
                    s.overlayUntil = now + sliderTimeout
                    if d != 0 && (d > 0) != s.shuffle { toggleShuffle() }
                case .repeatMode:  // the slider: Off, One, All
                    s.overlayUntil = now + sliderTimeout
                    let order = RepeatMode.sliderOrder
                    let i = order.firstIndex(of: s.repeatMode) ?? 0
                    setRepeat(order[clamp(i + d.signum(), 0, order.count - 1)])
                case .volume:
                    s.volume = clamp(s.volume + d * 5, 0, 100)
                    s.overlayUntil = now + 1.5
                    fx.append(.setVolume(s.volume))
                }
                return
            }
            guard s.top.screen.isList, !s.top.loading, !s.top.error else { return }
            let n = s.rows(for: s.top).count
            guard n > 0 else { return }
            // On a list, quick steps move more rows. On Now Playing, a step stays one step.
            let sel = clamp(s.top.sel + d * s.wheelSpeed.rows(at: now), 0, n - 1)
            s.top.off = clamp(s.top.off, sel - s.shownRows + 1, sel)
            s.top.sel = sel
            s.scrollUntil = now + scrollBarTime

        case .select:
            if s.top.screen == .now {
                s.nowMode = s.nowMode.next  // volume, scrub, shuffle, repeat, then volume again
                s.overlayUntil = now + (s.nowMode == .volume ? 1.5 : sliderTimeout)
                return
            }
            if s.top.error {  // retry
                s.tok += 1
                if s.shuffleToken == s.top.token { s.shuffleToken = s.tok }  // a pending shuffle follows the retry
                s.top.loading = true; s.top.error = false; s.top.token = s.tok
                fetch(s.top.screen)
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
            case .playlists: open(.playlists)
            case .likedSongs: open(.tracks(playlist: Playlist.likedSongsID))
            case .shuffleSongs:
                if s.offline { return toast(offlineStart) }
                if s.loadedTracks.contains(Playlist.likedSongsID) {
                    shuffleLiked()
                } else {  // not read yet: load, then shuffle
                    open(.tracks(playlist: Playlist.likedSongsID)); s.shuffleToken = s.tok
                }
            case .settings: s.stack.append(Frame(screen: .settings))
            case .playlist(let id): open(.tracks(playlist: id))
            case .track(let id):
                if s.offline { return toast(offlineStart) }
                if case .tracks(let pl) = s.top.screen { play(pl, id) }
            case .shuffle: toggleShuffle()
            case .repeatMode: setRepeat(s.repeatMode.next)
            case .skin: s.skin = s.skin.next  // not in the Settings rows until Dark and Aqua exist
            case .albumArt: s.showArt.toggle()
            case .clicker: s.clicker.toggle()
            case .about: s.stack.append(Frame(screen: .about))
            case .logOut: s.stack.append(Frame(screen: .confirm))
            case .cancel: s.stack.removeLast()
            case .confirmLogOut: signOut("Logged out"); fx.append(.logOut)
            }

        case .menu:
            if s.top.screen == .now && s.nowMode != .volume { s.nowMode = .volume; s.overlayUntil = 0; return }
            // Not in the mockup: a closed browser tab would leave the login waiting forever.
            if s.top.screen == .auth { s.stack.removeLast(); fx.append(.cancelLogIn); return }
            if s.stack.count < 2 { return }
            s.stack.removeLast(); s.nowMode = .volume

        case .toggleShuffle: toggleShuffle()
        case .cycleRepeat: setRepeat(s.repeatMode.next)

        case .play:
            guard s.current != nil else { return toast("Nothing playing yet") }
            if !s.isPlaying && s.offline { return toast("Offline. Can’t resume") }
            s.isPlaying.toggle()
            fx.append(s.isPlaying ? .resume : .pause)

        case .next:
            guard s.current != nil else { return }
            if s.offline { return toast(offlineStart) }  // a skip offline would leave UI and player on different tracks
            skip(true)  // `current` follows when the engine reports `.trackChanged`

        case .prev:
            guard s.current != nil else { return }
            if s.t > 3 { s.t = 0; seek(0) } else if s.offline { toast(offlineStart) } else { skip(false) }

        case .tick:
            if s.toastUntil > 0 && now > s.toastUntil { s.toast = ""; s.toastUntil = 0 }
            // The volume bar hides, and a slider goes back to the progress bar.
            if s.overlayUntil > 0 && now > s.overlayUntil { s.overlayUntil = 0; s.nowMode = .volume }
            if s.scrollUntil > 0 && now > s.scrollUntil { s.scrollUntil = 0 }

        case .position(let t, let gen):
            if s.current != nil && gen == s.playGen { s.t = t; s.beforeLoad = nil; s.loadPending = false }  // the load plays

        case .trackEnded(let gen):  // the engine already stopped; Repeat One and All never end
            guard s.isPlaying, s.current != nil, gen == s.playGen else { return }
            s.isPlaying = false; s.t = 0

        case .trackChanged(let id, let playing, let gen):
            // Same playlist. A track that is not in our copy of it still shows as current, by ID.
            guard s.current != nil, gen == s.playGen else { return }
            s.isPlaying = playing; s.beforeLoad = nil; s.loadPending = false  // the load plays
            if s.current?.track != id { s.current?.track = id; s.t = 0 }
            readIfUnknown(id)

        case .trackRead(let id, let track):
            // Not asked for in this session, for example a read from before a sign-out.
            guard s.trackReads.contains(id) else { return }
            guard let track else { return }  // failed: the ID stays, so it is not read again
            s.trackReads.remove(id)
            s.extraTracks.removeAll { $0.id == id }
            s.extraTracks.append(track)
            if s.extraTracks.count > extraTrackLimit { s.extraTracks.removeFirst(s.extraTracks.count - extraTrackLimit) }

        case .adopted(let id, let pl, let playing, let t, let gen):
            guard s.current == nil, gen == s.playGen else { return }  // a load or a newer one came first
            s.current = TrackRef(playlist: pl ?? "", track: id)  // "" is no playlist of ours
            s.isPlaying = playing; s.t = t
            if s.top.screen == .main { s.top.sel += 1 }  // the new Now Playing row goes on top: keep the pick
            readIfUnknown(id)

        case .playbackFailed(let msg, let gen):
            guard s.current != nil, gen == s.playGen else { return }
            s.isPlaying = false; s.beforeLoad = nil; s.loadPending = false  // the load, if any, has ended
            toast(msg)

        case .loadFailed(let msg, let gen):
            guard s.current != nil, gen == s.playGen else { return }
            // Show what really plays: the track from before the load, or nothing. If Spotify
            // does not play it as shown, the engine's next report corrects it.
            if let before = s.beforeLoad {
                s.current = before.current; s.t = before.t; s.isPlaying = before.isPlaying
            } else {
                s.current = nil; s.t = 0; s.isPlaying = false
                // No empty Now Playing: back to the list the load came from, with the toast there.
                if s.top.screen == .now && s.stack.count > 1 { s.stack.removeLast(); s.nowMode = .volume; s.overlayUntil = 0 }
            }
            s.beforeLoad = nil; s.loadPending = false
            toast(msg)

        case .playlistsLoaded(let token, let playlists):
            guard s.top.loading, s.top.token == token else { return }  // stale load
            if let playlists {
                // Keep Liked Songs and the tracks already read for playlists that are still there.
                let read = Dictionary(s.library.map { ($0.id, $0.tracks) }, uniquingKeysWith: { a, _ in a })
                let kept = Set(playlists.map(\.id)).union([Playlist.likedSongsID])
                s.loadedTracks = s.loadedTracks.intersection(kept)
                s.library = s.library.filter { $0.id == Playlist.likedSongsID } + playlists.map {
                    var p = $0
                    if s.loadedTracks.contains(p.id) { p.tracks = read[p.id] ?? [] }
                    return p
                }
                s.playlistsLoaded = true
            }
            finishLoad(token, ok: playlists != nil)

        case .tracksLoaded(let token, let id, let tracks):
            guard s.top.loading, s.top.token == token else { return }  // stale load
            if let tracks {
                if let i = s.library.firstIndex(where: { $0.id == id }) {
                    s.library[i].tracks = tracks; s.library[i].trackCount = tracks.count
                } else if id == Playlist.likedSongsID {
                    s.library.insert(Playlist(id: id, name: "Liked Songs", tracks: tracks), at: 0)
                } else {
                    s.library.append(Playlist(id: id, name: "", tracks: tracks))
                }
                s.loadedTracks.insert(id)
            }
            finishLoad(token, ok: tracks != nil)

        case .launch:
            guard !s.signedIn, s.stack == [Frame(screen: .login)] else { return }
            s.authAttempt += 1; s.restoring = true
            fx.append(.restoreSession(token: s.authAttempt))

        case .restored(let token, let ok):
            guard s.restoring, s.authAttempt == token else { return }  // from before a reset
            s.restoring = false
            if ok { s.stack = [Frame(screen: .main)]; s.signedIn = true; fx.append(.prefetch) }

        case .authDone(let token, let ok):
            guard s.top.screen == .auth, s.top.token == token else { return }  // stale attempt
            // A login that worked counts even if the app went offline since: its token is saved.
            if !ok { s.stack.removeLast(); return toast("Can’t reach Spotify") }
            s.stack = [Frame(screen: .main)]; s.signedIn = true
            fx.append(.prefetch)
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
            let nav = s.navSeq  // keep the screen's identity, so the skin does not slide the reset screen in
            s = AppState()
            s.tok = tok; s.playGen = gen; s.authAttempt = auth; s.navSeq = nav
        }
    }
    let before = (s.stack.count, s.top.screen, s.top.loading)
    let wasAuth = s.top.screen == .auth
    apply()
    // A new screen slides in: from the right when it opens, from the left on a way back.
    // The main menu after the login wait counts as opening. A reset does not slide.
    if case .reset = action {} else if (s.stack.count, s.top.screen) != (before.0, before.1) {
        s.navSeq += 1
        s.navForward = s.stack.count >= before.0 || (wasAuth && s.top.screen == .main)
    }
    // A list shows its scroll bar for a moment when it appears: on a new screen, or when its
    // load ends. A reset starts with no bar.
    let listShows = s.top.screen.isList && !s.top.loading && !s.top.error
    if case .reset = action {} else if listShows && (s.stack.count, s.top.screen, s.top.loading) != before {
        s.scrollUntil = now + scrollBarTime
    }
    // The bar for the playing track comes and goes, so keep the selection in the rows that show.
    if s.top.screen.isList { s.top.off = clamp(s.top.off, s.top.sel - s.shownRows + 1, s.top.sel) }
    return fx
}
