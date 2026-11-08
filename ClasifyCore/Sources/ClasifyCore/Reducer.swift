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
    /// A background re-read that `.refreshPlaylists` or `.refreshTracks` asked for. nil when it
    /// failed: the old rows stay.
    case playlistsRefreshed([Playlist]?)
    case tracksRefreshed(playlist: String, tracks: [Track]?)
    /// The tracks of the playlist selected on the Playlists screen were read for its covers,
    /// as `.readArtTracks` asked. nil when the read failed: the covers that show stay.
    /// A stale `token` (from before a logout or reset) is ignored.
    case artTracksRead(token: Int, playlist: String, tracks: [Track]?)
    /// The app came to the front. The list on screen and the playlist list are read again
    /// when they are older than `activationStaleAfter`, so a change made in Spotify shows.
    case activated
    /// The session came back after a drop, so changes can be missed. Every read counts as
    /// old, and the lists on screen are read again at once.
    case libraryStale
    /// The app started. It tries to log in again with the stored login.
    case launch
    /// Login finished for the attempt whose token is on the `.auth` frame. `ok` is false when it failed.
    case authDone(token: Int, ok: Bool)
    /// The restore that `.launch` started finished.
    case restored(token: Int, ok: Bool)
    case offline(Bool)
    /// The Mac's battery changed, as the app reads it from IOKit. nil when the Mac has no
    /// battery (an iMac or a Mac mini): the title bar shows no battery.
    case batteryChanged(Battery?)
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
    /// Read the playlist list or one playlist's tracks again, past the library's cache, while the
    /// screen shows the old rows. The result comes back as `.playlistsRefreshed` or `.tracksRefreshed`.
    case refreshPlaylists
    case refreshTracks(playlist: String)
    /// Read one playlist's tracks, through the library's memory cache, for the Playlists
    /// screen's covers. The result comes back as `.artTracksRead`.
    case readArtTracks(token: Int, playlist: String)
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

/// Rows of 22.5 points fill the list under the 22.5 point title bar, as in the mockup.
public let visibleRows = 9
/// Song lists show two lines a row (title and artist), so fewer rows fit. The count stays
/// the same when the bar shows: the rows get shorter instead.
public let trackRows = 5
/// The song rows that show at once in Cover Flow's song panel (card AF): 6, and part of a 7th.
public let panelRows = 6
/// Seconds after a seek in which `.position` ignores a position far from the seek target.
let seekSettle = 3.0
/// How far a position can be from the seek target, plus the time since the seek, and still be taken.
let seekSlack = 2.0

/// The most covers that take turns on the main menu.
public let mainArtCount = 8
/// Seconds after the main menu selection changes before its covers change.
public let artDelay = 0.3

/// Seconds without a wheel turn before a scrub, shuffle or repeat slider goes back to the progress bar.
public let sliderTimeout = 6.0
/// Seconds after a read when opening its screen reads it again in the background.
public let staleAfter = 120.0
/// Seconds after a read when the app coming to the front reads that list again.
public let activationStaleAfter = 30.0
/// The most tracks from outside the library that `AppState.extraTracks` keeps.
public let extraTrackLimit = 50
/// Seconds that a list's scroll bar shows after a wheel step or a screen change.
public let scrollBarTime = 1.5
/// A fast spin in Cover Flow: this many wheel steps within `fastSpinTime` seconds show the
/// big letter (card AG).
public let fastSpinSteps = 4
public let fastSpinTime = 0.6
/// Seconds after the last wheel step before Cover Flow hides the big letter.
public let letterTime = 1.0

func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { max(lo, min(hi, v)) }

