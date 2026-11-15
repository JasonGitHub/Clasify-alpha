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
    /// The library's artists were read (card BN). nil when the read failed.
    case artistsLoaded(token: Int, artists: [Playlist]?)
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
    /// The app started. It tries to log in again with the stored login. Before the first
    /// launch setup ends, it shows Hello (card AT) first.
    case launch
    /// The app looked for the Spotify app on this Mac: at launch, and every 3 s while the
    /// `spotifyApp` screen (card BB) shows. When it is found there, setup goes on.
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
    /// Read one playlist's tracks, through the library's memory cache, for the Playlists
    /// screen's covers. The result comes back as `.artTracksRead`.
    case readArtTracks(token: Int, playlist: String)
    /// Read Liked Songs and the playlist list in the background after a login, so that the
    /// first open is fast. Nothing comes back: the library keeps the result for the next fetch.
    case prefetch
    /// Log in through the browser; the result comes back as `.authDone` with this token.
    case logIn(token: Int)
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
/// big letter (card AG). Change 95: 6 steps within 0.4 s, so a normal quick turn does not
/// start it (it was 4 within 0.6 s).
public let fastSpinSteps = 6
public let fastSpinTime = 0.4
/// Seconds after the last wheel step before Cover Flow hides the big letter.
public let letterTime = 1.0

func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { max(lo, min(hi, v)) }

