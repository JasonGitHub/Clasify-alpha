import Observation

/// Playback engine (the Spotify desktop app, controlled through Spotify Connect, in 1.0). Code above it doesn't know which engine is playing.
/// The engine reports `.position`, `.trackEnded`, `.trackChanged`, `.adopted`, `.playbackFailed` and `.loadFailed` back to the store,
/// each with the generation of the newest `load`, `seek`, `next` or `prev`.
/// It reports only the state of its own device and context, so playback that the user moves elsewhere is not followed.
@MainActor
public protocol Player: AnyObject {
    /// Report `.position` and `.trackEnded` for this load with the same `generation`.
    /// `context` is the playlist ID (a Spotify URI, or `Playlist.likedSongsID`), or nil.
    func load(trackID: String, context: String?, autoplay: Bool, generation: Int)
    func pause()
    func resume()
    func stop()
    /// Skip within the playing context. Report the new track with `.trackChanged` and this `generation`.
    func next(generation: Int)
    func prev(generation: Int)
    /// The engine keeps the newest value and applies it to its own device before it plays.
    /// It may skip a value that it already applied, and it never changes another device.
    func setShuffle(_ on: Bool)
    func setRepeat(_ mode: RepeatMode)
    /// Report later `.position` and `.trackEnded` with this `generation`.
    func seek(to seconds: Double, generation: Int)
    func setVolume(_ percent: Int)
    /// CLA-168: this engine's service is the active one (true) or not. `ServicePlayer` calls it
    /// at start and on each switch. An engine may then report `.volumeReported`.
    func setActive(_ on: Bool)
    /// CLA-189: myPod quits normally while this engine's service is active. Only the Spotify
    /// engine does something here; the default does nothing.
    func quit()
}

extension Player {
    public func setActive(_ on: Bool) {}
    public func quit() {}
}

/// Card BV (CLA-125): where the newest beta's build number comes from. The app reads one small
/// file on getmypod.app; tests use a fake. It never touches the music services.
public protocol BetaFeed: Sendable {
    /// The newest beta's build number, or nil: offline, no answer in time, or a bad file.
    func latestBuild() async -> Int?
}

/// CLA-128: the activation server. A later PR makes it real; tests use a fake. Each call
/// answers with where the activation stands, `.offline` when the server does not answer.
public protocol Activator: Sendable {
    /// Where does it stand: no mail yet, mail out, or the link clicked? A failure: no usable answer (CLA-180).
    func status() async -> Result<Activation, ConnectionFailure>
    /// Send the mail again, to the same address (card BW, "Send again").
    func sendAgain() async -> Result<Activation, ConnectionFailure>
    /// The page to open, with a new one-time code (getmypod.app/activate/?d=CODE).
    func pageURL() async -> Result<String, ConnectionFailure>
}

/// How a login ended.
public enum LoginResult: Equatable, Sendable {
    case ok, failed
    /// The login worked, but the account is not Spotify Premium, so it ended (CLA-66). On
    /// Apple Music: there is no subscription (card BM, change 259).
    case notPremium
    /// The user did not allow access to the library (Apple Music, card BM, change 258).
    case denied
}