@discardableResult
public func reduce(_ s: inout AppState, _ action: Action, _ env: Dependencies) -> [Effect] {
    let now = env.now()
    var fx: [Effect] = []
    func toast(_ msg: String) { s.toast = msg; s.toastUntil = now + 1.8 }
    func fetch(_ screen: Screen) {
        let key = AppState.readKey(screen)  // an album and Albums read Liked Songs
        fx.append(key.isEmpty ? .fetchPlaylists(token: s.tok) : .fetchTracks(token: s.tok, playlist: key))
    }
    /// Opens a list screen. Only a list that this session has not read yet loads.
    func open(_ screen: Screen) {
        if s.isLoaded(screen) {
            s.stack.append(Frame(screen: screen))
            return refreshIfStale(screen)
        }
        s.tok += 1
        s.stack.append(Frame(screen: screen, loading: true, token: s.tok))
        fetch(screen)
    }
    /// Ends the top frame's load. A pending shuffle starts when the load worked.
    func finishLoad(_ token: Int, ok: Bool) {
        s.top.loading = false
        s.top.error = s.offline || !ok
        if s.top.screen == .coverFlow && !s.top.error { placeCoverFlow() }
        if s.shuffleToken == token && !s.top.error {
            s.shuffleToken = nil
            shuffleLiked()
        }
    }
    func loadTrack(_ id: String, autoplay: Bool) {
        s.playGen += 1
        fx.append(.load(trackID: id, context: s.current?.playlist, autoplay: autoplay, generation: s.playGen))
    }
    func seek(_ t: Double) {  // callbacks from before the seek go stale
        s.playGen += 1
        (s.seekTarget, s.seekAt, s.seekGen, s.seekTrack) = (t, now, s.playGen, s.current?.track)
        fx.append(.seek(t, generation: s.playGen))
    }
    func skip(_ forward: Bool) { s.playGen += 1; fx.append(forward ? .next(generation: s.playGen) : .prev(generation: s.playGen)) }  // and from before the skip
    func play(_ pl: String, _ id: String) {
        if !s.loadPending { s.beforeLoad = s.current.map { BeforeLoad(current: $0, t: s.t, isPlaying: s.isPlaying) } }
        s.loadPending = true
        if s.current == nil { shiftMainSelection(by: 1) }
        s.current = TrackRef(playlist: pl, track: id)
        s.t = 0; s.isPlaying = true; s.nowMode = .volume
        s.stack.append(Frame(screen: .now))
        fx.append(.setShuffle(s.shuffle)); fx.append(.setRepeat(s.repeatMode))
        loadTrack(id, autoplay: true)
    }
    /// Reads a list again in the background when its read is older than `staleAfter`.
    /// Only a screen opening, `.activated` and `.libraryStale` call this, so a wheel turn never starts a read.
    func refreshIfStale(_ screen: Screen, after limit: Double = staleAfter) {
        let key = AppState.readKey(screen)
        guard !s.offline, now - (s.readAt[key] ?? 0) >= limit, !s.refreshing.contains(key) else { return }
        s.refreshing.insert(key)
        fx.append(key.isEmpty ? .refreshPlaylists : .refreshTracks(playlist: key))
    }
    /// Reads the song list on screen and the playlist list again, when they were read before.
    func refreshShown() {
        guard s.signedIn else { return }
        let songs = !AppState.readKey(s.top.screen).isEmpty  // a song list or Albums
        if songs, s.isLoaded(s.top.screen) { refreshIfStale(s.top.screen, after: activationStaleAfter) }
        if s.playlistsLoaded { refreshIfStale(.playlists, after: activationStaleAfter) }
    }
    /// After new rows came in, each frame on `screen` keeps its selected row by ID. A row that
    /// left keeps the index, clamped. The scroll offset moves with the selection.
    func keepSelection(on screen: Screen, old: [Row]) {
        for f in s.stack.indices where s.stack[f].screen == screen {
            let new = s.rows(for: s.stack[f])
            var frame = s.stack[f]
            let picked = old.indices.contains(frame.sel) ? new.firstIndex(of: old[frame.sel]) : nil
            let sel = picked ?? clamp(frame.sel, 0, max(new.count - 1, 0))
            frame.off = clamp(frame.off + sel - frame.sel, max(0, sel - s.shownRows + 1), sel)
            frame.sel = sel
            s.stack[f] = frame
        }
    }
    func keepExtra(_ track: Track) {
        s.extraTracks.removeAll { $0.id == track.id }
        s.extraTracks.append(track)
        if s.extraTracks.count > extraTrackLimit { s.extraTracks.removeFirst(s.extraTracks.count - extraTrackLimit) }
    }
    /// Puts the playlist list in, and keeps Liked Songs and the tracks already read for
    /// playlists that are still there.
    func setPlaylists(_ playlists: [Playlist]) {
        let read = Dictionary(s.library.map { ($0.id, $0.tracks) }, uniquingKeysWith: { a, _ in a })
        let kept = Set(playlists.map(\.id)).union([Playlist.likedSongsID])
        // The playing playlist is gone: keep the playing track's details for Now Playing.
        if let ref = s.current, !kept.contains(AppState.source(ref.playlist)), let track = s.track(ref) { keepExtra(track) }
        s.loadedTracks = s.loadedTracks.intersection(kept)
        s.library = s.library.filter { $0.id == Playlist.likedSongsID } + playlists.map {
            var p = $0
            if s.loadedTracks.contains(p.id) { p.tracks = read[p.id] ?? [] }
            return p
        }
        s.playlistsLoaded = true
        s.readAt[AppState.readKey(.playlists)] = now
    }
    /// A current track from outside our copy of the list, such as Spotify's autoplay: read its
    /// details once. A read in flight or a failed read is not started again.
    func readIfUnknown(_ id: String) {
        guard let ref = s.current, s.track(ref) == nil, id.hasPrefix("spotify:track:"), !s.trackReads.contains(id) else { return }
        s.trackReads.insert(id)
        fx.append(.readTrack(id))
    }
    /// The Now Playing row comes onto the main menu (`by` 1) or leaves it (-1). Each main menu
    /// frame keeps the row it had selected, so MENU comes back to the row the user picked.
    func shiftMainSelection(by d: Int) {
        for f in s.stack.indices where s.stack[f].screen == .main {
            s.stack[f].sel = max(0, s.stack[f].sel + d)
        }
    }
    func stop() {
        if s.current != nil { fx.append(.stop) }
        s.isPlaying = false; s.current = nil; s.t = 0; s.beforeLoad = nil; s.loadPending = false
    }
    func signOut(_ msg: String) {
        stop()
        s.stack = [Frame(screen: .login)]; s.signedIn = false  // the library belongs to that account
        s.library = []; s.playlistsLoaded = false; s.loadedTracks = []
        s.extraTracks = []; s.trackReads = []; s.readAt = [:]; s.refreshing = []; s.artReads = [:]
        s.coverFlowAlbum = nil; s.letterUntil = 0; s.coverFlowSteps = []
        toast(msg)
    }
    func shuffleLiked() {
        let liked = s.tracks(in: Playlist.likedSongsID)
        guard !liked.isEmpty else { return }
        s.shuffle = true  // before play, so the engine gets shuffle on with the load
        play(Playlist.likedSongsID, liked[env.random(liked.count)].id)
    }
    /// Cover Flow opens on the playing album, else on the album it showed last, else on the
    /// middle album (card AE).
    func placeCoverFlow() {
        let albums = s.albums
        let playing = s.current.flatMap { s.track($0)?.album?.id }
        let index = { (id: String?) in id.flatMap { id in albums.firstIndex { $0.id == id } } }
        s.top.sel = index(playing) ?? index(s.coverFlowAlbum) ?? albums.count / 2
        s.top.off = 0
        if albums.indices.contains(s.top.sel) { s.coverFlowAlbum = albums[s.top.sel].id }
    }
    /// Moves Cover Flow by `d` albums, or by `d` letters while the big letter shows. A wheel
    /// step counts toward a fast spin; the ⏮ ⏭ buttons always move one album.
    func moveCoverFlow(_ d: Int, wheel: Bool) {
        guard !s.top.loading, !s.top.error, d != 0 else { return }
        let albums = s.albums
        guard !albums.isEmpty else { return }
        var sel = clamp(s.top.sel, 0, albums.count - 1)
        for _ in 0..<abs(d) {
            if wheel && s.letterUntil > 0 {
                sel = AppState.letterJump(from: sel, by: d.signum(), in: albums)
            } else {
                sel = clamp(sel + d.signum(), 0, albums.count - 1)
            }
            if wheel {
                s.coverFlowSteps = Array((s.coverFlowSteps + [now]).suffix(fastSpinSteps))
                let fast = s.coverFlowSteps.count == fastSpinSteps && now - s.coverFlowSteps[0] <= fastSpinTime
                if fast || s.letterUntil > 0 { s.letterUntil = now + letterTime }
            }
        }
        s.top.sel = sel
        s.coverFlowAlbum = albums[sel].id
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
            if s.top.screen == .coverFlow { return moveCoverFlow(d, wheel: true) }
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
            if s.top.screen == .coverFlow {
                // The cover turns over into the song panel with the album's songs (card AF).
                let albums = s.albums
                guard !s.top.loading, albums.indices.contains(s.top.sel) else { return }
                s.letterUntil = 0; s.coverFlowSteps = []  // so MENU comes back with no letter
                return open(.albumPanel(album: albums[s.top.sel].id))
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
            case .coverFlow:
                open(.coverFlow)
                if !s.top.loading { placeCoverFlow() }
            case .playlists: open(.playlists)
            case .albums: open(.albums)
            case .album(let id): open(.tracks(playlist: id))
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
                if let list = s.top.screen.songList { play(list, id) }
            case .shuffle: toggleShuffle()
            case .repeatMode: setRepeat(s.repeatMode.next)
            case .skin: s.skin = s.skin.next  // not in the Settings rows until Dark and Aqua exist
            case .albumArt: s.albumArt = s.albumArt.next
            case .deviceColor: s.deviceColor = s.deviceColor.next
            case .clicker: s.clicker.toggle()
            case .about:
                s.aboutScene = s.aboutOpens % AppState.aboutScenes; s.aboutOpens += 1
                s.stack.append(Frame(screen: .about))
            case .logOut: s.stack.append(Frame(screen: .confirm))
            case .cancel: s.stack.removeLast()
            case .confirmLogOut: signOut("Logged out"); fx.append(.logOut)
            }

        case .menu:
            if s.top.screen == .now && s.nowMode != .volume { s.nowMode = .volume; s.overlayUntil = 0; return }
            // Not in the mockup: a closed browser tab would leave the login waiting forever.
            if s.top.screen == .auth { s.stack.removeLast(); fx.append(.cancelLogIn); return }
            if s.stack.count < 2 { return }
            if s.top.screen == .coverFlow { s.letterUntil = 0; s.coverFlowSteps = [] }
            s.stack.removeLast(); s.nowMode = .volume

        case .toggleShuffle: toggleShuffle()
        case .cycleRepeat: setRepeat(s.repeatMode.next)

        case .play:
            guard s.current != nil else { return toast("Nothing playing yet") }
            if !s.isPlaying && s.offline { return toast("Offline. Can’t resume") }
            s.isPlaying.toggle()
            fx.append(s.isPlaying ? .resume : .pause)

        case .next:
            // The skin's ⏭ button moves Cover Flow (card AE).
            if s.top.screen == .coverFlow { return moveCoverFlow(1, wheel: false) }
            guard s.current != nil else { return }
            if s.offline { return toast(offlineStart) }  // a skip offline would leave UI and player on different tracks
            skip(true)  // `current` follows when the engine reports `.trackChanged`

        case .prev:
            if s.top.screen == .coverFlow { return moveCoverFlow(-1, wheel: false) }
            guard s.current != nil else { return }
            if s.t > 3 { s.t = 0; seek(0) } else if s.offline { toast(offlineStart) } else { skip(false) }

        case .tick:
            if s.toastUntil > 0 && now > s.toastUntil { s.toast = ""; s.toastUntil = 0 }
            if s.artUntil > 0 && now > s.artUntil {  // the covers follow the row
                s.artUntil = 0
                if let row = s.halfRow { s.artRow = row }
            }
            // The volume bar hides, and a slider goes back to the progress bar.
            if s.overlayUntil > 0 && now > s.overlayUntil { s.overlayUntil = 0; s.nowMode = .volume }
            if s.scrollUntil > 0 && now > s.scrollUntil { s.scrollUntil = 0 }
            if s.letterUntil > 0 && now > s.letterUntil { s.letterUntil = 0 }

        case .position(let t, let gen):
            // Soon after a seek, a position far from the target is from an earlier seek.
            // With Repeat One, a seek near the end can wrap to the start of the same track.
            let since = now - s.seekAt
            let end = s.current.flatMap { s.track($0)?.duration } ?? .infinity
            let wrapped = s.repeatMode == .one && s.seekTarget >= end - seekSettle && t <= seekSlack + since
            if gen == s.seekGen && s.current?.track == s.seekTrack && since < seekSettle && !wrapped
                && abs(t - s.seekTarget) > seekSlack + since { return }
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
            keepExtra(track)

        case .adopted(let id, let pl, let playing, let t, let gen):
            guard s.current == nil, gen == s.playGen else { return }  // a load or a newer one came first
            s.current = TrackRef(playlist: pl ?? "", track: id)  // "" is no playlist of ours
            s.isPlaying = playing; s.t = t
            shiftMainSelection(by: 1)  // the new Now Playing row goes on top: keep the pick
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
                shiftMainSelection(by: -1)
                // No empty Now Playing: back to the list the load came from, with the toast there.
                if s.top.screen == .now && s.stack.count > 1 { s.stack.removeLast(); s.nowMode = .volume; s.overlayUntil = 0 }
            }
            s.beforeLoad = nil; s.loadPending = false
            toast(msg)

        case .playlistsLoaded(let token, let playlists):
            guard s.top.loading, s.top.token == token else { return }  // stale load
            if let playlists { setPlaylists(playlists) }
            finishLoad(token, ok: playlists != nil)

        case .playlistsRefreshed(let playlists):
            // Not asked for in this session, for example from before a sign-out.
            guard s.refreshing.remove(AppState.readKey(.playlists)) != nil, let playlists else { return }
            let old = s.rows(for: Frame(screen: .playlists))
            setPlaylists(playlists)
            keepSelection(on: .playlists, old: old)

        case .activated: refreshShown()

        case .libraryStale:
            s.readAt = [:]
            refreshShown()

        case .tracksRefreshed(let id, let tracks):
            guard s.refreshing.remove(id) != nil, let tracks,
                let i = s.library.firstIndex(where: { $0.id == id })  // the playlist is gone
            else { return }
            // The screens that show this list: the song list, and for Liked Songs, Albums and its albums.
            var screens = [Screen.tracks(playlist: id)]
            for f in s.stack where AppState.readKey(f.screen) == id && !screens.contains(f.screen) { screens.append(f.screen) }
            let old = screens.map { s.rows(for: Frame(screen: $0)) }
            // The playing track left the list (or its album): keep its details for Now Playing.
            let playing = s.current.flatMap { AppState.source($0.playlist) == id ? s.track($0) : nil }
            s.library[i].tracks = tracks; s.library[i].trackCount = tracks.count
            if let ref = s.current, let playing, s.track(ref) == nil { keepExtra(playing) }
            s.readAt[id] = now
            for (screen, rows) in zip(screens, old) { keepSelection(on: screen, old: rows) }
            // Cover Flow opens again on the album it shows now, also when its album left.
            if let flow = s.stack.last(where: { $0.screen == .coverFlow }) {
                let albums = s.albums
                if albums.indices.contains(flow.sel) { s.coverFlowAlbum = albums[flow.sel].id }
            }

        case .artTracksRead(let token, let id, let tracks):
            guard s.artReads[id] == token else { return }  // a read from before a logout or reset
            s.artReads[id] = nil
            guard let tracks, !s.loadedTracks.contains(id) else { return }
            // Kept like an open's read, so opening the playlist later needs no read.
            if let i = s.library.firstIndex(where: { $0.id == id }) {
                s.library[i].tracks = tracks; s.library[i].trackCount = tracks.count
            } else if id == Playlist.likedSongsID {  // first, as an open's read puts it; not a Playlists row
                s.library.insert(Playlist(id: id, name: "Liked Songs", tracks: tracks), at: 0)
            } else {
                return  // the playlist is gone
            }
            s.loadedTracks.insert(id)
            s.readAt[id] = now

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
                s.readAt[id] = now
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

        case .batteryChanged(let battery):
            s.battery = battery

        case .expire:
            // Forget the stored login too, so that a later .launch does not restore it.
            if s.signedIn { signOut("Session expired. Log in again"); fx.append(.logOut) }

        case .reset:
            stop()
            let (tok, gen, auth, art) = (s.tok, s.playGen, s.authAttempt, s.artTok)  // keep counters so callbacks from before the reset stay stale
            let nav = (s.navSeq, s.wholeSeq)  // keep the screen's identity, so the skin does not slide the reset screen in
            let settings = s.settings  // saved settings stay
            let battery = s.battery  // the Mac's battery, which a reset does not change
            let aboutOpens = s.aboutOpens  // About counts from launch, not from a reset
            s = AppState()
            s.aboutOpens = aboutOpens
            s.tok = tok; s.playGen = gen; s.authAttempt = auth; s.artTok = art; (s.navSeq, s.wholeSeq) = nav; s.settings = settings
            s.battery = battery
        }
    }
    let before = (s.stack.count, s.top.screen, s.top.loading)
    let wasOverPanel = s.nowOverPanel
    let wasAuth = s.top.screen == .auth
    let rowBefore = s.halfRow
    let wasOffline = s.offline
    let artBefore = (s.artRow, s.library, s.current, s.loadedTracks, s.extraTracks)  // copies share storage, so this is cheap
    apply()
    // A new screen slides in: from the right when it opens, from the left on a way back.
    // The main menu after the login wait counts as opening. A reset does not slide.
    if case .reset = action {} else if (s.stack.count, s.top.screen) != (before.0, before.1) {
        s.navSeq += 1
        s.navForward = s.stack.count >= before.0 || (wasAuth && s.top.screen == .main)
        // Between a half screen and a full one, the whole screen moves; otherwise only the content.
        let whole = s.isHalf(before.1) != s.isHalf(s.top.screen)
        if whole { s.wholeSeq += 1 }
        // The cover flies only to and from a Now Playing that shows the panel's album.
        let fly = before.1 == .now ? wasOverPanel : s.nowOverPanel
        s.navMove = AppState.move(between: before.1, and: s.top.screen, whole: whole, fly: fly)
    }
    // A list shows its scroll bar for a moment when it appears: on a new screen, or when its
    // load ends. A reset starts with no bar.
    let listShows = s.top.screen.isList && !s.top.loading && !s.top.error
    if case .reset = action {} else if listShows && (s.stack.count, s.top.screen, s.top.loading) != before {
        s.scrollUntil = now + scrollBarTime
    }
    // The covers of a half screen: on the main menu, new random ones when the menu opens.
    // On both, the selected row's covers a moment after the selection changes. On Playlists,
    // the covers that show stay until the selected playlist's tracks are read.
    // Picking them reads the whole library, so it runs only when something they use changed.
    if case .reset = action {} else if s.isHalf(s.top.screen) {
        let opened = before.1 != s.top.screen || before.0 != s.stack.count
        if opened && s.top.screen == .main {
            s.artSeed = env.random(1 << 30); s.artRow = s.mainRow; s.artUntil = 0
        } else if s.halfRow != rowBefore || opened {
            s.artUntil = now + artDelay
        }
        if opened || (s.artRow, s.current, s.loadedTracks) != (artBefore.0, artBefore.2, artBefore.3) || s.library != artBefore.1 || s.extraTracks != artBefore.4 {
            s.refreshArt()
        }
        // The list that the covers come from: the selected playlist, or Liked Songs for the main
        // menu's rows (see `refreshArt`), which nothing else reads at first open.
        let artList: String? = switch s.artRow {
        case .playlist(let id)?: id
        case .nowPlaying?, nil: nil
        default: s.top.screen == .main ? Playlist.likedSongsID : nil  // Playlists picks a playlist soon
        }
        // Read when the covers move to a list or the app comes back online, not on each
        // tick, so a failed read is tried again only when the row is selected again.
        if let id = artList, opened || s.artRow != artBefore.0 || (wasOffline && !s.offline),
            !s.loadedTracks.contains(id), !s.offline, s.artReads[id] == nil {
            s.artTok += 1; s.artReads[id] = s.artTok
            fx.append(.readArtTracks(token: s.artTok, playlist: id))
        }
    }
    // The bar for the playing track comes and goes, so keep the selection in the rows that show.
    if s.top.screen.isList { s.top.off = clamp(s.top.off, s.top.sel - s.shownRows + 1, s.top.sel) }
    return fx
}
