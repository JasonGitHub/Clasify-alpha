import Foundation

public enum Action: Equatable, Sendable {
    case wheel(Int)  // detents, + is clockwise. Quick steps on a list move more rows: see `WheelSpeed`.
    case select, menu, play, next, prev
    /// The shuffle and repeat icons on Now Playing, and the S and R keys.
    case toggleShuffle, cycleRepeat
    /// CLA-183, card CS: a key typed on Search (a letter, a number or a space), and Delete
    /// there. On other screens they do nothing.
    case searchType(Character), searchDelete
    case tick  // drives toast and overlay timers
    /// The playlist list was read: names and track counts, no tracks. nil when the read failed.
    case playlistsLoaded(token: Int, playlists: [Playlist]?)
    /// The tracks of one playlist (or Liked Songs) were read. nil when the read failed.
    case tracksLoaded(token: Int, playlist: String, tracks: [Track]?)
    /// The library's artists were read (card BN). nil when the read failed.
    case artistsLoaded(token: Int, artists: [Playlist]?)
    /// A background re-read that `.refreshPlaylists` or `.refreshTracks` asked for. nil when it
    /// failed: the old rows stay.
    case playlistsRefreshed([Playlist]?)
    case tracksRefreshed(playlist: String, tracks: [Track]?)
    /// CLA-179: the artists, read again for On This Mac's main menu. nil when it failed: the
    /// old rows stay.
    case artistsRefreshed([Playlist]?)
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
    /// The app started. It tries to log in again with the stored login. Before the first
    /// launch setup ends, it shows Hello (card AT) first.
    case launch
    /// The app looked for the Spotify app on this Mac: at launch, on a service switch, and every
    /// 3 s while the `spotifyApp` screen (card BB) shows. When it is found there, setup goes on.
    /// The screen opens only on Spotify; Pick Your Music orders its rows from it on both.
    case spotifyAppFound(Bool)
    /// A track read is this far: `done` of `total` items have their details, on `albums`
    /// albums. The first library read (card AY, changes 141 and 188) counts up with it.
    case readProgress(String, done: Int, total: Int, albums: Int)
    /// Login finished for the attempt whose token is on the `.auth` frame. `ok` is false when it failed.
    case authDone(token: Int, ok: Bool)
    /// The restore that `.launch` or "Check again" started finished.
    case restored(token: Int, ok: Bool)
    /// The login worked, but the account is not Spotify Premium, so it ended (CLA-66). From a
    /// browser login, a restore, "Check again", or a session that found it out later. The
    /// Premium screen shows (card AX, screen 135). The stored login stays for "Check again".
    /// `token` is the attempt of the login or restore, as in `.authDone` and `.restored`, so
    /// a late result of an older attempt is dropped. nil: a session that is in found it out.
    case notPremium(token: Int?)
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
    /// CLA-168: the engine reports its own volume, in percent: on Apple Music, the Mac's output
    /// volume, also when the volume keys change it. Applied only on Apple Music.
    case volumeReported(Int)
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
    /// The active service's library names its lists with these words (after `.setService`).
    case libraryWords(LibraryWords)
    /// The login or restore with this token found no access to the library: the user did
    /// not allow it in the macOS prompt (Apple Music, card BM, change 258).
    case accessDenied(token: Int)
    /// The app read its own signature at launch (card BI v2): a beta, or nil for an ad-hoc build.
    case betaBuild(BetaBuild?)
    /// The launch check of card BV (CLA-125) read the newest beta's build number.
    case latestBeta(Int)
    /// CLA-128: the activation server answered request number `request`. nil: the app's stored
    /// activation, sent before `.launch`. `failure`: why `.offline` came (CLA-180), for analytics only.
    case activation(Activation, request: Int?, failure: ConnectionFailure? = nil)
    /// CLA-143: the login with this token carries the activate page: after it, the tab goes on
    /// to the email page, so Activate opens on 320 and skips 319.
    case loginCarriesActivate(token: Int)
    /// CLA-128: the app came back to the front. On the Activate screen (320, 321 and 322) it
    /// asks the server again (CLA-146), unless a check is on its way.
    case checkActivation
    /// The skin's first-launch arrival ended, or did not run (card BR, change 288). Hello starts
    /// from now. A second one does nothing.
    case arrived
    /// Card AN.1 (CLA-43, 344): a click or right-click on the menu bar icon. `shown`: the device
    /// window shows now. The answer is `.showWindow` or `.hideWindow`.
    case menuBarClick(shown: Bool)
    /// ⌘W, File › Close, on the device window (Jason OK 15:49 JST 11-22). It hides myPod as a
    /// click on the menu bar icon over a shown myPod does: the answer is `.hideWindow`, and the
    /// music goes on. During the first setup it does nothing: setup always shows in the window.
    case closeWindow
    /// CLA-130 (card BT row 4): Cmd + a two-finger swipe turned the 3D device off its front
    /// (true), or it is back on its front (false). While it is turned, the wheel, the buttons
    /// and the keys do nothing. The angle itself stays in the skin (`K3DTurn`).
    case deviceTurned(Bool)
    /// CLA-97: the player lost control of playback, or got it back. Only for the
    /// `control_lost` and `control_back` events: `.playbackFailed` and the track reports still
    /// drive the screens.
    case controlLost(ControlLoss), controlBack
    /// CLA-97: a skin feature that the reducer does not see (the About flip, the take-apart),
    /// for `day_active`.
    case used(Feature)
    /// CLA-97: ms from the process start to the first window, for `app_speed`. The app sends it once.
    case appStarted(ms: Int)
    /// CLA-97: the app quits normally. The exact day count is saved (`AppState.savedToday`).
    case willQuit
    /// CLA-97: a 3D view opened or closed, for the view times of `day_active`. The skin sends it.
    case view3D(View3D, open: Bool)
    /// CLA-162: where the device window is now, or nil when the person cannot see it. The app
    /// sends it about once a minute and at each change.
    case window(WindowSpot?)
    /// CLA-97: the sender takes events: a PostHog key is in the build and `analytics.on` is on.
    /// The app sends it at start and when the switch changes.
    case analyticsOn(Bool)
    /// CLA-163: the hints trial switch (`hints.trial`). The app sends it at start.
    case hintsTrial(Bool)
    /// CLA-97 (A4): MetricKit reported crashes or hangs of earlier runs. Only the first
    /// `AppProblem.maxPerLaunch` of a run become events. With `analytics.on` off, the sender drops them.
    case appProblems([AppProblem])
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
    /// Read the library's artists; the result comes back as `.artistsLoaded` with this token.
    case fetchArtists(token: Int)
    /// Read the playlist list or one playlist's tracks again, past the library's cache, while the
    /// screen shows the old rows. The result comes back as `.playlistsRefreshed` or `.tracksRefreshed`.
    case refreshPlaylists
    case refreshTracks(playlist: String)
    /// CLA-179: read the artists again past the cache (On This Mac only). The result comes back
    /// as `.artistsRefreshed`.
    case refreshArtists
    /// Read one playlist's tracks, through the library's memory cache, for the Playlists
    /// screen's covers. The result comes back as `.artTracksRead`.
    case readArtTracks(token: Int, playlist: String)
    /// Read Liked Songs and the playlist list in the background after a login, so that the
    /// first open is fast. Nothing comes back: the library keeps the result for the next fetch.
    case prefetch
    /// Log in through the browser; the result comes back as `.authDone` with this token.
    case logIn(token: Int)
    /// CLA-143, card BY: the same browser login, on a Mac that still has to activate (Spotify
    /// only). The app first asks for the activate page (at most 2 s) and hands it to the login
    /// page, so the same tab goes on to it. With no page in time, it is `.logIn`.
    case logInActivating(token: Int)
    case cancelLogIn
    /// Open the Spotify app's download page in the browser (card BB).
    case getSpotifyApp
    /// Open Spotify's Premium page in the browser (card AX, screen 135).
    case getPremium
    /// Log in with the stored login; the result comes back as `.restored` with this token.
    case restoreSession(token: Int)
    /// Forget the stored login.
    case logOut
    /// Read one track's details, for a track that Spotify plays from outside the library.
    /// The result comes back as `.trackRead`.
    case readTrack(String)
    /// Make this music service the active one in the player and the library (CLA-103). The
    /// store runs it before the effects after it, and answers with `.libraryWords`.
    case setService(MusicService)
    /// Open the Mac's privacy settings for Apple Music (card BM, change 258).
    case openPrivacy
    /// Open the beta download page in the browser (card BI v2).
    case getNewBeta
    /// Quit the app, from the ended beta (card BI v2, change 234).
    case quit
    /// Card BV (CLA-125): read the newest beta's build number, once. A newer number comes back
    /// as `.latestBeta`; offline, no answer in 5 s or a bad file send nothing (change 314).
    case checkLatestBeta
    /// CLA-128, card BW: open getmypod.app/activate/?d=ID in the browser, where the person types the email.
    case openActivatePage(request: Int)
    /// CLA-128: ask where the activation stands; send the mail again. The answer comes back
    /// as `.activation` with this request number.
    case checkActivation(request: Int), sendActivationAgain(request: Int)
    /// Card AN.1 (CLA-43, 344-345): fade the device window in where it was last, or out. The
    /// music goes on.
    case showWindow, hideWindow
    /// CLA-97: send this beta analytics event. The app's sender decides if it goes out.
    case track(BetaEvent)
}