@discardableResult
public func reduce(_ s: inout AppState, _ action: Action, _ env: Dependencies) -> [Effect] {
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
            if s.pendingPlay { startLiked() } else { shuffle(s.shuffleList) }
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
    /// The next setup step after the login: the Spotify app screen if the app is missing,
    /// else the first library read, else the main menu.
    func setupNext() {
        if s.spotifyApp == false { s.stack = [Frame(screen: .spotifyApp)]; return }
        guard !s.setupDone else { s.stack = [Frame(screen: .main)]; return }
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
    /// Clasify cannot sign out the Mac's Apple account (card BM, change 263).
    func logOut() {
        signOut(); fx.append(.logOut)
        if s.service == .appleMusic { s.stack = [pickMusic()] }
    }
    /// Pick Your Music, on the active service's row (card BM, change 257).
    func pickMusic() -> Frame {
        var frame = Frame(screen: .pickMusic)
        frame.sel = MusicService.allCases.firstIndex(of: s.service) ?? 0
        return frame
    }
    /// Goes straight to the login screen, with no toast (card AX, change 181).
    func signOut() {
        stop()
        s.stack = [Frame(screen: .login)]; s.signedIn = false; s.sessionEnded = false  // the library belongs to that account
        s.library = []; s.playlistsLoaded = false; s.loadedTracks = []; s.artists = []; s.artistsLoaded = false
        s.extraTracks = []; s.trackReads = []; s.readAt = [:]; s.refreshing = []; s.artReads = [:]
        s.coverFlowAlbum = nil; s.letterUntil = 0; s.coverFlowSteps = []
        s.toast = ""; s.toastUntil = 0  // an older toast must not cover the login words
        s.hint = nil; s.hintAt = 0; s.hintTip = false; s.heldToast = ""  // nor a toast that waited for a hint
        s.tourRestAt = now  // the tour queue stays for the next login (card BA.2)
        s.pendingService = nil
    }
    /// Card BM, change 260: leaving Settings with another service. The old one stops, its
    /// library leaves, and the new one logs in with its stored login: its main menu opens at
    /// the top, with nothing playing. With no stored login, its login screen shows (256).
    func switchService(to service: MusicService) {
        signOut()
        s.service = service
        fx.append(.setService(service))
        s.authAttempt += 1; s.restoring = true
        fx.append(.restoreSession(token: s.authAttempt))
    }
    /// Plays the list in shuffle, from a random song.
    func shuffle(_ list: String) {
        let songs = s.tracks(in: list)
        guard !songs.isEmpty else { return }
        s.shuffle = true  // before play, so the engine gets shuffle on with the load
        play(list, songs[env.random(songs.count)].id)
    }
    func playLikedInOrder() {
        guard let first = s.tracks(in: Playlist.likedSongsID).first else { return }  // no songs: nothing to do
        play(Playlist.likedSongsID, first.id)
    }
    /// Liked Songs as the Shuffle setting says now: a random start in shuffle, or the first song.
    func startLiked() {
        if s.shuffle { shuffle(Playlist.likedSongsID) } else { playLikedInOrder() }
    }
    /// Play with nothing to resume (CLA-61): Liked Songs, as the Shuffle setting says. Shuffle
    /// on starts at a random song, as Shuffle Songs does. Liked Songs that is not read yet
    /// loads first, as for Shuffle Songs.
    func playLiked() {
        if s.offline { return toast(offlineStart) }
        // While a list loads, open nothing more, so no frame is left loading under another.
        if s.top.loading {
            // Liked Songs that loads starts when it is read. A start already pending stays as it is.
            guard s.top.screen == .tracks(playlist: Playlist.likedSongsID), s.shuffleToken != s.top.token else { return }
            s.shuffleToken = s.top.token; s.pendingPlay = true
            return
        }
        s.pendingPlay = true
        if s.loadedTracks.contains(Playlist.likedSongsID) {
            startLiked()
        } else {
            open(.tracks(playlist: Playlist.likedSongsID)); s.shuffleToken = s.tok
        }
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
            s.stack.append(Frame(screen: .betaSoon))
        }
    }
    func apply() {
        // Change 234: the ended beta takes only the wheel and its rows.
        if s.top.screen == .betaEnded {
            switch action {
            case .wheel, .select, .tick, .batteryChanged, .betaBuild: break
            default: return
            }
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
            // On a list, quick steps move more rows. On Now Playing, a step stays one step.
            let sel = clamp(s.top.sel + d * s.wheelSpeed.rows(at: now), 0, n - 1)
            s.top.off = clamp(s.top.off, sel - s.shownRows + 1, sel)
            s.top.sel = sel
            s.scrollUntil = now + scrollBarTime

        case .select:
            if s.top.screen == .about {
                // Change 210: a press wakes the capybara, or near the top makes it wave. From
                // step 3 it opens Licenses (change 213, a later PR).
                let pose = s.aboutPose(at: now)
                if pose.pose == .sleep {
                    s.aboutWaveAt = now
                } else if s.top.off >= AppState.aboutLicensesStep {
                    // Change 213: the Licenses list. The pose waits as it is until About shows again.
                    // A press while it waves leaves it standing, as the wave's end would.
                    s.aboutIdleHold = pose.pose == .wave ? AboutPoseNow(pose: .stand, since: now, from: .wave, cut: true) : pose
                    s.stack.append(Frame(screen: .licenses))
                } else if pose.pose != .wave {
                    s.aboutWaveAt = now
                }
                return
            }
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
            switch rows[s.top.sel] {
            case .logIn:
                s.authAttempt += 1
                s.stack.append(Frame(screen: .auth, token: s.authAttempt))
                fx.append(.logIn(token: s.authAttempt))
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
                fx.append(.logIn(token: s.authAttempt))
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
            case .shuffleSongs:
                if s.offline { return toast(offlineStart) }
                s.pendingPlay = false
                if s.loadedTracks.contains(s.shuffleList) {
                    shuffle(s.shuffleList)
                } else {  // not read yet: load, then shuffle
                    open(.tracks(playlist: s.shuffleList)); s.shuffleToken = s.tok
                }
            case .settings: s.stack.append(Frame(screen: .settings)); s.pendingService = nil
            case .playlist(let id): open(.tracks(playlist: id))
            case .track(let id):
                if s.offline { return toast(offlineStart) }
                if let list = s.top.screen.songList { play(list, id) }
            case .service: s.pendingService = (s.pendingService ?? s.service).other  // applied when Settings closes
            case .shuffle: toggleShuffle()
            case .repeatMode: setRepeat(s.repeatMode.next)
            case .skin: s.skin = s.skin.next  // not in the Settings rows until Dark and Aqua exist
            case .albumArt: s.albumArt = s.albumArt.next
            case .deviceColor: s.deviceColor = s.deviceColor.next
            case .clicker: s.clicker.toggle()
            case .nowPlayingBar: s.nowPlayingBar.toggle()
            case .color(let color):  // card AW: a press saves the color, then the music pick (card BM, 257)
                s.deviceColor = color
                if s.signedIn { setupNext() } else { s.stack.append(pickMusic()) }
            case .pickService(let service):
                if service != s.service { s.service = service; fx.append(.setService(service)) }
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
                    fx.append(.logIn(token: s.authAttempt))
                }
            case .openPrivacy: fx.append(.openPrivacy)
            case .getNewBeta:  // the warning closes; the ended screen stays
                fx.append(.getNewBeta)
                if s.top.screen == .betaSoon { s.stack.removeLast() }
            case .later: s.stack.removeLast()
            case .quit: fx.append(.quit)
            case .useSpotify: switchService(to: .spotify)  // change 262
            case .about:
                // Card BF: it opens at the top. The scroll bar shows from 0.3 s for 1.5 s.
                s.stack.append(Frame(screen: .about))
                s.aboutAt = now; s.scrollUntil = now + 0.3 + scrollBarTime
                s.aboutWaveAt = now + AppState.aboutWaveDelay; s.aboutIdleAt = 0  // change 210: it waves hello
            case .license(let i): s.stack.append(Frame(screen: .license(i)))  // change 213: its text
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
            // Change 213: back from Licenses, the idle clock starts again from the pose it left.
            if s.top.screen == .about { s.aboutIdleAt = now }
            // Card BA, change 151: the first MENU press back toward the main menu ends the MENU
            // hint for good, also before it shows.
            if s.setupDone && s.stack.first?.screen == .main { s.hintsDone.insert(.menu) }

        case .toggleShuffle: toggleShuffle()
        case .cycleRepeat: setRepeat(s.repeatMode.next)

        case .play:
            if s.setupDone { s.hintsDone.insert(.playPause) }  // card BA, change 176: any press ends that hint
            // The tour's Play starts Liked Songs on Now Playing, also when Spotify already had a
            // song when Clasify started (change 199).
            if s.tour == .tourPlay && s.top.screen == .main { return playLiked() }
            guard s.current != nil else {
                // CLA-61: nothing to resume, so Liked Songs plays. Only on the main screens:
                // never during setup, at login, or on the Spotify App screen.
                guard s.signedIn, s.stack.first?.screen == .main, s.top.screen != .spotifyApp else { return }
                return playLiked()
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
            }
            finishLoad(token, ok: artists != nil)

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
            guard s.top.loading, s.top.token == token else { return }  // stale load
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
            s.authAttempt += 1; s.restoring = true
            fx.append(.restoreSession(token: s.authAttempt))

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
            } else if !found && s.signedIn && s.setupDone {
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
            guard ok else { return }
            s.signedIn = true; fx.append(.prefetch)
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
                guard s.signedIn else { return }
            }
            s.restoring = false
            s.authAttempt += 1  // a late result of this login is stale
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
            if !ok { s.stack[s.stack.count - 1] = Frame(screen: .loginFailed); return }
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
            s.beta = beta
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
    let wasOverPanel = s.nowOverPanel
    let wasSignedIn = s.signedIn
    let rowBefore = s.halfRow
    let wasOffline = s.offline
    let artBefore = (s.artRow, s.library, s.current, s.loadedTracks, s.extraTracks)  // copies share storage, so this is cheap
    apply()
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
        // The list that the covers come from: the selected playlist, or `albumsList` for the main
        // menu's rows (see `refreshArt`), which nothing else reads at first open.
        let artList: String? = switch s.artRow {
        case .playlist(let id)?: id
        case .nowPlaying?, nil: nil
        default: s.top.screen == .main ? s.albumsList : nil  // Playlists picks a playlist soon
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
        guard s.tourOn else { return }
        switch action {
        case .play: s.hintsDone.insert(.tourPlay)
        case .next, .prev: s.hintsDone.insert(.tourNext)
        case .menu where s.stack.count < before.0: s.hintsDone.insert(.tourMenu)  // MENU that went back
        default: break
        }
        if s.isPlaying { s.hintsDone.insert(.tourPlay) }  // the music started another way
        switch action {
        case .wheel, .select, .menu, .play, .next, .prev, .toggleShuffle, .cycleRepeat:
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
        s.hint = shown; s.hintAt = now; s.hintTip = shown != .tourPlay
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
            case .menu: return s.stack.count > 1 && s.top.screen.isList && !s.top.loading && !s.top.error && s.top.screen != .betaSoon
            // On Now Playing, only while a song plays and that row shows the time bar: the tip
            // takes its place, and the volume bar, a scrub or a setting needs that row.
            case .playPause: return playing()
            case .next: return playing() && s.hintsDone.contains(.playPause) && s.navSeq != s.hintPlaySeq
            case .tourPlay, .tourNext, .tourMenu: return false  // see `tour()`
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