/// Spotify login and library source (playlists and Liked Songs).
/// It reads each part only when asked, and keeps what it read in memory for the session.
@MainActor
public protocol Library: AnyObject {
    /// The user's playlists in order, with names and track counts but no tracks.
    /// Returns nil when the read fails.
    func playlists() async -> [Playlist]?
    /// The tracks of one playlist, or of Liked Songs for `Playlist.likedSongsID`.
    /// Returns nil when the read fails.
    func tracks(of playlist: String) async -> [Track]?
    /// The playlist list or one playlist's tracks, read again past any cached read.
    /// Returns nil when the read fails.
    func rereadPlaylists() async -> [Playlist]?
    func reread(_ playlist: String) async -> [Track]?
    /// The details of one track ("spotify:track:<id>"). Returns nil when the read fails.
    func track(_ id: String) async -> Track?
    /// Reads Liked Songs and the playlist list in the background, at most two reads at a time,
    /// so that a later `playlists()` or `tracks(of:)` can answer at once. CLA-194: answers the
    /// size of what it read, for `app_speed` (no extra read).
    func prefetch() async -> LibraryCount
    /// Logs in through the browser: `.failed` when the user cancels or the login fails.
    /// `page` is nil, or the activate page that the login page then opens in the same tab
    /// (CLA-143, Spotify only).
    func logIn(page: String?) async -> LoginResult
    /// Stops a login that waits for the browser.
    func cancelLogIn() async
    /// Logs in again with the stored login: `.failed` when there is none or it fails.
    func restoreSession() async -> LoginResult
    /// Forgets the stored login and ends the session.
    func logOut()
    /// CLA-190: the engine's error number of the newest failed read of `key` (a playlist ID,
    /// or "" for the playlist list), for `use_error`. nil when it is not known.
    func failureStatus(of key: String) -> Int?
    /// Called on the main actor while a track read runs: how many of the list's items have
    /// their details, and how many there are. The store sets it.
    var onProgress: (@MainActor (_ playlist: String, _ done: Int, _ total: Int, _ albums: Int) -> Void)? { get set }
    /// The words that name this service's library on screen, such as "Liked Songs".
    var words: LibraryWords { get }
    /// The library's artists, as lists with no tracks: their IDs (`Playlist.isArtistID`) and
    /// names (card BN). `tracks(of:)` reads an artist's songs. nil when the read fails.
    func artists() async -> [Playlist]?
    /// The artists, read again past any cached read (CLA-179, On This Mac). nil when it fails.
    func rereadArtists() async -> [Playlist]?
}

extension Library {
    public var words: LibraryWords { .spotify }
    public func artists() async -> [Playlist]? { [] }
    public func rereadArtists() async -> [Playlist]? { await artists() }
    public func failureStatus(of key: String) -> Int? { nil }
}

/// CLA-194, `app_speed`: how many playlists and songs the start's prefetch read, each nil when
/// its read failed. `songs` counts `LibraryWords.albumsList`: liked songs on Spotify, the
/// library's songs on Apple Music and On This Mac. Hidden lists (`Playlist.isHidden`) do not
/// count, as in `AppState.librarySize`. Counts only.
public struct LibraryCount: Equatable, Sendable {
    public var playlists: Int?, songs: Int?
    public init(playlists: [Playlist]?, songs: [Track]?) {
        self.playlists = playlists.map { $0.filter { !Playlist.isHidden($0.id) }.count }
        self.songs = songs?.count
    }
}

/// The words that name a service's library on screen. The `Library` gives them, so the
/// reducer, the menus and the skins never pick text by service (CLA-103).
public struct LibraryWords: Equatable, Sendable {
    /// The liked list, such as "Liked Songs".
    public var likedSongs: String
    /// The service, as in "Can’t reach Spotify".
    public var service: String
    /// How the user adds a song to the liked list, as in "Like songs in Spotify".
    public var like: String
    /// The screen when the account cannot play: its headline, its line, the row that opens
    /// the plan's page, and the small device's word (card AX screen 135, card BM change 259).
    public var needPlan: String, needPlanLine: String, getPlan: String, noPlan: String
    /// The list that Albums and Cover Flow group into albums: Liked Songs on Spotify, the
    /// songs of the library's albums (`Playlist.libraryID`) on Apple Music, as on an iPod.
    public var albumsList: String
    /// The setup count's noun for `albumsList`'s songs, one and many: "liked song(s)" on
    /// Spotify, "song(s)" on Apple Music, which counts the songs of the library's albums.
    public var oneSong: String, manySongs: String
    /// The main menu has Artists and Songs, and Playlists starts with the liked list, as on an
    /// iPod (card BN). On for Apple Music only.
    public var libraryRows: Bool