/// Side inputs the reducer reads, injected so tests are deterministic.
public struct Dependencies: Sendable {
    public var now: @Sendable () -> Double
    public var random: @Sendable (Int) -> Int  // uniform in 0..<n
    /// CLA-97: the Mac's time zone, for the day and time bands of `day_active`.
    public var timeZone = TimeZone.current

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
/// CLA-179 (Jason 18:19 JST, 11-24): On This Mac reads the Music app library again when the
/// main menu opens and the last read is older than this, so songs added or removed there show.
public let localStaleAfter = 60.0
/// Seconds after a read when the app coming to the front reads that list again.
public let activationStaleAfter = 30.0
/// Card BW, CLA-146: the Activate screen asks the server for 3 minutes (see `activateCheckDelay`),
/// then shows "Check again" (322); "Welcome to the beta" shows for 1.5 s before Your Music.
public let activateChecksFor = 180.0, activateBeat = 1.5
/// CLA-146: a check with no answer after this many seconds no longer blocks the next one. The
/// request itself gives up after 10 s (`ServerActivator`).
public let activateStuckAfter = 12.0
/// CLA-146 (Jason, 18:58 JST 11-19): seconds from one timer check to the next, by the seconds
/// since the checks started: 3 s in minute 1, 10 s in minute 2, 15 s in minute 3, then nil
/// (stop). That is at most 30 checks, as many as the old 30 s for 15 minutes.
public func activateCheckDelay(elapsed: Double) -> Double? {
    if elapsed < 60 { return 3 }
    if elapsed < 120 { return 10 }
    if elapsed < activateChecksFor { return 15 }
    return nil
}
/// The most tracks from outside the library that `AppState.extraTracks` keeps.
public let extraTrackLimit = 50
/// Seconds that a list's scroll bar shows after a wheel step or a screen change.
public let scrollBarTime = 1.5
/// A fast spin in Cover Flow: this many wheel steps within `fastSpinTime` seconds show the
/// big letter (card AG). Change 95: 6 steps within 0.4 s, so a normal quick turn does not
/// start it (it was 4 within 0.6 s).
public let fastSpinSteps = 6
public let fastSpinTime = 0.4
/// Seconds after the last wheel step before Cover Flow hides the big letter.
public let letterTime = 1.0

/// CLA-170: how long Now Playing keeps the earlier song's words for a read with no answer.
let readWait = 3.0

func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { max(lo, min(hi, v)) }

/// Card AN.1 (CLA-43, 348): screens that show myPod when it is hidden by the menu bar icon.
let showsWindow: [Screen] = [.betaSoon, .betaEnded, .betaNew, .activate]

@discardableResult
public func reduce(_ s: inout AppState, _ action: Action, _ env: Dependencies) -> [Effect] {
    let top = s.top.screen, handOver = s.activateHandOver
    // CLA-97: the first launch, for the setup times. A Mac set up before it has none.
    if action == .launch && !s.setupDone && s.firstLaunchAt == nil { s.firstLaunchAt = env.now() }
    // CLA-97, `app_speed`: not on a launch in setup, as that time holds the person's own login steps.
    if action == .launch && s.setupDone && s.launchedAt == nil { s.launchedAt = env.now() }
    let before = BeforeEvents(s, action)
    var fx = reduceAction(&s, action, env)
    fx += searchReads(&s)
    fx += betaEvents(&s, before, fx, now: env.now())
    fx += dayEvents(&s, action, before, now: env.now(), in: env.timeZone)
    // 348: a beta notice or Activate that opens shows a hidden myPod. CLA-153: not Activate
    // that opens through the login hand-over (320), because the browser shows the activate
    // page. A locked Mac at launch still shows it, also on 321.
    if s.top.screen != top && showsWindow.contains(s.top.screen) && !fx.contains(.showWindow)
        && !(s.top.screen == .activate && handOver) { fx.append(.showWindow) }
    return fx
}

private func reduceAction(_ s: inout AppState, _ action: Action, _ env: Dependencies) -> [Effect] {
    let now = env.now()
    var fx: [Effect] = []
    /// A status toast. While a hint shows, it waits until the hint ends (card BA).
    func toast(_ msg: String) {
        if s.hint != nil { s.heldToast = msg; return }
        s.toast = msg; s.toastUntil = now + 1.8
    }
    /// The hint stops. `done`: it ended for good. A toast that waited shows now.
    func endHint(done: Bool) {
        if done, let hint = s.hint { s.hintsDone.insert(hint) }
        s.hint = nil; s.hintAt = 0; s.hintTip = false
        if !s.heldToast.isEmpty { toast(s.heldToast); s.heldToast = "" }
    }
    func fetch(_ screen: Screen) {
        // CLA-120: on the main menu at a launch, before the stored login is back, a list waits
        // in its loading state. Its read starts when the login is back (`.restored`).
        if !s.signedIn && s.restoring { return }
        let key = s.readKey(screen)  // Albums and Cover Flow read `albumsList`, an album itself
        if screen == .yourMusic { s.readDone = 0; s.readTotal = 0; s.readAlbums = 0; s.namesHold = 0; s.firstReadSongs = nil; s.firstReadSongsAt = 0 }  // each first read, or retry, counts from 0
        if screen == .artists { return fx.append(.fetchArtists(token: s.tok)) }
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
            shuffle(s.shuffleList)
        }
        if s.startToken == token && !s.top.error {  // CLA-173: a list start waited for this read
            s.startToken = nil
            // Now Playing takes the loading frame's place, so MENU goes back to the row. An
            // empty list stays on screen: there is nothing to play. So does a list with only
            // missing songs (card CR): its gray rows show.
            if s.tracks(in: s.startList).contains(where: { !$0.missing }) { s.stack.removeLast(); startList(s.startList) }
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
        let key = s.readKey(screen)
        // The artists are read once a session (card BN).
        guard screen != .artists, !s.offline, now - (s.readAt[key] ?? 0) >= limit, !s.refreshing.contains(key) else { return }
        s.refreshing.insert(key)
        fx.append(key.isEmpty ? .refreshPlaylists : .refreshTracks(playlist: key))
    }
    /// Reads the song list on screen and the playlist list again, when they were read before.
    func refreshShown() {
        guard s.signedIn else { return }
        let songs = !s.readKey(s.top.screen).isEmpty  // a song list or Albums
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
    /// Puts the playlist list in, and keeps the lists that are not playlists (Liked Songs, the
    /// library, Songs, artists, albums) and the tracks already read for playlists still there.
    func setPlaylists(_ playlists: [Playlist]) {
        let read = Dictionary(s.library.map { ($0.id, $0.tracks) }, uniquingKeysWith: { a, _ in a })
        let hidden = s.library.filter { Playlist.isHidden($0.id) && !Album.isID($0.id) }
        let albums = s.library.filter { Album.isID($0.id) }
        let kept = Set(playlists.map(\.id) + hidden.map(\.id) + albums.map(\.id)).union([Playlist.likedSongsID, Playlist.libraryID])
        // The playing playlist is gone: keep the playing track's details for Now Playing.
        if let ref = s.current, !Album.isID(ref.playlist), !kept.contains(ref.playlist), let track = s.track(ref) { keepExtra(track) }
        s.loadedTracks = s.loadedTracks.intersection(kept)
        s.library = hidden + playlists.map {
            var p = $0
            if s.loadedTracks.contains(p.id) { p.tracks = read[p.id] ?? [] }
            return p
        } + albums
        s.playlistsLoaded = true
        s.readAt[AppState.readKey(.playlists)] = now
    }
    /// A current track from outside our copy of the list, such as Spotify's autoplay: read its
    /// details once. A read in flight or a failed read is not started again.
    func readIfUnknown(_ id: String) {
        guard let ref = s.current, s.track(ref) == nil, id.hasPrefix("spotify:track:"), !s.trackReads.contains(id) else { return }
        s.trackReads.insert(id); s.readsPending[id] = now
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
    /// The first library read ended setup. Card AY, change 140: "You’re all set" for a beat,
    /// then the main menu.
    func endFirstRead() {
        s.setupDone = true
        s.beatUntil = now + AppState.allSetTime(songs: s.firstReadSongs)
    }
    /// Liked Songs is read and "Getting your music" waited for the playlist names (change 191,
    /// CLA-74): the read worked, also if offline since.
    func endHeldRead() {
        s.namesHold = 0
        guard s.top.screen == .yourMusic && s.top.loading else { return }
        s.top.loading = false; s.top.error = false
        endFirstRead()
    }
    /// Change 191: holds "Getting your music" until the last playlist name has shown. False
    /// when every name has shown already, or there are none.
    func holdForNames() -> Bool {
        let n = s.firstReadNames.count
        let shown = s.namesAt + AppState.namesEnd(names: n, songs: s.firstReadSongs, late: s.namesLate)
        guard n > 0 && now < shown else { return false }
        s.namesHold = shown
        return true
    }
    /// Card BW: one request to the activation server; its answer comes back as `.activation`.
    /// CLA-146: one check at a time. A check while one is on its way sends nothing; a press
    /// then takes that answer as its own, so no connection still shows 327.
    func askActivation(_ effect: (Int) -> Effect, pressed: Bool, check: Bool = true) {
        if check && s.activateAsking(at: now) {
            if pressed { s.activatePressed = s.activateAsked }
            return  // a due timer check stays due until the answer comes
        }
        nextActivateCheck()
        s.activateRequest += 1
        if pressed { s.activatePressed = s.activateRequest }
        s.activateAsked = s.activateRequest; s.activateAskedAt = now
        fx.append(effect(s.activateRequest))
    }
    /// CLA-146: the next timer check, by `activateCheckDelay`; none after the 3 minutes.
    func nextActivateCheck() {
        guard s.activateStopAt > 0 else { return }
        let elapsed = now - (s.activateStopAt - activateChecksFor)
        s.activateCheckAt = activateCheckDelay(elapsed: elapsed).map { now + $0 } ?? s.activateStopAt
    }
    func startActivateChecks() { s.activateStopAt = now + activateChecksFor; nextActivateCheck() }
    /// Card BW: the page opens (320). The checks run for 3 minutes from now (CLA-146).
    func openActivatePage() {
        pageIsOpen()
        s.activatePressed = s.activateRequest  // a page that cannot open shows 327
        fx.append(.openActivatePage(request: s.activateRequest))
    }
    /// 320: the browser shows the activate page, from "Open browser" or from the login (CLA-143).
    func pageIsOpen() {
        s.activateRequest += 1; s.activateAsked = 0  // an answer to the flow before is dropped
        s.activateFlow += 1
        showActivateStep {
            if case .waiting(_, let mail) = s.activation { s.activateOpenMail = mail } else { s.activateOpenMail = 0 }
            startActivateChecks()
        }
    }
    /// The browser login with the current `authAttempt`. CLA-143: on a Mac that still has to
    /// activate, a Spotify login carries the activate page.
    func logIn() {
        s.activateHandOver = false
        fx.append(s.activateGated && s.service == .spotify ? .logInActivating(token: s.authAttempt) : .logIn(token: s.authAttempt))
    }
    /// Card BW, 320 and 321: "Cancel" and MENU go back to 319 and stop the checks.
    func cancelActivate() {
        showActivateStep { s.activateOpenMail = nil; s.activation = .locked; s.activateStopAt = 0 }
        s.activateRequest += 1; s.activateAsked = 0  // an answer still on its way is dropped
        s.activateFlow += 1  // and a page URL still on its way
    }
    /// Card BW: the 1.5 s beat on 323, the timer checks, and their end after 3 minutes (322).
    func activateTick() {
        if s.activatedAt > 0 {
            if now >= s.activatedAt + activateBeat { s.activatedAt = 0; setupNext() }
        } else if s.activateStopAt > 0 && now >= s.activateStopAt {
            showActivateStep { s.activateStopAt = 0 }
        } else if s.activateStopAt > 0 && now >= s.activateCheckAt {
            askActivation(Effect.checkActivation, pressed: false)
        }
    }
    /// Card BW: a new Activate screen starts on its first row.
    func showActivateStep(_ change: () -> Void) {
        let before = s.activateStep
        change()
        if s.top.screen == .activate && s.activateStep != before { s.stack[s.stack.count - 1].sel = 0; s.stack[s.stack.count - 1].off = 0 }
    }
    /// The next setup step after the login: the Spotify app screen if Spotify needs the app and
    /// it is missing, else the first library read, else the main menu. Apple Music does not need it.
    func setupNext() {
        if s.spotifyApp == false && s.service == .spotify { s.stack = [Frame(screen: .spotifyApp)]; return }
        // CLA-128: Activate comes before Your Music (CLA-156: always). CLA-140: also after
        // setup (a login after a lock), and by the remembered flag, so a "no connection" answer
        // does not hold an activated Mac.
        if s.activateGated {
            s.stack = [Frame(screen: .activate)]
            // CLA-143, card BY: the login page took the tab on to the email page, so 320, not 319.
            if s.activateHandOver { s.activateHandOver = false; pageIsOpen() }
            return
        }
        guard !s.setupDone else {
            s.stack = [Frame(screen: .main)]
            // CLA-140: a launch that showed Activate first restores the stored login only now.
            if !s.signedIn && !s.restoring { restore() }
            return
        }
        s.tok += 1
        s.stack = [Frame(screen: .yourMusic, loading: true, token: s.tok)]
        fetch(.yourMusic)
        // Card AY, change 141: the small screen fills with the playlist names meanwhile.
        if s.playlistsLoaded {
            s.namesAt = now
        } else if s.refreshing.insert(AppState.readKey(.playlists)).inserted {
            s.namesAt = 0
            fx.append(.refreshPlaylists)
        }
    }
    func restore() {
        s.authAttempt += 1; s.restoring = true
        fx.append(.restoreSession(token: s.authAttempt))
    }
    /// CLA-140: the launch check found that a remembered Mac is no longer active (turned off,
    /// moved out by a newer Mac, or a new mail flow). Playback stops and only Activate shows.
    func lockToActivate(_ answer: Activation) {
        stop()
        // A restore still on its way is stale: its result must not replace Activate (Codex on
        // #325). After 323, setupNext() starts a new one.
        if s.restoring { s.restoring = false; s.authAttempt += 1 }
        if s.hint != nil { endHint(done: false) }
        s.beatUntil = 0; s.toast = ""; s.toastUntil = 0
        s.stack = [Frame(screen: .activate)]
        if case .waiting = answer { startActivateChecks() }  // 321, with its checks
    }
    /// "Linked" on the Spotify App screen ended (card BB, change 174): back to where it was
    /// opened over, or on with setup.
    func leaveSpotifyApp() {
        s.beatUntil = 0
        guard s.stack.count > 1 else { return setupNext() }
        s.stack.removeLast()
        // A load that failed under this screen left an empty Now Playing: back to its list.
        if s.top.screen == .now && s.current == nil && s.stack.count > 1 {
            s.stack.removeLast(); s.nowMode = .volume; s.overlayUntil = 0
        }
        // A read that ended under this screen was dropped, because its frame was not on top.
        if s.top.loading {
            s.tok += 1
            if s.shuffleToken == s.top.token { s.shuffleToken = s.tok }
            if s.startToken == s.top.token { s.startToken = s.tok }
            s.top.token = s.tok
            fetch(s.top.screen)
        }
    }
    /// "Log out" or MENU on the Premium screen: forget the stored login and go to the login
    /// screen with its normal words, with no toast (card AX, screen 135, as change 181).
    func leavePremium() {
        s.restoring = false
        s.authAttempt += 1  // a "Check again" that still runs is stale
        logOut()
        s.premiumFound = false; s.premiumAt = 0
    }
    /// Signs out and forgets the login. Apple Music goes back to Pick Your Music, because
    /// Clasify cannot sign out the Mac's Apple account (card BM, change 263); On This Mac too.
    func logOut() {
        // CLA-120: Log out can come while the stored login is checked at launch: its late
        // result is stale then.
        if s.restoring { s.restoring = false; s.authAttempt += 1 }
        signOut(); fx.append(.logOut)
        if s.service != .spotify { s.stack = [pickMusic()] }
    }
    /// Pick Your Music, on the active service's row (card BM, change 257). When the Spotify app
    /// was not found (or not checked yet), Apple Music is the top row and is selected (CLA-103).
    func pickMusic() -> Frame {
        s.appleMusicFirst = s.spotifyApp != true
        var frame = Frame(screen: .pickMusic)
        let row = Row.pickService(s.appleMusicFirst ? .appleMusic : s.service)
        frame.sel = s.rows(for: frame).firstIndex(of: row) ?? 0
        return frame
    }
    /// Goes straight to the login screen, with no toast (card AX, change 181).
    func signOut() {
        stop()
        s.stack = [Frame(screen: .login)]; s.signedIn = false; s.sessionEnded = false  // the library belongs to that account
        s.library = []; s.playlistsLoaded = false; s.loadedTracks = []; s.artists = []; s.artistsLoaded = false
        s.extraTracks = []; s.trackReads = []; s.readsPending = [:]; s.heldWords = nil; s.readAt = [:]; s.refreshing = []; s.artReads = [:]
        s.coverFlowAlbum = nil; s.letterUntil = 0; s.coverFlowSteps = []
        s.toast = ""; s.toastUntil = 0  // an older toast must not cover the login words
        s.hint = nil; s.hintAt = 0; s.hintTip = false; s.heldToast = ""  // nor a toast that waited for a hint
        s.tourRestAt = now  // the tour queue stays for the next login (card BA.2)
        s.pendingService = nil
        s.startToken = nil; s.startOnCovers = false  // a late read must not fill the next account's library
    }
    /// Makes `service` the active one. CLA-168: `volume` is the active service's volume; on
    /// Apple Music it is the Mac's output volume. Spotify's waits in `spotifyVolume` and comes
    /// back on the switch back. The Spotify player kept it too: only the active one gets volume.
    func use(_ service: MusicService) {
        if s.service == .spotify && service != .spotify { s.spotifyVolume = s.volume }
        if s.service != .spotify && service == .spotify { s.volume = s.spotifyVolume }
        s.service = service
    }
    /// Card BM, change 260: leaving Settings with another service. The old one stops, its
    /// library leaves, and the new one logs in with its stored login: its main menu opens at
    /// the top, with nothing playing. With no stored login, its login screen shows (256).
    func switchService(to service: MusicService) {
        signOut()
        s.controlLostAt = nil  // CLA-97: the old service's loss ends with no control_back; the new one counts its own
        use(service)
        fx.append(.setService(service))
        s.authAttempt += 1; s.restoring = true
        fx.append(.restoreSession(token: s.authAttempt))
    }
    /// Plays the list in shuffle, from a random song.
    func shuffle(_ list: String) {
        let songs = s.tracks(in: list).filter { !$0.missing }  // card CR: never start on a missing file
        guard !songs.isEmpty else { return }
        s.shuffle = true  // before play, so the engine gets shuffle on with the load
        play(list, songs[env.random(songs.count)].id)
    }
    /// The Shuffle Songs row, and Play with nothing to resume (CLA-61; CLA-161, Jason 12:24 JST
    /// 11-20: Play does what Shuffle Songs does). The whole list shuffles from a random song,
    /// with Shuffle on: Songs on Apple Music, Liked Songs on Spotify. A list not read yet loads first.
    func shuffleSongs() {
        if s.offline { return toast(offlineStart) }
        // While a list loads, open nothing more, so no frame is left loading under another.
        if s.top.loading {
            // The shuffle list that loads starts when it is read. A start already pending stays as it is.
            guard s.top.screen == .tracks(playlist: s.shuffleList), s.shuffleToken != s.top.token else { return }
            s.shuffleToken = s.top.token; s.startToken = nil
            return
        }
        if s.loadedTracks.contains(s.shuffleList) {
            shuffle(s.shuffleList)
        } else {  // not read yet: load, then shuffle
            open(.tracks(playlist: s.shuffleList)); s.shuffleToken = s.tok; s.startToken = nil
        }
    }
    /// CLA-173: Play on a playlist or album row starts it on Now Playing, like the iPod. Now
    /// Playing opens over the row's own screen, so MENU goes back to the same row. A list not
    /// read yet shows its loading look while it reads, as Shuffle Songs does, and Now Playing
    /// then takes its place. An empty list opens. Cover Flow's covers: see `.play`.
    func playList(_ id: String, on screen: Screen) {
        if s.offline { return toast(offlineStart) }
        if s.isLoaded(screen) && s.tracks(in: id).contains(where: { !$0.missing }) {  // card CR: else the gray rows show
            refreshIfStale(screen)  // as opening it would: an old copy reads again behind Now Playing
            return startList(id)
        }
        open(screen)
        if s.top.loading { s.startToken = s.top.token; s.startList = id; s.shuffleToken = nil }
    }
    /// Starts a read list as a song pick does: from its first song, or with Shuffle on from a
    /// random song, so the queue is the same as a pick in that list. An empty list plays nothing.
    func startList(_ id: String) {
        let songs = s.tracks(in: id).filter { !$0.missing }  // card CR: never start on a missing file
        guard !songs.isEmpty else { return }
        play(id, songs[s.shuffle ? env.random(songs.count) : 0].id)
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
    let offlineStart = "You’re offline right now"
    /// Card CR: the toast on a gray row, a local song whose file is missing.
    let missingFile = "Can’t find this song’s file"
    func toggleShuffle() { s.shuffle.toggle(); fx.append(.setShuffle(s.shuffle)) }
    func setRepeat(_ mode: RepeatMode) {
        if mode != s.repeatMode { s.repeatMode = mode; fx.append(.setRepeat(mode)) }
    }

    /// Card BI v2: the warning once on day 27 (change 233), over the screen that shows; on day
    /// 30 the beta ends (234). The ended screen replaces everything, and nothing plays.
    func checkBeta() {
        guard let beta = s.beta else { return }
        if now >= beta.endsAt {
            guard s.top.screen != .betaEnded else { return }
            stop()
            if s.hint != nil { endHint(done: false) }
            s.beatUntil = 0; s.toast = ""; s.toastUntil = 0
            s.stack = [Frame(screen: .betaEnded)]
        } else if now >= beta.warnsAt && s.betaWarned != beta.signed && s.canWarnBeta {
            s.betaWarned = beta.signed
            s.betaWarnedNow = true
            s.stack.append(Frame(screen: .betaSoon))
        } else if s.newBetaWaits && s.canWarnBeta {
            // Card BV, change 312: over the screen that shows. Music goes on as it was.
            s.betaNoticed = s.newBetaNow
            s.betaNoticedNow = true
            s.stack.append(Frame(screen: .betaNew))
        }
    }
    func apply() {
        // Change 234: the ended beta takes only the wheel and its rows.
        if s.top.screen == .betaEnded {
            switch action {
            case .wheel, .select, .tick, .batteryChanged, .betaBuild, .latestBeta, .arrived, .menuBarClick, .closeWindow, .deviceTurned: break
            default: return
            }
        }
        switch action {  // change 312: a key or a wheel turn; a later beta answer shows nothing
        case .wheel, .select, .menu, .play, .next, .prev, .toggleShuffle, .cycleRepeat, .searchType, .searchDelete: s.touched = true
        default: break
        }
        switch action {  // CLA-173: another input ends a start that waits on the covers
        case .wheel, .select, .menu, .next, .prev, .toggleShuffle, .cycleRepeat:
            if s.startOnCovers { s.startOnCovers = false; s.startToken = nil }
        default: break
        }
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
            if s.top.screen == .color {
                if s.colorTurnAt == 0 { s.colorTurnAt = now }  // card AW: the first turn
            }
            if s.top.screen == .about {
                // Change 210: a turn wakes a sleeping capybara with a wave, and does not scroll.
                let pose = s.aboutPose(at: now)
                if pose.pose == .sleep { s.aboutWaveAt = now; return }
                // Card BF, change 207: one step a turn, however fast. A step that moves shows
                // the scroll bar for 1.5 s.
                let off = clamp(s.top.off + d.signum(), 0, AppState.aboutSteps)
                if off != s.top.off { s.top.off = off; s.scrollUntil = now + scrollBarTime }
                if pose.pose != .wave { s.aboutIdleAt = now; s.aboutIdleHold = pose }  // any turn restarts the idle clock
                return
            }
            if case .license(let i) = s.top.screen {
                // Change 213: the text moves as a list does, quick steps more lines.
                let off = clamp(s.top.off + d * s.wheelSpeed.rows(at: now), 0, AppState.licenseSteps(i))
                if off != s.top.off { s.top.off = off; s.scrollUntil = now + scrollBarTime }
                return
            }
            guard s.top.screen.isList, !s.top.loading, !s.top.error else { return }
            let n = s.rows(for: s.top).count
            guard n > 0 else { return }
            // CLA-183: on Search, the first turn selects the first row.
            if s.top.screen == .search && !s.searchPicked { s.searchPicked = true; s.top.sel = 0; s.top.off = 0; return }
            // On a list, quick steps move more rows. On Now Playing, a step stays one step.
            let sel = clamp(s.top.sel + d * s.wheelSpeed.rows(at: now), 0, n - 1)
            s.top.off = clamp(s.top.off, sel - s.shownRows + 1, sel)
            s.top.sel = sel
            s.scrollUntil = now + scrollBarTime

        case .select:
            if s.top.screen == .about {
                // Change 210: a press wakes the capybara, or near the top makes it wave. From
                // `aboutLicensesStep` it opens Licenses (change 213); at `aboutStatusStep`,
                // Activation when the Status row opens (card BF.2).
                let pose = s.aboutPose(at: now)
                if pose.pose == .sleep {
                    s.aboutWaveAt = now
                } else if s.top.off >= AppState.aboutLicensesStep || (s.top.off == AppState.aboutStatusStep && s.aboutStatus.opens) {
                    // Change 213: the Licenses list; card BF.2 (change 361): Activation. The pose
                    // waits as it is until About shows again. A press while it waves leaves it
                    // standing, as the wave's end would.
                    s.aboutIdleHold = pose.pose == .wave ? AboutPoseNow(pose: .stand, since: now, from: .wave, cut: true) : pose
                    s.stack.append(Frame(screen: s.top.off >= AppState.aboutLicensesStep ? .licenses : .activation))
                } else if pose.pose != .wave {
                    s.aboutWaveAt = now
                }
                return
            }
            if s.top.screen == .activate && s.activateStep == .confirmed { s.activatedAt = 0; return setupNext() }  // 323: a press goes on
            if s.top.screen == .now {
                s.nowMode = s.nowMode.next  // volume, scrub, shuffle, repeat, then volume again
                s.overlayUntil = now + (s.nowMode == .volume ? 1.5 : sliderTimeout)
                return
            }
            if s.top.error {  // retry
                s.tok += 1
                if s.shuffleToken == s.top.token { s.shuffleToken = s.tok }  // a pending shuffle follows the retry
                if s.startToken == s.top.token { s.startToken = s.tok }
                s.top.loading = true; s.top.error = false; s.top.token = s.tok
                fetch(s.top.screen)
                return
            }
            if s.top.screen == .loggedIn {  // card AX: a press goes on at once
                s.beatUntil = 0
                return setupNext()
            }
            if s.top.screen == .spotifyApp && s.spotifyApp == true { return leaveSpotifyApp() }  // "Linked": on at once
            if s.top.screen == .premium && s.premiumFound {  // "Premium": on at once
                s.beatUntil = 0
                return setupNext()
            }
            if s.top.screen == .yourMusic && s.setupDone {  // "You’re all set": on at once
                s.beatUntil = 0
                s.stack = [Frame(screen: .main)]
                return
            }
            if s.top.screen == .hello {  // card AT: a press begins setup
                s.stack = [Frame(screen: .color)]
                s.top.sel = DeviceColor.allCases.firstIndex(of: s.deviceColor) ?? 0
                s.colorAt = now; s.colorTurnAt = 0
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
            // CLA-183: on Search, the first Return selects the first row; the next opens it.
            if s.top.screen == .search && !s.searchPicked { s.searchPicked = true; s.top.sel = 0; s.top.off = 0; return }
            switch rows[s.top.sel] {
            case .logIn:
                s.authAttempt += 1
                s.stack.append(Frame(screen: .auth, token: s.authAttempt))
                logIn()
            case .getSpotifyApp: fx.append(.getSpotifyApp)
            case .checkPremium:
                // Card AX, screen 135: the cable's light flows once, and Clasify logs in again
                // with the stored login. Still no Premium: nothing else changes.
                s.premiumAt = now
                guard !s.restoring else { return }
                s.authAttempt += 1; s.restoring = true
                fx.append(.restoreSession(token: s.authAttempt))
            case .getPremium: fx.append(.getPremium)
            case .premiumLogOut: leavePremium()
            case .openBrowser, .tryAgain:
                // A new login opens the browser again. The bridge stops the older one, and
                // the new token makes its `.authDone` stale.
                s.authAttempt += 1
                s.stack[s.stack.count - 1] = Frame(screen: .auth, token: s.authAttempt)
                logIn()
            case .nowPlaying: s.stack.append(Frame(screen: .now)); s.nowMode = .volume
            case .coverFlow:
                open(.coverFlow)
                if !s.top.loading { placeCoverFlow() }
            case .playlists: open(.playlists)
            case .artists: open(.artists)
            case .songs: open(.tracks(playlist: Playlist.songsID))
            case .artist(let id): open(.tracks(playlist: id))
            case .albums: open(.albums)
            case .album(let id): open(.tracks(playlist: id))
            case .likedSongs: open(.tracks(playlist: Playlist.likedSongsID))
            case .shuffleSongs: shuffleSongs()
            case .settings: s.stack.append(Frame(screen: .settings)); s.pendingService = nil
            case .search:  // CLA-183: an empty query and no row selected
                s.searchQuery = ""; s.searchPicked = false
                s.stack.append(Frame(screen: .search))
            case .foundSong(let id, let list):
                if s.offline { return toast(offlineStart) }
                play(list, id)
            case .playlist(let id): open(.tracks(playlist: id))
            case .track(let id):
                if s.offline { return toast(offlineStart) }
                guard let list = s.top.screen.songList else { return }
                // Card CR: a gray row (its file is missing) plays nothing.
                if s.tracks(in: list).first(where: { $0.id == id })?.missing == true { return toast(missingFile) }
                play(list, id)
            case .service: s.pendingService = (s.pendingService ?? s.service).next  // applied when Settings closes
            case .shuffle: toggleShuffle()
            case .repeatMode: setRepeat(s.repeatMode.next)
            case .skin: s.skin = s.skin.next  // not in the Settings rows until Dark and Aqua exist
            case .albumArt: s.albumArt = s.albumArt.next
            case .deviceColor: s.deviceColor = s.deviceColor.next
            case .clicker: s.clicker.toggle()
            case .menuBar: s.menuBar.toggle()  // card AN.1, 346: the app adds or takes away the icon
            case .color(let color):  // card AW: a press saves the color, then the music pick (card BM, 257)
                s.deviceColor = color
                if s.signedIn { setupNext() } else { s.stack.append(pickMusic()) }
            case .pickService(let service):
                if service != s.service { use(service); fx.append(.setService(service)) }
                if service == .spotify {
                    // Today's Log In. After a log out on Apple Music, a Spotify login that is
                    // still stored goes on with no browser: "Signing in…" first. In the first
                    // setup, the launch already tried the stored login.
                    s.stack.append(Frame(screen: .login))
                    if s.setupDone { s.authAttempt += 1; s.restoring = true; fx.append(.restoreSession(token: s.authAttempt)) }
                } else {
                    // Change 258: the macOS prompt shows over this screen. Its answer comes
                    // back with this screen's token.
                    s.authAttempt += 1
                    s.stack[s.stack.count - 1].token = s.authAttempt
                    logIn()
                }
            case .openPrivacy: fx.append(.openPrivacy)
            case .getNewBeta:  // the warning closes; the ended screen stays
                fx.append(.getNewBeta)
                if s.top.screen == .betaSoon || s.top.screen == .betaNew { s.stack.removeLast() }
            case .later: s.stack.removeLast()
            case .openActivate, .openActivateAgain, .useAnotherEmail: openActivatePage()
            case .tryActivateAgain:  // 324 (mail busy) opens the page again, because the email is typed there; 327 asks
                if s.activation == .offline { startActivateChecks(); askActivation(Effect.checkActivation, pressed: true) } else { openActivatePage() }
            case .sendAgain: showActivateStep { startActivateChecks() }; askActivation(Effect.sendActivationAgain, pressed: true, check: false)
            case .checkMail:  // 322, 325, 326: the checks start again
                showActivateStep { startActivateChecks() }; askActivation(Effect.checkActivation, pressed: true)
            case .cancelActivate: cancelActivate()
            case .quit: fx.append(.quit)
            case .useSpotify: switchService(to: .spotify)  // change 262
            case .checkLibrary:  // card CR: the screen stays until the new read finds songs
                if s.refreshing.insert(Playlist.libraryID).inserted { fx.append(.refreshTracks(playlist: Playlist.libraryID)) }
            case .pickYourMusic: logOut()  // card CR: as a log out on Apple Music, to Pick Your Music
            case .about:
                // Card BF: it opens at the top. The scroll bar shows from 0.3 s for 1.5 s.
                s.stack.append(Frame(screen: .about))
                s.aboutAt = now; s.scrollUntil = now + 0.3 + scrollBarTime
                s.aboutWaveAt = now + AppState.aboutWaveDelay; s.aboutIdleAt = 0  // change 210: it waves hello
            case .license(let i): s.stack.append(Frame(screen: .license(i)))  // change 213: its text
            case .activatedAs: break  // card BF.2: the one row of Activation does nothing
            case .logOut: s.stack.append(Frame(screen: .confirm))
            case .cancel:
                if s.top.screen == .auth { fx.append(.cancelLogIn) }
                s.stack.removeLast()
            case .confirmLogOut: logOut()
            }

        case .menu:
            if s.top.screen == .now && s.nowMode != .volume { s.nowMode = .volume; s.overlayUntil = 0; return }
            // Not in the mockup: a closed browser tab would leave the login waiting forever.
            if s.top.screen == .auth { s.stack.removeLast(); fx.append(.cancelLogIn); return }
            if s.top.screen == .spotifyApp || s.top.screen == .accessOff { return }  // cards BB, BM: MENU does nothing
            if s.top.screen == .activate {  // card BW: like "Cancel" on 320 and 321, else nothing
                if s.activateStep == .browserOpen || s.activateStep == .checkMail { cancelActivate() }
                return
            }
            if s.top.screen == .premium { return leavePremium() }  // card AX: back to the login
            if s.top.screen == .color && !s.setupDone {
                // CLA-62 (Jason, 12:47 JST 11-10): back to Hello, which starts again. A color
                // that was turned to but not pressed is dropped; the saved one stays.
                s.stack = [Frame(screen: .hello)]; s.helloAt = now
                return
            }
            if s.stack.count < 2 { return }
            if s.top.screen == .settings, let service = s.pendingService {
                s.pendingService = nil
                if service != s.service { return switchService(to: service) }  // back on the old value: nothing happens
            }
            if s.top.screen == .coverFlow { s.letterUntil = 0; s.coverFlowSteps = [] }
            s.stack.removeLast(); s.nowMode = .volume
            // Change 213: back from Licenses (or Activation), the idle clock starts again from the pose it left.
            if s.top.screen == .about { s.aboutIdleAt = now }
            // Card BA, change 151: the first MENU press back toward the main menu ends the MENU
            // hint for good, also before it shows.
            if s.setupDone && s.stack.first?.screen == .main { s.hintsDone.insert(.menu) }

        case .searchType, .searchDelete: searchKey(&s, action)
        case .toggleShuffle: toggleShuffle()
        case .cycleRepeat: setRepeat(s.repeatMode.next)

        case .play:
            if s.setupDone { s.hintsDone.insert(.playPause) }  // card BA, change 176: any press ends that hint
            // The tour's Play starts Shuffle Songs on Now Playing, also when Spotify already had a
            // song when Clasify started (change 199, CLA-161).
            if s.tour == .tourPlay && s.top.screen == .main { return shuffleSongs() }
            // CLA-173: a playlist or album row, or Cover Flow's covers, start that list. A list
            // start that waits for its read stays as it is. Every other screen and row: as before.
            if (s.top.loading && s.startToken == s.top.token) || s.startOnCovers { return }
            if s.top.screen == .coverFlow, !s.top.loading, s.albums.indices.contains(s.top.sel) {
                let id = s.albums[s.top.sel].id
                s.letterUntil = 0; s.coverFlowSteps = []  // as Select: MENU comes back with no letter
                // Now Playing opens over the covers. An empty album plays nothing and the covers stay.
                if s.offline { return toast(offlineStart) }
                if s.isLoaded(.albumPanel(album: id)) { refreshIfStale(.albumPanel(album: id)); return startList(id) }
                // Not read yet: the covers stay, with the album in the middle, while it reads.
                s.tok += 1
                s.startToken = s.tok; s.startList = id; s.startOnCovers = true; s.shuffleToken = nil
                return fetch(.albumPanel(album: id))
            }
            // CLA-183, card CS: on Search, Play plays the selected result; with none selected, nothing.
            if s.top.screen == .search && !s.searchPicked { return }
            if s.top.screen.isList, !s.top.loading, case let rows = s.rows(for: s.top), rows.indices.contains(s.top.sel) {
                if s.top.screen == .search {
                    switch rows[s.top.sel] {
                    case .artist(let id): return playList(id, on: .tracks(playlist: id))
                    case .foundSong(let id, let list): return s.offline ? toast(offlineStart) : play(list, id)
                    default: break
                    }
                }
                switch rows[s.top.sel] {
                case .playlist(let id), .album(let id): return playList(id, on: .tracks(playlist: id))
                default: break
                }
            }
            guard s.current != nil else {
                // CLA-61, CLA-161: nothing to resume, so Play does what Shuffle Songs does. Only on
                // the main screens: never during setup, at login, or on the Spotify App screen.
                guard s.signedIn, s.stack.first?.screen == .main, s.top.screen != .spotifyApp else { return }
                return shuffleSongs()
            }
            if !s.isPlaying && s.offline { return toast("You’re offline right now") }
            s.isPlaying.toggle()
            fx.append(s.isPlaying ? .resume : .pause)

        case .next:
            if s.setupDone { s.hintsDone.insert(.next) }  // card BA, change 177: any press ends that hint
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
            if s.readOverdue(at: now) {  // CLA-170: a silent read
                s.readsPending = s.readsPending.filter { now - $0.value < readWait }
            }
            // Card BA, change 195: the tip after 3 pulses, then the end after 10 s.
            if s.hint != nil && s.hintDue > 0 && now >= s.hintDue { if s.hintTip { endHint(done: true) } else { s.hintTip = true } }
            if s.namesHold > 0 && now >= s.namesHold { endHeldRead() }  // change 191: every name has shown
            if s.beatUntil > 0 && now >= s.beatUntil {  // "You’re in" moves on
                s.beatUntil = 0
                if s.top.screen == .loggedIn { setupNext() }
                if s.top.screen == .spotifyApp && s.spotifyApp == true { leaveSpotifyApp() }
                if s.top.screen == .premium && s.premiumFound { setupNext() }
                if s.top.screen == .yourMusic && s.setupDone { s.stack = [Frame(screen: .main)] }
            }
            if s.top.screen == .activate { activateTick() }
            if s.artUntil > 0 && now > s.artUntil {  // the covers follow the row
                s.artUntil = 0
                if let row = s.halfRow { s.artRow = row }
            }
            // The volume bar hides, and a slider goes back to the progress bar.
            if s.overlayUntil > 0 && now > s.overlayUntil { s.overlayUntil = 0; s.nowMode = .volume }
            if s.scrollUntil > 0 && now > s.scrollUntil { s.scrollUntil = 0 }
            if s.letterUntil > 0 && now > s.letterUntil { s.letterUntil = 0 }
            checkBeta()

        case .position(let t, let gen):
            // Soon after a seek, a position far from the target is from an earlier seek.
            // With Repeat One, a seek near the end can wrap to the start of the same track.
            let since = now - s.seekAt
            let end = s.current.flatMap { s.track($0)?.duration } ?? .infinity
            let wrapped = s.repeatMode == .one && s.seekTarget >= end - seekSettle && t <= seekSlack + since
            if gen == s.seekGen && s.current?.track == s.seekTrack && since < seekSettle && !wrapped
                && abs(t - s.seekTarget) > seekSlack + since { return }
            if s.current != nil && gen == s.playGen { s.t = t; s.beforeLoad = nil; s.loadPending = false }  // the load plays

        case .volumeReported(let percent):  // Spotify's volume stays in `volume` / `spotifyVolume`
            guard s.service != .spotify else { return }
            s.volume = clamp(percent, 0, 100)

        case .trackEnded(let gen):  // the engine already stopped; Repeat One and All never end
            guard s.isPlaying, s.current != nil, gen == s.playGen else { return }
            s.isPlaying = false; s.t = 0

        case .trackChanged(let id, let playing, let gen):
            // Same playlist. A track that is not in our copy of it still shows as current, by ID.
            guard s.current != nil, gen == s.playGen else { return }
            s.isPlaying = playing; s.beforeLoad = nil; s.loadPending = false  // the load plays
            if s.current?.track != id {
                // CLA-170: an unknown song keeps the last known words (fast Next: still the first one's).
                if let known = s.current.flatMap({ s.track($0) }) { s.heldWords = NowWords(title: known.title, artist: known.artist) }
                s.current?.track = id; s.t = 0
            }
            readIfUnknown(id)

        case .trackRead(let id, let track):
            // Not asked for in this session, for example a read from before a sign-out.
            guard s.trackReads.contains(id) else { return }
            s.readsPending[id] = nil  // CLA-170: answered, so the words wait no more
            guard let track else { return }  // failed: the ID stays, so it is not read again
            s.trackReads.remove(id)
            keepExtra(track)

        case .adopted(let id, let pl, let playing, let t, let gen):
            guard s.current == nil, gen == s.playGen else { return }  // a load or a newer one came first
            if s.activateGated && s.stack.first?.screen == .activate { return }  // CLA-140: nothing plays behind Activate
            s.current = TrackRef(playlist: pl ?? "", track: id)  // "" is no playlist of ours
            s.heldWords = nil  // CLA-170: no earlier song
            s.isPlaying = playing; s.t = t
            shiftMainSelection(by: 1)  // the new Now Playing row goes on top: keep the pick
            readIfUnknown(id)

        case .playbackFailed(let msg, let gen):
            guard s.current != nil, gen == s.playGen else { return }
            s.isPlaying = false; s.beforeLoad = nil; s.loadPending = false  // the load, if any, has ended
            if s.top.screen != .spotifyApp { toast(msg) }  // card BB says it there

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
            if s.top.screen != .spotifyApp { toast(msg) }

        case .artistsLoaded(let token, let artists):
            guard s.top.loading, s.top.token == token else { return }  // stale load
            if let artists {
                s.artists = artists.sorted { Playlist.nameOrder($0.name, $1.name) }
                s.artistsLoaded = true
                s.readAt[AppState.artistsKey] = now
            }
            finishLoad(token, ok: artists != nil)

        case .artistsRefreshed(let artists):
            guard s.refreshing.remove(AppState.artistsKey) != nil, let artists else { return }
            let old = s.rows(for: Frame(screen: .artists))
            s.artists = artists.sorted { Playlist.nameOrder($0.name, $1.name) }
            s.artistsLoaded = true  // CLA-183: Search's quiet read can be the first one
            s.readAt[AppState.artistsKey] = now
            keepSelection(on: .artists, old: old)

        case .playlistsLoaded(let token, let playlists):
            guard s.top.loading, s.top.token == token else { return }  // stale load
            if let playlists { setPlaylists(playlists) }
            finishLoad(token, ok: playlists != nil)

        case .playlistsRefreshed(let playlists):
            // Not asked for in this session, for example from before a sign-out.
            guard s.refreshing.remove(AppState.readKey(.playlists)) != nil else { return }
            // CLA-74: Liked Songs was read first, and "Getting your music" waits for the list.
            let waiting = s.namesHold == .infinity
            guard let playlists else {
                if waiting { endHeldRead() }  // no names to show: setup goes on
                return
            }
            let old = s.rows(for: Frame(screen: .playlists))
            setPlaylists(playlists)
            keepSelection(on: .playlists, old: old)
            if s.top.screen == .yourMusic && s.top.loading { s.namesAt = now }  // the names fill in from now
            if waiting && !holdForNames() { endHeldRead() }  // no playlists: setup goes on

        case .activated:
            // Card BM, change 258: back from System Settings, Access is off checks again. With
            // access, setup goes on as after Allow; still none, the screen stays as it is.
            if s.top.screen == .accessOff && !s.restoring {
                s.authAttempt += 1; s.restoring = true
                fx.append(.restoreSession(token: s.authAttempt))
                return
            }
            refreshShown()

        case .libraryStale:
            s.readAt = [:]
            refreshShown()

        case .tracksRefreshed(let id, let tracks):
            guard s.refreshing.remove(id) != nil, let tracks,
                let i = s.library.firstIndex(where: { $0.id == id })  // the playlist is gone
            else { return }
            // The screens that show this list: the song list, and for Liked Songs, Albums and its albums.
            var screens = [Screen.tracks(playlist: id)]
            // The library's albums: each read album is its songs there, so it changes with them.
            let albums = id == Playlist.libraryID ? s.library.map(\.id).filter(Album.isID) : []
            for f in s.stack where (s.readKey(f.screen) == id || albums.contains(s.readKey(f.screen))) && !screens.contains(f.screen) {
                screens.append(f.screen)
            }
            let old = screens.map { s.rows(for: Frame(screen: $0)) }
            // The playing track left the list (or its album): keep its details for Now Playing.
            // An album that was not read shows its liked songs, so it changes with Liked Songs.
            let pl = s.current?.playlist ?? ""
            let shows = pl == id || albums.contains(pl) || (id == s.albumsList && Album.isID(pl) && !s.loadedTracks.contains(pl))
            let playing = shows ? s.current.flatMap { s.track($0) } : nil
            s.library[i].tracks = tracks; s.library[i].trackCount = tracks.count
            for j in s.library.indices where albums.contains(s.library[j].id) {
                s.library[j].tracks = Album.songs(s.library[j].id, in: tracks); s.library[j].trackCount = s.library[j].tracks.count
            }
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
                s.library.insert(Playlist(id: id, name: s.likedSongsName, tracks: tracks), at: 0)
            } else if id == Playlist.libraryID {  // the main menu's covers on Apple Music; not a row
                s.library.append(Playlist(id: id, name: "", tracks: tracks))
            } else {
                return  // the playlist is gone
            }
            s.loadedTracks.insert(id)
            s.readAt[id] = now

        case .tracksLoaded(let token, let id, let tracks):
            // CLA-173: read behind the covers, while they still show.
            let onCovers = s.startOnCovers && s.startToken == token && s.top.screen == .coverFlow
            guard onCovers || (s.top.loading && s.top.token == token) else { return }  // stale load
            if let tracks {
                if let i = s.library.firstIndex(where: { $0.id == id }) {
                    s.library[i].tracks = tracks; s.library[i].trackCount = tracks.count
                } else if id == Playlist.likedSongsID {
                    s.library.insert(Playlist(id: id, name: s.likedSongsName, tracks: tracks), at: 0)
                } else {
                    s.library.append(Playlist(id: id, name: "", tracks: tracks))
                }
                s.loadedTracks.insert(id)
                s.readAt[id] = now
            }
            if onCovers {
                s.startOnCovers = false; s.startToken = nil
                if tracks == nil || s.offline { return toast("Can’t reach \(s.words.service)") }
                return startList(id)  // an empty album plays nothing: the covers stay
            }
            if s.top.screen == .yourMusic, let tracks, !s.offline {
                // Card AY, change 191: "Getting your music" stays until every name has shown.
                // CLA-74: when the read at login ended before the playlist list came, it also
                // waits for the list. The bar and the counts end full, also if the last reports
                // come late; the count also sets the pace (changes 266 and 267).
                s.readDone = tracks.count; s.readTotal = tracks.count
                s.readAlbums = Set(tracks.compactMap { $0.album?.id }).count
                if s.firstReadSongs == nil { s.firstReadSongs = tracks.count; s.firstReadSongsAt = now }
                let listPending = s.namesAt == 0 && s.refreshing.contains(AppState.readKey(.playlists))
                if listPending { s.namesHold = .infinity }
                if listPending || (s.namesAt > 0 && holdForNames()) { return }
            }
            finishLoad(token, ok: tracks != nil)
            if s.top.screen == .yourMusic && !s.top.error { endFirstRead() }

        case .launch:
            guard !s.signedIn, s.stack == [Frame(screen: .login)] else { return }
            if !s.setupDone { s.stack = [Frame(screen: .hello)]; s.helloAt = now }
            // CLA-120: after setup, the app opens on the main menu at once, with no slide, and
            // the stored login is checked behind it. Its failures show their screens as before.
            // With the Spotify app missing, the login screen stays: the restore goes on to it.
            // CLA-140: a set-up Mac that is not activated sees only Activate. The stored login is
            // restored after it (setupNext), so nothing reads or plays behind it.
            if s.setupDone && s.activateGated { s.stack = [Frame(screen: .activate)]; return }
            if s.setupDone && !(s.spotifyApp == false && s.service == .spotify) { s.stack = [Frame(screen: .main)] }
            restore()

        case .readProgress(let id, let done, let total, let albums):
            guard s.top.screen == .yourMusic, s.top.loading, s.namesHold == 0, id == s.readKey(.yourMusic) else { return }
            // Each report hops to the main actor in its own task, so two can come out of order.
            // For the same read, the count never goes back.
            s.readDone = total == s.readTotal ? max(s.readDone, done) : done
            s.readTotal = total
            s.readAlbums = max(s.readAlbums, albums)
            if total > 0 && s.firstReadSongs == nil { s.firstReadSongs = total; s.firstReadSongsAt = now }  // changes 266 and 267

        case .spotifyAppFound(let found):
            let was = s.spotifyApp
            s.spotifyApp = found
            if s.top.screen == .spotifyApp {
                // Card BB, change 174: "Linked" shows for a beat, then Clasify goes on.
                if found && was != true { s.beatUntil = now + AppState.beatTime }
                if !found { s.beatUntil = 0 }
            } else if !found && s.signedIn && s.setupDone && s.service == .spotify {
                // Change 131: the app went away while Clasify was open (a play found it gone).
                // The screen opens over this one, and closes back to it when the app is found.
                if s.top.screen == .loggedIn {  // over "You’re in", it takes its place: then on to the main menu
                    s.beatUntil = 0
                    s.stack = [Frame(screen: .spotifyApp)]
                } else {
                    s.stack.append(Frame(screen: .spotifyApp))
                }
            }

        case .restored(let token, let ok):
            guard s.restoring, s.authAttempt == token else { return }  // from before a reset
            s.restoring = false
            // CLA-120: the main menu showed while the stored login was checked. With none, the
            // login screen shows, as before.
            let onMain = !s.signedIn && s.setupDone && s.stack.first?.screen == .main
            guard ok else {
                if onMain { s.stack = [Frame(screen: .login)] }
                return
            }
            s.signedIn = true; fx.append(.prefetch)
            if onMain && s.top.loading {  // a list opened meanwhile: its read starts now
                s.tok += 1
                if s.shuffleToken == s.top.token { s.shuffleToken = s.tok }
                if s.startToken == s.top.token { s.startToken = s.tok }
                s.top.token = s.tok
                fetch(s.top.screen)
            }
            // During setup, Hello and the color pick stay. The login screen goes on, and so does
            // Access is off after access was turned on (card BM, 258).
            if s.top.screen == .login || s.top.screen == .accessOff { setupNext() }
            if s.top.screen == .premium {
                // "Check again" found Premium: the green check for a beat, then on (screen 135).
                s.premiumFound = true; s.premiumAt = now
                s.beatUntil = now + AppState.beatTime
            }

        case .notPremium(let token):
            // Only for the login or restore that runs now, or a session that is in. A late one
            // from an older attempt ("Open browser again"), a logout or a reset is dropped.
            if let token {
                let login = (s.top.screen == .auth || s.top.screen == .pickMusic) && s.top.token == token
                guard login || (s.restoring && s.authAttempt == token) else { return }
            } else {
                guard s.signedIn, !(s.activateGated && s.stack.first?.screen == .activate) else { return }  // CLA-140
            }
            s.restoring = false
            s.authAttempt += 1  // a late result of this login is stale
            s.activateHandOver = false
            if s.top.screen == .premium { return }  // "Check again": still no Premium, no change
            // A restore at launch during setup: Hello and the color pick stay. The browser
            // login after them shows the Premium screen.
            if !s.signedIn && (s.top.screen == .hello || s.top.screen == .color) { return }
            signOut()  // the session ended, and the library belongs to that account
            s.stack = [Frame(screen: .premium)]
            s.premiumFound = false; s.premiumAt = 0

        case .authDone(let token, let ok):
            // The Apple Music prompt answers on Pick Your Music (card BM, change 258).
            let prompt = s.top.screen == .pickMusic
            guard s.top.screen == .auth || prompt, s.top.token == token else { return }  // stale attempt
            // A login that worked counts even if the app went offline since: its token is saved.
            // Card AX: a failed login says so in place of the wait (171). One that worked shows
            // "You’re in" for a beat (175), then goes on.
            if !ok && prompt { s.stack[s.stack.count - 1].token = 0; return }  // a press asks again
            if !ok { s.activateHandOver = false; s.stack[s.stack.count - 1] = Frame(screen: .loginFailed); return }
            s.signedIn = true; s.sessionEnded = false
            fx.append(.prefetch)
            s.stack = [Frame(screen: .loggedIn)]
            s.beatUntil = now + AppState.beatTime

        case .offline(let on):
            if on && s.isPlaying { s.isPlaying = false; fx.append(.pause); toast("Paused while you’re offline") }
            s.offline = on

        case .batteryChanged(let battery):
            s.battery = battery

        case .betaBuild(let beta):
            // Card BV: once a launch, betas only, and not on an ended beta (313: its screen has Get New Beta).
            if let beta, s.beta == nil, now < beta.endsAt {
                fx.append(.checkLatestBeta)
                s.newBetaNow = s.newBeta  // a build found before shows at once, with no wait
            }
            s.beta = beta
            checkBeta()

        case .activation(let activation, let request, let failure):
            if let request, request == s.activateAsked { s.activateAsked = 0 }  // CLA-146: the next check may go
            guard request == nil || request == s.activateRequest else { return }  // an older request
            // Card BW: a timer check with no connection waits for the next one; a press shows 327.
            if activation == .offline && request != s.activatePressed { return }
            // CLA-140: the app remembers "activated". A launch answer that says this remembered
            // Mac is not active locks it: Activate shows over everything.
            let lock = request == nil && s.activated && s.setupDone && s.stack.first?.screen != .activate
            switch activation {
            case .active: s.activated = true
            case .locked, .waiting, .off: s.activated = false
            case .full, .mailBusy, .offline: break
            }
            showActivateStep {
                s.activation = activation
                s.activateFailure = activation == .offline ? failure : nil
                switch activation {
                case .waiting(_, let mail): if let open = s.activateOpenMail, mail > open { s.activateOpenMail = nil }  // a new mail: 321
                case .locked: break  // no mail yet: 320 stays
                case .active, .full, .off, .mailBusy, .offline: s.activateOpenMail = nil; s.activateStopAt = 0
                }
                if activation.isActive && s.top.screen == .activate {  // 323, then Your Music
                    s.activatedAt = now
                    if !fx.contains(.showWindow) { fx.append(.showWindow) }  // CLA-153: myPod comes back from the browser
                }
            }
            if lock && !s.activated { lockToActivate(activation) }

        case .loginCarriesActivate(let token):
            guard s.top.screen == .auth, s.top.token == token, s.activateGated else { return }  // a stale login
            s.activateHandOver = true

        case .checkActivation:
            // CLA-146: also on 322, after the 3 minutes. It does not start the 3 minutes again.
            guard s.top.screen == .activate,
                  [.browserOpen, .checkMail, .stopped].contains(s.activateStep) else { return }
            askActivation(Effect.checkActivation, pressed: false)

        case .latestBeta(let build):
            // Every answer is saved ("never miss"); only one before the first key may show now.
            s.newBeta = max(build, s.newBeta ?? 0)
            // The number on a notice that shows never changes under the user.
            if !s.touched && !s.betaNoticedNow && build > (s.newBetaNow ?? 0) { s.newBetaNow = build }
            checkBeta()

        case .libraryWords(let words):
            s.words = words

        case .accessDenied(let token):
            // Change 258: from the prompt on Pick Your Music, or from a restore.
            let prompt = s.top.screen == .pickMusic && s.top.token == token
            guard prompt || (s.restoring && s.authAttempt == token) else { return }
            s.restoring = false
            s.authAttempt += 1  // a late result of this login is stale
            if !s.signedIn && (s.top.screen == .hello || s.top.screen == .color) { return }  // setup goes on to the pick
            signOut()
            s.stack = [Frame(screen: .accessOff)]

        case .expire:
            // Forget the stored login too, so that a later .launch does not restore it. The login
            // screen says "Log in again", and after the login the main menu opens (change 181).
            if s.signedIn { signOut(); s.sessionEnded = true; fx.append(.logOut) }

        case .menuBarClick(let shown):
            // 348: the first setup always shows in the window, so the icon does not hide it.
            fx.append(shown && s.setupDone ? .hideWindow : .showWindow)
        case .closeWindow:
            if s.setupDone { fx.append(.hideWindow) }
        case .deviceTurned(let turned):
            s.deviceTurned = turned

        case .controlLost(let reason):
            guard s.controlLostAt == nil else { return }  // one loss until control comes back
            s.controlLostAt = now
            fx.append(.track(.controlLost(reason, service: s.service)))

        case .used, .willQuit, .view3D, .window: break  // only for `day_active` (dayEvents)
        case .analyticsOn(let on): s.analyticsOn = on
        case .hintsTrial(let on): s.hintsTrial = on
        case .appProblems(let problems):
            // The budget is for the whole run: MetricKit can hand over reports more than once.
            for problem in problems.prefix(max(0, AppProblem.maxPerLaunch - s.problemsSent)) {
                s.problemsSent += 1
                fx.append(.track(.appProblem(problem, service: s.service)))
            }
        case .appStarted(let ms): s.startMs = ms

        case .controlBack:
            guard let lost = s.controlLostAt else { return }
            s.controlLostAt = nil
            fx.append(.track(.controlBack(seconds: max(0, Int((now - lost).rounded())), service: s.service)))

        case .arrived:
            guard !s.arrived else { return }
            s.arrived = true
            if s.top.screen == .hello { s.helloAt = now }  // Hello starts as the device lands

        case .reset:
            stop()
            let (tok, gen, auth, art) = (s.tok, s.playGen, s.authAttempt, s.artTok)  // keep counters so callbacks from before the reset stay stale
            let nav = (s.navSeq, s.wholeSeq)  // keep the screen's identity, so the skin does not slide the reset screen in
            let settings = s.settings  // saved settings stay
            let (battery, spotifyApp, beta) = (s.battery, s.spotifyApp, s.beta)  // the Mac and the build, which a reset does not change
            let words = s.words  // the active service's library, which a reset does not change
            s = AppState()
            s.tok = tok; s.playGen = gen; s.authAttempt = auth; s.artTok = art; (s.navSeq, s.wholeSeq) = nav; s.settings = settings
            s.battery = battery; s.spotifyApp = spotifyApp; s.beta = beta; s.words = words
        }
    }
    let before = (s.stack.count, s.top.screen, s.top.loading)
    let playHintDone = s.hintsDone.contains(.playPause)
    let tourShown = s.hint?.isTour == true && s.hintTip ? s.hint : nil  // its words showed
    // Change 288: while the device arrives, the wheel, the buttons and the keys do nothing,
    // and the tour and hints do not see them either. CLA-130: the same while it is turned.
    if !s.arrived || s.deviceTurned {
        switch action {
        case .wheel, .select, .menu, .play, .next, .prev, .toggleShuffle, .cycleRepeat, .searchType, .searchDelete: return []
        default: break
        }
    }
    let wasOverPanel = s.nowOverPanel || s.nowOverCovers
    let wasSignedIn = s.signedIn
    let rowBefore = s.halfRow
    let wasOffline = s.offline
    let artBefore = (s.artRow, s.library, s.current, s.loadedTracks, s.extraTracks)  // copies share storage, so this is cheap
    let searchBefore = SearchInputs(s)
    apply()
    searchAfter(&s, searchBefore, now: now)
    // CLA-179, card CR: On This Mac reads the whole library when its main menu opens, also with
    // no covers. Empty, "No songs yet" takes the main menu's place until a read finds songs.
    let library = Playlist.libraryID
    if s.service == .local && s.signedIn && !s.offline && s.stack.count == 1 && s.top.screen == .main
        && (before.1 != .main || !wasSignedIn) {
        if !s.loadedTracks.contains(library) {
            if s.artReads[library] == nil {
                s.artTok += 1; s.artReads[library] = s.artTok
                fx.append(.readArtTracks(token: s.artTok, playlist: library))
            }
        } else {
            // Read before: every list read so far reads again quietly when older than
            // `localStaleAfter` (the app shares one library read between them). The rows stay
            // until the answers come; the playing song and its queue do not change.
            for key in s.loadedTracks.sorted() { refreshIfStale(.tracks(playlist: key), after: localStaleAfter) }
            if s.playlistsLoaded { refreshIfStale(.playlists, after: localStaleAfter) }
            // The artists are read once a session on other services (card BN); here they
            // follow the library, so a new artist shows with its songs.
            let artists = AppState.artistsKey
            if s.artistsLoaded && now - (s.readAt[artists] ?? 0) >= localStaleAfter && !s.refreshing.contains(artists) {
                s.refreshing.insert(artists)
                fx.append(.refreshArtists)
            }
        }
    }
    if s.localEmpty && s.signedIn && s.stack.count == 1 && s.top.screen == .main { s.stack = [Frame(screen: .noSongs)] }
    if s.top.screen == .noSongs && !s.localEmpty { s.stack = [Frame(screen: .main)] }
    // A new screen slides in: from the right when it opens, from the left on a way back.
    // The screen after a login counts as opening. A reset and the first screen at launch do not slide.
    let slides = switch action {
    case .reset, .launch: false
    default: true
    }
    if slides && (s.stack.count, s.top.screen) != (before.0, before.1) {
        s.navSeq += 1
        s.navForward = s.stack.count >= before.0 || (s.signedIn && !wasSignedIn)
        if s.top.screen == .hello { s.navForward = false }  // Hello is only ever gone back to (CLA-62)
        if s.top.screen == .premium { s.navForward = true }  // screen 135 opens after a login
        if before.1 == .premium && s.top.screen == .login { s.navForward = false }  // back from screen 135
        // Between a half screen and a full one, the whole screen moves; otherwise only the content.
        // Hello has no title bar, so the whole screen moves to and from it too (CLA-62).
        let whole = s.isHalf(before.1) != s.isHalf(s.top.screen) || before.1 == .hello || s.top.screen == .hello
        if whole { s.wholeSeq += 1 }
        // The cover flies only to and from a Now Playing that shows the panel's album, or the
        // middle album of the covers (card CI).
        let fly = before.1 == .now ? wasOverPanel : s.nowOverPanel || s.nowOverCovers
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
        // The list that the covers come from: the selected playlist, or `albumsList` for the main
        // menu's rows (see `refreshArt`), which nothing else reads at first open.
        let artList: String? = switch s.artRow {
        case .playlist(let id)?: id
        case .nowPlaying?, nil: nil
        default: s.top.screen == .main ? s.albumsList : nil  // Playlists picks a playlist soon
        }
        // Read when the covers move to a list or the app comes back online, not on each
        // tick, so a failed read is tried again only when the row is selected again. CLA-120:
        // the main menu at launch shows before the stored login is back: its read waits for it.
        let signsIn = !wasSignedIn && s.signedIn
        if let id = artList, opened || s.artRow != artBefore.0 || (wasOffline && !s.offline) || signsIn,
            s.signedIn, !s.loadedTracks.contains(id), !s.offline, s.artReads[id] == nil {
            s.artTok += 1; s.artReads[id] = s.artTok
            fx.append(.readArtTracks(token: s.artTok, playlist: id))
        }
    }
    // The bar for the playing track comes and goes, so keep the selection in the rows that show.
    if s.top.screen.isList { s.top.off = clamp(s.top.off, s.top.sel - s.shownRows + 1, s.top.sel) }
    // Card BA: one first-time hint at a time, after setup, with no toast. A hint stops while its
    // screen does not show, and starts again later. Change 139: the MENU hint shows on a list
    // opened from the main menu, with no load or message; going deeper, it starts again on the
    // new list. Changes 176 and 177: the play/pause hint, then on a later visit the next hint,
    // show on Now Playing once a song has played 10 s.
    /// Card BA.2, change 238 (Jason OK 15:59 JST 11-12): the first-run hints as a queue. It
    /// starts when "You’re all set" goes on to the main menu after the first setup. One hint at
    /// a time: Play, then Next, then MENU. A press of its button ends a hint, also before it
    /// shows. Other input only hides it; it shows again after `tourRest` with no input, on its
    /// screen. A hint hidden `tourHideMax` times while its words showed is done. When all
    /// three are done, the tour and the BA hints end for good (CTO rule from BA.1).
    func tour() {
        let steps: Set<Hint> = [.tourPlay, .tourNext, .tourMenu]
        if !s.tourOn && before.1 == .yourMusic && s.top.screen == .main && s.setupDone && s.hintsDone.isDisjoint(with: steps) {
            s.tourOn = true; s.tourRestAt = now  // saved: once ever
        }
        // CLA-163, card CE.1: a tour that ended before the trial's step came goes on with it.
        if !s.tourOn && s.setupDone && s.hintsDone.isSuperset(of: steps)
            && s.tourSteps.contains(where: { !s.hintsDone.contains($0) }) {
            s.tourOn = true; s.tourRestAt = now
        }
        guard s.tourOn else { return }
        switch action {
        case .play: s.hintsDone.insert(.tourPlay)
        case .next, .prev: s.hintsDone.insert(.tourNext)
        case .menu where s.stack.count < before.0: s.hintsDone.insert(.tourMenu)  // MENU that went back
        case .menuBarClick where s.tourSteps.contains(.tourMenuBar): s.hintsDone.insert(.tourMenuBar)  // 388: any click
        case .deviceTurned(true) where s.tourSteps.contains(.tourTurn): s.hintsDone.insert(.tourTurn)  // the first ⌘ turn
        default: break
        }
        if s.isPlaying { s.hintsDone.insert(.tourPlay) }  // the music started another way
        switch action {
        // CE.1: a click on the menu bar icon and a ⌘ turn are input too (mock), so the next
        // hint waits 3 s after them: the menu bar hint does not glow the moment a turn ends it.
        case .wheel, .select, .menu, .play, .next, .prev, .toggleShuffle, .cycleRepeat, .menuBarClick, .deviceTurned,
            .searchType, .searchDelete:
            if let hint = tourShown, !s.hintsDone.contains(hint) {
                let n = s.tourHides[hint, default: 0] + 1
                s.tourHides[hint] = n
                if n >= AppState.tourHideMax { s.hintsDone.insert(hint) }
            }
            s.tourRestAt = now
        default: break
        }
        guard let step = s.tour else {
            s.tourOn = false
            s.hintsDone.formUnion([.menu, .playPause, .next])
            if s.hint?.isTour == true { endHint(done: false) }
            return
        }
        // A tour tip has no time-out, so a toast that waits for it (offline, Spotify closed)
        // would never show. The tip gives way, and it comes back after the toast.
        if !s.heldToast.isEmpty && s.hint?.isTour == true { endHint(done: false) }
        let shown: Hint? = s.tourPlace && now >= s.tourShowAt ? step : nil
        guard shown != s.hint else { return }
        if shown == nil { return endHint(done: false) }
        if s.hint == nil && !s.toast.isEmpty { return }  // a status toast goes first
        s.hint = shown; s.hintAt = now; s.hintTip = !s.glowsFirst(shown)
    }
    if case .reset = action {} else { tour() }
    if case .reset = action {} else {
        if !playHintDone && s.hintsDone.contains(.playPause) { s.hintPlaySeq = s.navSeq }
        func playing() -> Bool {
            s.top.screen == .now && s.current != nil && s.isPlaying && s.nowMode == .volume && s.overlayUntil <= now
        }
        func fits(_ hint: Hint) -> Bool {
            guard s.setupDone, s.signedIn, s.stack.first?.screen == .main, !s.hintsDone.contains(hint) else { return false }
            switch hint {
            // Not over the beta warning (card BI v2): its own rows say what to do.
            case .menu: return s.stack.count > 1 && s.top.screen.isList && !s.top.loading && !s.top.error
                && s.top.screen != .betaSoon && s.top.screen != .betaNew
            // On Now Playing, only while a song plays and that row shows the time bar: the tip
            // takes its place, and the volume bar, a scrub or a setting needs that row.
            case .playPause: return playing()
            case .next: return playing() && s.hintsDone.contains(.playPause) && s.navSeq != s.hintPlaySeq
            case .tourPlay, .tourNext, .tourMenu, .tourMenuBar, .tourTurn: return false  // see `tour()`
            }
        }
        if s.tour != nil {  // the tour shows its own hints
        } else if let hint = s.hint, !fits(hint) {
            endHint(done: false)
        } else if s.hint == .menu && (s.stack.count, s.top.screen) != (before.0, before.1) {
            s.hintAt = now; s.hintTip = false
        }
        let played = s.t >= AppState.hintPlayTime
        if s.tour == nil && s.hint == nil && s.toast.isEmpty, let hint = Hint.allCases.first(where: { fits($0) && ($0 == .menu || played) }) {
            s.hint = hint; s.hintAt = now; s.hintTip = false
        }
    }
    return fx
}

// CLA-183: Search's parts of the reducer, in their own functions. `reduceAction` is very large,
// and its stack frame in a debug build is near the 512 KB of a macOS test thread.

/// A key on Search. A typed key or Delete clears the selection, as the try page does.
private func searchKey(_ s: inout AppState, _ action: Action) {
    guard s.top.screen == .search else { return }
    switch action {
    case .searchType(let c):
        guard Search.types(c), s.searchQuery.count < Search.maxQuery else { return }
        s.searchQuery.append(c)
    case .searchDelete:
        guard !s.searchQuery.isEmpty else { return }
        s.searchQuery.removeLast()
    default: return
    }
    s.searchPicked = false; s.top.sel = 0; s.top.off = 0  // new results: none selected
}

/// What Search's results depend on, before an action.
private struct SearchInputs {
    let query: String, library: [Playlist], artists: [Playlist], loadedTracks: Set<String>, open: Bool
    init(_ s: AppState) {
        query = s.searchQuery; library = s.library; artists = s.artists; loadedTracks = s.loadedTracks
        open = s.stack.contains { $0.screen == .search }
    }
}

/// The one place where Search's results follow the query and the library data, while Search
/// is open. The index is made when Search opens and when library data arrives; each key only
/// asks it. A selection past the new end moves to the last row. Leaving Search clears it.
private func searchAfter(_ s: inout AppState, _ before: SearchInputs, now: Double) {
    guard s.stack.contains(where: { $0.screen == .search }) else {
        if before.open {
            s.searchResults = []; s.searchQuery = ""; s.searchPicked = false; s.searchIndex = nil
            s.searchBox.value.stale = false  // no `.tick` for a closed Search
        }
        return
    }
    // CTO on #457: the quiet reads bring new data often, so the index is made again at most
    // once a `Search.rebuildWait`. A later change waits for the next action or `.tick`
    // (`AppState.searchIndexDue`). Opening Search makes it at once.
    if before.library != s.library || before.artists != s.artists || before.loadedTracks != s.loadedTracks {
        s.searchBox.value.stale = true
    }
    let rebuild = !before.open || s.searchIndex == nil || s.searchIndexDue(at: now)
    if rebuild {
        s.searchIndex = Search.Index(s)
        s.searchBox.value.builtAt = now; s.searchBox.value.stale = false
    }
    guard rebuild || before.query != s.searchQuery, let index = s.searchIndex else { return }
    let old = s.searchResults
    s.searchResults = index.results(s.searchQuery)
    for f in s.stack.indices where s.stack[f].screen == .search {
        // New data under the same query: the selected row stays on its result when it is still
        // there, also when rows come in above it.
        if s.searchPicked, before.query == s.searchQuery, old.indices.contains(s.stack[f].sel),
            let i = s.searchResults.firstIndex(of: old[s.stack[f].sel]) {
            s.stack[f].sel = i
        }
        s.stack[f].sel = min(s.stack[f].sel, max(s.searchResults.count - 1, 0))
        s.stack[f].off = min(s.stack[f].off, s.stack[f].sel)
    }
    if s.searchResults.isEmpty { s.searchPicked = false }
}

/// CLA-183: while Search is open, the lists it finds songs in are read quietly, one at a time,
/// with no spinner: first the albums list, then the playlist list, then the artists (Apple Music
/// and On This Mac), then each playlist that is not read yet, in row order. Each read uses a
/// path that already exists, and its answer goes in like that path's answer, so the results
/// follow it. A read that fails is not tried again while Search stays open. Leaving Search
/// starts no new read; one in flight still lands. A sign-out or a service switch clears
/// `artReads` and `refreshing`, so an old answer is dropped there and the next read starts on the new library.
private func searchReads(_ s: inout AppState) -> [Effect] {
    let playlists = AppState.readKey(.playlists), artists = AppState.artistsKey
    func inFlight(_ key: String) -> Bool {
        key == playlists || key == artists ? s.refreshing.contains(key) : s.artReads[key] != nil
    }
    func isRead(_ key: String) -> Bool {
        switch key {
        case playlists: s.playlistsLoaded
        case artists: s.artistsLoaded
        default: s.loadedTracks.contains(key)
        }
    }
    // The last read is done: a list it did not fill is skipped until Search opens again.
    if let key = s.searchBox.value.reading, !inFlight(key) {
        s.searchBox.value.reading = nil
        if !isRead(key) { s.searchBox.value.skipped.insert(key) }
    }
    guard s.stack.contains(where: { $0.screen == .search }) else {
        if !s.searchBox.value.skipped.isEmpty { s.searchBox.value.skipped = [] }
        return []
    }
    // One read at a time: none starts while any other read of the library runs (a cover read,
    // a quiet reread, or an open, which also covers a list that the person opened).
    guard s.searchBox.value.reading == nil, s.signedIn, !s.offline, s.artReads.isEmpty, s.refreshing.isEmpty,
        !s.stack.contains(where: \.loading) else { return [] }
    var keys = [s.albumsList, playlists]
    if s.service != .spotify { keys.append(artists) }  // Spotify gives no artist list (S1)
    keys += s.library.lazy.filter { !Playlist.isHidden($0.id) }.map(\.id)
    guard let key = keys.first(where: { !isRead($0) && !s.searchBox.value.skipped.contains($0) }) else { return [] }
    s.searchBox.value.reading = key
    switch key {
    case playlists:
        s.refreshing.insert(key)
        return [.refreshPlaylists]
    case artists:
        s.refreshing.insert(key)
        return [.refreshArtists]
    default:
        s.artTok += 1; s.artReads[key] = s.artTok
        return [.readArtTracks(token: s.artTok, playlist: key)]
    }
}