    public init(
        likedSongs: String, service: String, like: String,
        needPlan: String, needPlanLine: String, getPlan: String, noPlan: String,
        albumsList: String = Playlist.likedSongsID, oneSong: String = "liked song", manySongs: String = "liked songs",
        libraryRows: Bool = false
    ) {
        self.likedSongs = likedSongs; self.service = service; self.like = like
        self.needPlan = needPlan; self.needPlanLine = needPlanLine; self.getPlan = getPlan; self.noPlan = noPlan
        self.albumsList = albumsList; self.oneSong = oneSong; self.manySongs = manySongs
        self.libraryRows = libraryRows
    }

    public static let spotify = LibraryWords(
        likedSongs: "Liked Songs", service: "Spotify", like: "Like",
        needPlan: "Premium needed", needPlanLine: "To play music, we need Spotify Premium.",
        getPlan: "Get Premium", noPlan: "No Premium")
    public static let appleMusic = LibraryWords(
        likedSongs: "Favorite Songs", service: "Apple Music", like: "Favorite",
        needPlan: "Not subscribed", needPlanLine: "To play music, we need Apple Music.",
        getPlan: "Get Apple Music", noPlan: "No plan",
        albumsList: Playlist.libraryID, oneSong: "song", manySongs: "songs", libraryRows: true)
}

/// Holds all app state. Only `send` changes it, and only through `reduce`.
@MainActor @Observable
public final class Store {
    public private(set) var state: AppState
    @ObservationIgnored private let player: any Player
    @ObservationIgnored private let library: any Library
    @ObservationIgnored private let env: Dependencies
    @ObservationIgnored private var fetches: [Int: Task<Void, Never>] = [:]  // in flight, by token
    /// Counts service switches. A background read with no token that ends after a switch is
    /// dropped, so the old service's lists never show on the new one (CLA-103).
    @ObservationIgnored private var serviceGen = 0
    /// Called after each `.wheel` step that moved something (see `wheelMoved`). The app clicks
    /// and ticks the trackpad here.
    @ObservationIgnored public var onWheelStep: (@MainActor () -> Void)?
    /// Opens the Spotify app's download page in the browser (card BB). The app sets it.
    @ObservationIgnored public var onGetSpotifyApp: (@MainActor () -> Void)?
    /// Opens Spotify's Premium page in the browser (card AX, screen 135). The app sets it.
    @ObservationIgnored public var onGetPremium: (@MainActor () -> Void)?
    /// Opens the Mac's privacy settings for Apple Music (card BM, change 258). The app sets it.
    @ObservationIgnored public var onOpenPrivacy: (@MainActor () -> Void)?
    /// Card CX: opens a new mail to feedback@getmypod.app. The phone app sets it; it sends
    /// `.mailFailed` when no mail can open.
    @ObservationIgnored public var onOpenMail: (@MainActor () -> Void)?
    /// Makes `service` the active one in the player and the library, before any later effect
    /// runs (CLA-103). The app sets it. Then the state gets the library's words.
    @ObservationIgnored public var onSetService: (@MainActor (MusicService) -> Void)?
    /// Opens the beta download page, and quits the app (card BI v2). The app sets them.
    @ObservationIgnored public var onGetNewBeta: (@MainActor () -> Void)?
    @ObservationIgnored public var onQuit: (@MainActor () -> Void)?
    /// Card AN.1 (CLA-43): fade the device window in or out. The app sets them.
    @ObservationIgnored public var onShowWindow: (@MainActor () -> Void)?
    @ObservationIgnored public var onHideWindow: (@MainActor () -> Void)?
    /// CLA-97: the beta analytics sender. The app sets it (A3); nil sends nothing.
    @ObservationIgnored public var onBetaEvent: (@MainActor (BetaEvent) -> Void)?
    /// Card BW: opens the activator's page URL (getmypod.app/activate/?d=CODE) in the browser. The app sets it.
    @ObservationIgnored public var onOpenActivatePage: (@MainActor (String) -> Void)?
    /// CLA-203: the last 2 minutes of facts, in memory only, for the problem events.
    @ObservationIgnored public let timeline = Timeline()
    /// CLA-203: the events with a timeline in this launch (`problem_after` too), and the
    /// `song_cut` events. Caps for launch scale.
    @ObservationIgnored private var timelinesSent = 0
    @ObservationIgnored private var cutsSent = 0
    static let timelineCap = 10, cutCap = 3
    /// CLA-203: the problem that waits for its `problem_after`: its name, when it came, whether
    /// control came back since. One at a time.
    @ObservationIgnored private var after: (problem: String, at: Double, back: Bool)?
    /// Where the settings are saved. When set, `init` loads them into the state.
    @ObservationIgnored private let settingsStore: (any SettingsStore)?
    /// Card BV: the launch check's source. With none, the check finds nothing.
    @ObservationIgnored private let betaFeed: (any BetaFeed)?
    /// CLA-128: the activation server. With none, the requests get no answer.
    @ObservationIgnored private let activator: (any Activator)?

    public init(
        player: any Player, library: any Library, state: AppState = AppState(), env: Dependencies = .live,
        settings: (any SettingsStore)? = nil, betaFeed: (any BetaFeed)? = nil, activator: (any Activator)? = nil,
        platform: Platform = .mac
    ) {
        self.player = player; self.library = library; self.state = state; self.env = env
        settingsStore = settings
        self.betaFeed = betaFeed
        self.activator = activator
        self.state.platform = platform  // CLA-202
        self.state.words = library.words
        library.onProgress = { [weak self] playlist, done, total, albums in
            self?.send(.readProgress(playlist, done: done, total: total, albums: albums))
        }
        if let settings {
            self.state.settings = Settings(from: settings)
            // The player keeps its own shuffle and repeat for when it takes over playback later.
            player.setShuffle(self.state.shuffle)
            player.setRepeat(self.state.repeatMode)
        }
        // CLA-202: a saved service that this platform does not have reads as its first one.
        if !self.state.features.services.contains(self.state.service) { self.state.service = self.state.features.services[0] }
    }

    /// CLA-203: sends an event; a problem gets the 2 minutes before it, within the caps, and
    /// starts its `problem_after`. Over the cap a problem goes out as before, with no timeline;
    /// a `song_cut` over its cap does not go out.
    func track(_ event: BetaEvent, before: AppState, at now: Double, stateSeconds: Int? = nil) {
        guard event.isProblem else { onBetaEvent?(event); return }
        if case .songCut = event {
            guard cutsSent < Self.cutCap else { return }
            cutsSent += 1
        }
        guard timelinesSent < Self.timelineCap else { onBetaEvent?(event); return }
        timelinesSent += 1
        var pos: Int?, len: Int?
        if let current = before.current {
            pos = Int(before.t.rounded(.down))
            if let length = before.track(current)?.duration, length > 0 { len = Int(length.rounded()) }
        }
        let context = ProblemContext(timeline: timeline.text(at: now), pos: pos, len: len,
                                     playing: before.isPlaying, screen: before.top.screen.eventName,
                                     stateSeconds: stateSeconds)
        onBetaEvent?(.problem(event, context))
        if after == nil, timelinesSent < Self.timelineCap {  // its `problem_after` needs a place under the cap
            timelinesSent += 1
            after = (event.problemName, now, false)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(Timeline.span))
                guard let self else { return }
                self.finishAfter(at: self.env.now(), quit: false)
            }
        }
    }

    /// CLA-203: `problem_after` for the waiting problem, 2 minutes after it or at the quit.
    private func finishAfter(at now: Double, quit: Bool) {
        guard let after, quit || now - after.at >= Timeline.span else { return }
        self.after = nil
        onBetaEvent?(.problemAfter(problem: after.problem, timeline: timeline.text(since: after.at, at: now), quit: quit,
                                   back: after.back, playing: state.isPlaying, service: state.service))
    }

    /// Waits for in-flight library fetches to deliver their results. For tests.
    func settle() async {
        while let task = fetches.values.first { await task.value }
    }

    /// An activation server answer as an action. No usable answer is `.offline`, with why (CLA-180).
    private static func answer(_ answer: Result<Activation, ConnectionFailure>, request: Int?) -> Action {
        switch answer {
        case .success(let activation): .activation(activation, request: request)
        case .failure(let failure): .activation(.offline, request: request, failure: failure)
        }
    }

    /// CLA-128: at launch, the stored activation of this Mac. The answer comes
    /// with no request number, so it is dropped here when a newer request started meanwhile.
    public func checkActivationAtLaunch() {
        guard let activator, state.features.activation else { return }  // CLA-202: no activation on the phone
        let request = state.activateRequest
        Task { [weak self] in
            let answer = await activator.status()
            guard let self, self.state.activateRequest == request else { return }
            self.send(Store.answer(answer, request: nil))
        }
    }

    /// A browser login. CLA-143: `activating` asks for the activate page first, for at most
    /// `pageWait` seconds. On time, the login page takes the tab on to it; late, no answer or
    /// an error, the login goes on without it, as before.
    private func logIn(_ token: Int, activating: Bool) {
        let library = self.library, activator = activating ? self.activator : nil
        Task { [weak self] in
            var page: String?
            if let activator {
                page = await Self.within(Self.pageWait) { try? await activator.pageURL().get() }  // a failure: the login goes on
                // MENU, Cancel or a newer login came while it waited: this login must not start
                // (Codex on #330).
                guard let state = self?.state, state.top.screen == .auth, state.top.token == token else { return }
                if page != nil { self?.send(.loginCarriesActivate(token: token)) }
            }
            let result = await library.logIn(page: page)
            switch result {
            case .notPremium: self?.send(.notPremium(token: token))
            case .denied: self?.send(.accessDenied(token: token))
            case .ok, .failed: self?.send(.authDone(token: token, ok: result == .ok))
            }
        }
    }
    static let pageWait = 2.0

    /// The answer of `work`, or nil when it takes longer than `seconds`.
    static func within(_ seconds: Double, _ work: @escaping @Sendable () async -> String?) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask { await work() }
            group.addTask { try? await Task.sleep(for: .seconds(seconds)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    public func send(_ action: Action) {
        let before = state
        let effects = reduce(&state, action, env)
        let now = env.now()
        // How long the state before this action held: read before the action changes it.
        let stateSeconds = timeline.stateSeconds(at: now)
        timeline.record(action, from: before, to: state, at: now)
        if case .controlBack = action { after?.back = true }
        if case .willQuit = action { finishAfter(at: now, quit: true) } else { finishAfter(at: now, quit: false) }
        if let settingsStore, state.settings != before.settings { state.settings.save(to: settingsStore) }
        if case .wheel = action, wheelMoved(from: before, to: state) { onWheelStep?() }
        for effect in effects {
            switch effect {
            case .load(let id, let context, let autoplay, let gen):
                player.load(trackID: id, context: context, autoplay: autoplay, generation: gen)
            case .pause: player.pause()
            case .resume: player.resume()
            case .stop: player.stop()
            case .quitPlayer: player.quit()
            case .next(let gen): player.next(generation: gen)
            case .prev(let gen): player.prev(generation: gen)
            case .setShuffle(let on): player.setShuffle(on)
            case .setRepeat(let mode): player.setRepeat(mode)
            case .seek(let t, let gen): player.seek(to: t, generation: gen)
            case .setVolume(let v): player.setVolume(v)
            // A stale token is ignored by the reducer.
            case .fetchPlaylists(let token):
                let library = self.library
                fetches[token] = Task { [weak self] in
                    let result = await library.playlists()
                    self?.fetches[token] = nil
                    if result == nil { self?.send(.readFailed(token: token, status: library.failureStatus(of: ""))) }
                    self?.send(.playlistsLoaded(token: token, playlists: result))
                }
            case .fetchArtists(let token):
                let library = self.library
                fetches[token] = Task { [weak self] in
                    let result = await library.artists()
                    self?.fetches[token] = nil
                    if result == nil { self?.send(.readFailed(token: token, status: library.failureStatus(of: AppState.artistsKey))) }
                    self?.send(.artistsLoaded(token: token, artists: result))
                }
            case .fetchTracks(let token, let id):
                let library = self.library
                fetches[token] = Task { [weak self] in
                    let result = await library.tracks(of: id)
                    self?.fetches[token] = nil
                    if result == nil { self?.send(.readFailed(token: token, status: library.failureStatus(of: id))) }
                    self?.send(.tracksLoaded(token: token, playlist: id, tracks: result))
                }
            case .refreshPlaylists:
                let (library, gen) = (self.library, serviceGen)
                Task(priority: .utility) { [weak self] in
                    let result = await library.rereadPlaylists()
                    guard let self, self.serviceGen == gen else { return }
                    self.send(.playlistsRefreshed(result))
                }
            case .refreshTracks(let id):
                let (library, gen) = (self.library, serviceGen)
                Task(priority: .utility) { [weak self] in
                    let result = await library.reread(id)
                    guard let self, self.serviceGen == gen else { return }
                    self.send(.tracksRefreshed(playlist: id, tracks: result))
                }
            case .refreshArtists:
                let (library, gen) = (self.library, serviceGen)
                Task(priority: .utility) { [weak self] in
                    let result = await library.rereadArtists()
                    guard let self, self.serviceGen == gen else { return }
                    self.send(.artistsRefreshed(result))
                }
            case .readArtTracks(let token, let id):
                let library = self.library
                Task(priority: .utility) { [weak self] in
                    let result = await library.tracks(of: id)
                    self?.send(.artTracksRead(token: token, playlist: id, tracks: result))
                }
            case .readTrack(let id):
                let (library, gen) = (self.library, serviceGen)
                Task { [weak self] in
                    let track = await library.track(id)
                    guard let self, self.serviceGen == gen else { return }
                    self.send(.trackRead(id, track))
                }
            case .prefetch:
                let library = self.library, gen = serviceGen
                Task(priority: .utility) { [weak self] in
                    let count = await library.prefetch()
                    guard let self, self.serviceGen == gen else { return }  // another service's count
                    self.send(.libraryCounted(count))
                }
            case .logIn(let token): logIn(token, activating: false)
            case .logInActivating(let token): logIn(token, activating: true)
            case .getSpotifyApp: onGetSpotifyApp?()
            case .getPremium: onGetPremium?()
            case .openPrivacy: onOpenPrivacy?()
            case .openMail: onOpenMail?()
            case .getNewBeta: onGetNewBeta?()
            case .quit: onQuit?()
            case .showWindow: onShowWindow?()
            case .hideWindow: onHideWindow?()
            case .track(let event): track(event, before: before, at: now, stateSeconds: stateSeconds)
            case .openActivatePage(let request):
                guard let activator else { break }
                let flow = state.activateFlow
                Task { [weak self] in
                    let url = await activator.pageURL()
                    guard let self, self.state.activateFlow == flow else { return }  // Cancel or MENU came first
                    switch url {
                    case .success(let url): self.onOpenActivatePage?(url)
                    case .failure(let failure): self.send(.activation(.offline, request: request, failure: failure))
                    }
                }
            case .sendActivationAgain(let request):
                guard let activator else { break }
                Task { [weak self] in
                    let answer = await activator.sendAgain()
                    self?.send(Store.answer(answer, request: request))
                }
            case .checkActivation(let request):
                guard let activator else { break }
                Task { [weak self] in
                    let answer = await activator.status()
                    self?.send(Store.answer(answer, request: request))
                }
            case .checkLatestBeta:
                guard let betaFeed else { break }
                Task { [weak self] in  // the read runs off the main actor; only its answer comes back
                    guard let build = await betaFeed.latestBuild() else { return }
                    self?.send(.latestBeta(build))
                }
            case .cancelLogIn:
                let library = self.library
                Task { await library.cancelLogIn() }
            case .restoreSession(let token):
                let library = self.library
                Task { [weak self] in
                    let result = await library.restoreSession()
                    switch result {
                    case .notPremium: self?.send(.notPremium(token: token))
                    case .denied: self?.send(.accessDenied(token: token))
                    case .ok, .failed: self?.send(.restored(token: token, ok: result == .ok))
                    }
                }
            case .logOut: library.logOut()
            case .setService(let service):
                serviceGen += 1
                onSetService?(service)
                send(.libraryWords(library.words))
            }
        }
    }
}
