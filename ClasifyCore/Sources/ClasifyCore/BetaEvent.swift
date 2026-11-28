import Foundation

/// CLA-97: a beta analytics event. The reducer decides it and returns it as `Effect.track`;
/// the app's sender (A3) adds the account ID (before activation, a random install ID), the build
/// and the macOS version, and sends it only from a signed beta build with a key, with `analytics.on`. No
/// email, no song or playlist names.
public enum BetaEvent: Equatable, Sendable {
    /// Each setup screen a person reaches, once in a row (`log_in` covers the login and the browser).
    /// `seconds` is nil on a Mac with no first launch time (set up before CLA-97).
    /// `color` is on the step that the press on Color sends: the color picked (CLA-97, Jason 14:23 JST 11-22).
    /// CLA-197: `all_set` also says the active service's library size, as `app_speed` does.
    case setupStep(SetupStep, seconds: Int?, service: MusicService, color: DeviceColor? = nil, playlists: Int? = nil, songs: Int? = nil)
    /// Setup stops on an error. `reason`: why our server got no answer, on `no_connection` only (CLA-180).
    case setupError(SetupError, service: MusicService, reason: ConnectionFailure? = nil)
    /// The pick on Pick Your Music: the service, the top row, and whether the Spotify app was found.
    case musicPick(MusicService, top: MusicService, spotifyApp: Bool?)
    /// Once per person: seconds from the first launch to the first song that plays.
    case firstSong(seconds: Int, service: MusicService)
    /// myPod lost control of playback, and got it back this many seconds later.
    case controlLost(ControlLoss, service: MusicService)
    case controlBack(seconds: Int, service: MusicService)
    /// A beta notice showed, or its Get New Beta was pressed. `daysLeft` of this build.
    case betaRenewal(BetaNotice, pressed: Bool, daysLeft: Int)
    /// The first start of a new build: the build before, this one, and days since it was signed.
    case appUpdated(from: Int, to: Int, days: Int)
    /// After setup: a login failed, a list did not load (`offline` when the Mac was offline), or a song did not play.
    /// CLA-190: `list` and `status` only for `list_not_loaded`: the kind of list (never its
    /// name or ID) and the engine's error number, each when known.
    case useError(UseError, offline: Bool, service: MusicService, list: String? = nil, status: Int? = nil)
    /// Once a launch after setup, at the first library read that the app took: ms from the
    /// process start to the first window (nil when the app did not say), from `.launch` to that
    /// read, and whether it worked (a failed one counts too: Jason 23:57 JST).
    /// CLA-186: the library's size as read so far, each nil until its list is read and on a
    /// failed read. `songs`: the songs of `albumsList` (on Spotify the liked songs only; on Apple
    /// Music and On This Mac the library). `playlists`: the playlists the Playlists screen shows.
    case appSpeed(startMs: Int?, libraryMs: Int, loaded: Bool, playlists: Int? = nil, songs: Int? = nil)
    /// The service changed after setup (the Settings Service row).
    case serviceSwitch(from: MusicService, to: MusicService)
    /// One day with music, a feature or a 3D view, sent on the first action of a later day.
    /// `color` is the Color setting when the day is reported (Jason 14:23 JST 11-22).
    /// `settings`: Album Art, Clicker and Menu Bar when the day is reported (Jason 13:38 JST 11-23).
    case dayActive(DayUse, service: MusicService, color: DeviceColor, settings: DaySettings = DaySettings())
    /// A crash or a hang of an earlier run (A4, MetricKit).
    case appProblem(AppProblem, service: MusicService)
    /// CLA-181: the first-run hints. `start` once, when the tour first turns on; then one event
    /// as each tour step ends, with `how` (nil on `start`). At most 6 in a person's life.
    case hintStep(HintStep, how: HintHow?, service: MusicService)
    /// CLA-186: a normal quit (not a crash or a force quit): the minutes this launch was open
    /// (nil when the app could not read it), and the kind of screen that showed (`Screen.eventName`).
    /// CLA-203: `use`, this launch's play use (`LaunchUse`).
    case appClosed(minutes: Double?, screen: String, service: MusicService, use: LaunchUse = LaunchUse())
    /// CLA-186: a first step after setup, once per install (`FirstStep`). `how` on `play_no_music`
    /// only. `seconds` from `all_set` in the setup's launch, else from this launch.
    case firstStep(FirstStep, how: NoMusic?, seconds: Int, service: MusicService)
    /// CLA-203: a song that ended by itself under `cutLimit` seconds (the one `songs_cut` counts),
    /// with how far it got and its length, whole seconds (`len` nil when not known).
    case songCut(pos: Int, len: Int?, service: MusicService)
    /// CLA-203: a problem event with what came before it (`Store` adds it, `ProblemContext`).
    indirect case problem(BetaEvent, ProblemContext)
    /// CLA-203: 2 minutes after a problem, or at the quit before that: what came after it.
    /// `problem`: its event name and kind, as "control_lost:stopped_in_spotify".
    case problemAfter(problem: String, timeline: String, quit: Bool, back: Bool, playing: Bool, service: MusicService)

    /// The event name in PostHog.
    public var name: String {
        switch self {
        case .setupStep: "setup_step"
        case .setupError: "setup_error"
        case .musicPick: "music_pick"
        case .firstSong: "first_song"
        case .controlLost: "control_lost"
        case .controlBack: "control_back"
        case .betaRenewal: "beta_renewal"
        case .appUpdated: "app_updated"
        case .dayActive: "day_active"
        case .useError: "use_error"
        case .appSpeed: "app_speed"
        case .serviceSwitch: "service_switch"
        case .appProblem: "app_problem"
        case .hintStep: "hint_step"
        case .appClosed: "app_closed"
        case .firstStep: "first_step"
        case .songCut: "song_cut"
        case .problem(let event, _): event.name
        case .problemAfter: "problem_after"
        }
    }

    /// CLA-203: the events that get the timeline: a loss of control, a song or list that did
    /// not play or load, a first Play with no music, a cut song.
    var isProblem: Bool {
        switch self {
        case .controlLost, .useError(.songNotPlayed, _, _, _, _), .useError(.listNotLoaded, _, _, _, _), .songCut: true
        case .firstStep(let step, _, _, _): step == .playNoMusic
        default: false
        }
    }

    /// CLA-203: the event without the context that the Store added.
    var plain: BetaEvent {
        if case .problem(let event, _) = self { return event }
        return self
    }

    /// CLA-203: the name and kind of a problem, for `problem_after`.
    var problemName: String {
        switch self {
        case .controlLost(let reason, _): "control_lost:" + reason.rawValue
        case .useError(let kind, _, _, _, _): "use_error:" + kind.rawValue
        case .firstStep(let step, _, _, _): "first_step:" + step.rawValue
        case .problem(let event, _): event.problemName
        default: name
        }
    }

    /// The event's own data. The sender adds the rest.
    public var properties: [String: BetaValue] {
        switch self {
        case .setupStep(let step, let seconds, let service, let color, let playlists, let songs):
            var p: [String: BetaValue] = ["step": .text(step.rawValue), "service": .text(service.eventName)]
            if let seconds { p["seconds"] = .number(seconds) }
            if let color { p["color"] = .text(color.eventName) }
            if let playlists { p["playlists"] = .number(playlists) }
            if let songs { p["songs"] = .number(songs) }
            return p
        case .setupError(let kind, let service, let reason):
            var p: [String: BetaValue] = ["kind": .text(kind.rawValue), "service": .text(service.eventName)]
            if let reason { p["reason"] = .text(reason.eventName) }
            return p
        case .musicPick(let service, let top, let spotifyApp):
            var p: [String: BetaValue] = ["service": .text(service.eventName), "top": .text(top.eventName)]
            if let spotifyApp { p["spotify_app"] = .flag(spotifyApp) }
            return p
        case .firstSong(let seconds, let service):
            return ["seconds": .number(seconds), "service": .text(service.eventName)]
        case .controlLost(let reason, let service):
            return ["reason": .text(reason.rawValue), "service": .text(service.eventName)]
        case .controlBack(let seconds, let service):
            return ["seconds": .number(seconds), "service": .text(service.eventName)]
        case .betaRenewal(let notice, let pressed, let daysLeft):
            return ["notice": .text(notice.rawValue), "pressed": .flag(pressed), "days_left": .number(daysLeft)]
        case .appUpdated(let from, let to, let days):
            return ["old_build": .number(from), "new_build": .number(to), "days": .number(days)]
        case .useError(let kind, let offline, let service, let list, let status):
            var p: [String: BetaValue] = ["kind": .text(kind.rawValue), "offline": .flag(offline), "service": .text(service.eventName)]
            if let list { p["list"] = .text(list) }
            if let status { p["status"] = .number(status) }
            return p
        case .appSpeed(let startMs, let libraryMs, let loaded, let playlists, let songs):
            var p: [String: BetaValue] = ["library_ms": .number(libraryMs), "loaded": .flag(loaded)]
            if let startMs { p["start_ms"] = .number(startMs) }
            if let playlists { p["playlists"] = .number(playlists) }
            if let songs { p["songs"] = .number(songs) }
            return p
        case .serviceSwitch(let from, let to):
            return ["from": .text(from.eventName), "to": .text(to.eventName)]
        case .hintStep(let step, let how, let service):
            var p: [String: BetaValue] = ["step": .text(step.rawValue), "service": .text(service.eventName)]
            if let how { p["how"] = .text(how.rawValue) }
            return p
        case .firstStep(let step, let how, let seconds, let service):
            var p: [String: BetaValue] = ["step": .text(step.rawValue), "seconds": .number(seconds), "service": .text(service.eventName)]
            if let how { p["how"] = .text(how.rawValue) }
            return p
        case .appClosed(let minutes, let screen, let service, let use):
            var p: [String: BetaValue] = [
                "screen": .text(screen), "service": .text(service.eventName),
                "plays": .number(use.plays), "pauses": .number(use.pauses), "skips": .number(use.skips),
                "longest_pause_s": .number(Int(use.longestPause.rounded())),
                "stops_playing": .number(use.stopsPlaying), "stops_paused": .number(use.stopsPaused),
                "outside_music_s": .number(Int(use.outsideSeconds.rounded())),
            ]
            if let minutes { p["minutes"] = .decimal(minutes) }
            return p
        case .appProblem(let problem, let service):
            return problem.properties.merging(["service": .text(service.eventName)]) { old, _ in old }
        case .songCut(let pos, let len, let service):
            var p: [String: BetaValue] = ["pos_s": .number(pos), "service": .text(service.eventName)]
            if let len { p["len_s"] = .number(len) }
            return p
        case .problem(let event, let context):
            return event.properties.merging(context.properties) { own, _ in own }  // a cut song keeps its own place
        case .problemAfter(let problem, let timeline, let quit, let back, let playing, let service):
            return ["problem": .text(problem), "timeline": .text(timeline), "quit": .flag(quit), "back": .flag(back),
                    "playing": .flag(playing), "service": .text(service.eventName)]
        case .dayActive(let d, let service, let color, let settings):
            var p: [String: BetaValue] = [
                "color": .text(color.eventName), "album_art": .text(settings.albumArt.eventName),
                "clicker": .flag(settings.clicker), "menu_bar": .flag(settings.menuBar),
                "songs_shuffle": .number(d.songsShuffle), "songs_repeat": .number(d.songsRepeat), "songs_cut": .number(d.songsCut),
                "menu_bar_clicks": .number(d.menuBarClicks),
                "outside_songs": .number(d.outsideSongs), "outside_minutes": .decimal(d.outsideSeconds / 60),  // CLA-203
                "day": .number(d.day), "weekday": .number(d.weekday), "songs": .number(d.songs), "minutes": .decimal(d.seconds / 60),
                "minutes_night": .decimal(d.bands[0] / 60), "minutes_morning": .decimal(d.bands[1] / 60),
                "minutes_work": .decimal(d.bands[2] / 60), "minutes_evening": .decimal(d.bands[3] / 60), "service": .text(service.eventName),
            ]
            for f in Feature.allCases { p["used_" + f.rawValue] = .flag(d.features.contains(f)) }
            for v in View3D.allCases { p[v.property] = .decimal(d.views[v.index]) }
            // CLA-162: where the window was. Only with visible time; no other app, no screen content.
            p["minutes_visible"] = .decimal(d.visible / 60)
            if let area = d.topArea { p["spot"] = .text(WindowSpot.areaNames[area]) }
            if let key = d.topScreen {
                let n = key.split(separator: "x").compactMap { Int($0) }
                if n.count >= 3 {
                    p["main_screen"] = .flag(n[0] == 1)
                    p["screen_width"] = .number(n[1])
                    p["screen_height"] = .number(n[2])
                }
                p["screens"] = .number(d.screenCount)
            }
            return p
        }
    }
}

/// CLA-203: what a problem event says about the moment before it. No names, no IDs.
public struct ProblemContext: Equatable, Sendable {
    /// The 2 minutes before (`Timeline.text`).
    public var timeline: String
    /// The song's place and length, whole seconds, when a song was there.
    public var pos: Int?, len: Int?
    /// Music played just before, and the kind of screen (`Screen.eventName`).
    public var playing: Bool, screen: String
    /// Whole seconds that `playing` held before the problem, with no upper limit (CTO: a stop
    /// 30 minutes after a pause). Nil when not known.
    public var stateSeconds: Int? = nil

    var properties: [String: BetaValue] {
        var p: [String: BetaValue] = ["timeline": .text(timeline), "playing": .flag(playing), "screen": .text(screen)]
        if let pos { p["pos_s"] = .number(pos) }
        if let len { p["len_s"] = .number(len) }
        if let stateSeconds { p["state_s"] = .number(stateSeconds) }
        return p
    }
}

/// A value in an event's data.
public enum BetaValue: Equatable, Sendable {
    case text(String), number(Int), flag(Bool), decimal(Double)
}

/// CLA-181: a step of the first-run hints (card BA.2, CLA-163). The old card BA hints are not one.
public enum HintStep: String, Sendable {
    case start, play, next, menu, turn, menuBar = "menu_bar"

    init?(_ hint: Hint) {
        switch hint {
        case .tourPlay: self = .play
        case .tourNext: self = .next
        case .tourMenu: self = .menu
        case .tourTurn: self = .turn
        case .tourMenuBar: self = .menuBar
        case .menu, .playPause, .next: return nil
        }
    }
}

/// CLA-181: how a hint step ended: the person did its action, or it hid `tourHideMax` times.
public enum HintHow: String, Sendable {
    case done, unused
}

extension Screen {
    /// CLA-186: the kind of screen, for `app_closed`. Never a list, song or artist name.
    var eventName: String {
        switch self {
        case .login: "login"
        case .auth: "auth"
        case .main: "main_menu"
        case .playlists: "playlists"
        case .albums: "albums"
        case .tracks: "songs"
        case .settings: "settings"
        case .confirm: "confirm"
        case .about: "about"
        case .now: "now_playing"
        case .coverFlow: "cover_flow"
        case .albumPanel: "album_panel"
        case .hello: "hello"
        case .color: "color"
        case .spotifyApp: "spotify_app"
        case .yourMusic: "your_music"
        case .loginFailed: "login_failed"
        case .loggedIn: "logged_in"
        case .premium: "premium"
        case .pickMusic: "pick_music"
        case .accessOff: "access_off"
        case .licenses: "licenses"
        case .license: "license"
        case .artists: "artists"
        case .betaSoon: "beta_soon"
        case .betaEnded: "beta_ended"
        case .betaNew: "beta_new"
        case .activate: "activate"
        case .activation: "activation"
        case .noSongs: "no_songs"
        case .search: "search"
        case .noMail: "no_mail"  // card CX: only on the phone, which sends no analytics
        }
    }
}

/// The setup steps, in order (analytics doc). `spotify_check` shows only when the Spotify app is missing.
public enum SetupStep: String, Sendable {
    case hello, color, pickMusic = "pick_music", spotifyCheck = "spotify_check", logIn = "log_in", activate
    case yourMusic = "your_music", allSet = "all_set"

    init?(_ screen: Screen) {
        switch screen {
        case .hello: self = .hello
        case .color: self = .color
        case .pickMusic: self = .pickMusic
        case .spotifyApp: self = .spotifyCheck
        case .login, .auth: self = .logIn
        case .activate: self = .activate
        case .yourMusic: self = .yourMusic
        default: return nil
        }
    }
}

/// The setup errors (analytics doc), with the 4 of activation.
public enum SetupError: String, Sendable {
    case spotifyNotFound = "spotify_not_found", premiumNeeded = "premium_needed", loginFailed = "login_failed"
    case accessOff = "apple_music_access_off", noPlan = "no_apple_music_plan"
    case mailBusy = "mail_busy", betaFull = "beta_full", accountOff = "account_off", noConnection = "no_connection"
}

extension AppState {
    /// CLA-190: the kind of list that a screen reads on the active service, for `use_error`.
    /// Never a name or an ID. Albums and Cover Flow read `albumsList`: liked songs on Spotify,
    /// the library's songs on Apple Music (Codex on #481).
    func listKind(_ screen: Screen) -> String? {
        switch screen {
        case .playlists: return "playlists"
        case .artists: return "artists"
        case .albums, .coverFlow, .yourMusic, .tracks, .albumPanel:
            let id = readKey(screen)
            if id == Playlist.likedSongsID { return "liked" }
            if id == Playlist.libraryID || id == Playlist.songsID { return "songs" }
            if Album.isID(id) { return "album" }
            if Playlist.isArtistID(id) { return "artist" }
            return "playlist"
        default: return nil
        }
    }
}

/// CLA-97: the errors of `use_error`.
public enum UseError: String, Sendable {
    case loginFailed = "login_failed", listNotLoaded = "list_not_loaded", songNotPlayed = "song_not_played"
}

/// Why myPod lost control of playback, as the player found it.
public enum ControlLoss: String, Sendable {
    case sessionDrop = "session_drop", timeout, otherDevice = "other_device", stoppedInSpotify = "stopped_in_spotify"
    case spotifyQuit = "spotify_quit", appleMusicError = "apple_music_error"
}

/// The beta notices (cards BV and BI v2): a newer build, the day-27 warning, the end.
public enum BetaNotice: String, Sendable {
    case update, warning, end

    init?(_ screen: Screen) {
        switch screen {
        case .betaNew: self = .update
        case .betaSoon: self = .warning
        case .betaEnded: self = .end
        default: return nil
        }
    }
}

extension Settings {
    /// The Settings rows a person changes, for the Settings flag of `day_active`.
    var choices: [String] {
        [String(shuffle), repeatMode.rawValue, albumArt.rawValue, deviceColor.rawValue, String(clicker),
         String(nowPlayingBar), String(menuBar), service.rawValue]
    }
}

/// The settings that `day_active` says, as they are when the day is reported.
public struct DaySettings: Equatable, Sendable {
    public var albumArt = AlbumArt.all, clicker = true, menuBar = true
    public init(albumArt: AlbumArt = .all, clicker: Bool = true, menuBar: Bool = true) {
        (self.albumArt, self.clicker, self.menuBar) = (albumArt, clicker, menuBar)
    }
}

extension AlbumArt {
    /// `all`, `now_playing` or `off`, as the events name it.
    public var eventName: String { rawValue.lowercased().replacingOccurrences(of: " ", with: "_") }
}

extension DeviceColor {
    /// `silver` or `black`, as the events name it.
    public var eventName: String { rawValue.lowercased() }
}

extension MusicService {
    /// `spotify`, `apple_music` or `local`, as the events name it.
    public var eventName: String {
        switch self {
        case .spotify: "spotify"
        case .appleMusic: "apple_music"
        case .local: "local"
        }
    }
}

/// What `betaEvents` compares: the state before an action.
struct BeforeEvents {
    var screen: Screen, setupDone: Bool, activateStep: ActivateStep
    /// The build that `.betaBuild` reads, for `app_updated`.
    var build: BetaBuild?
    /// The service row that a press on Pick Your Music picks in setup, and that screen's top row.
    var pick: MusicService?, top: MusicService
    /// The action is the engine's report of a position past 0 for the playing load: a
    /// confirmed play, not a scrub or the optimistic Play.
    var played = false, position = 0.0
    /// Music played before the action, for the save of the day at a pause.
    var playing: Bool
    /// For `use_error` and `service_switch`: the screen showed an error, the service, and the
    /// action is a failed load of the playing song.
    var error: Bool, service: MusicService, songFailed = false
    /// The action brings a library read, and the read times before it, for `app_speed`: the
    /// reducer marks each read that it took (Codex on #350: not a stale or unasked one).
    var libraryRead = false, readAt: [String: Double], artists: Bool
    /// The reads in flight before: a failed read that the app took ends one of them.
    var loading: Bool, refreshes: Int, coverReads: Int
    /// The settings before, for the Settings flag of `day_active`, and a skin feature (`.used`).
    var choices: [String], used: Feature?
    /// The action is the press on a color on the Color screen in setup.
    var colorPress = false
    /// CLA-181: the tour and its ended steps before.
    var tourOn: Bool, hintsDone: Set<Hint>
    /// CLA-186: the load generation before, for `songs_cut`.
    var gen: Int
    /// CLA-194: the action is the quit, which sends an `app_speed` that still waits.
    var quit = false
    /// CLA-203: a loss of control was open before, so a new `.controlLost` was not counted.
    var lossOpen: Bool

    init(_ s: AppState, _ action: Action) {
        (screen, setupDone, activateStep) = (s.top.screen, s.setupDone, s.activateStep)
        choices = s.settings.choices
        (tourOn, hintsDone) = (s.tourOn, s.hintsDone)
        playing = s.isPlaying
        lossOpen = s.controlLostAt != nil
        gen = s.playGen
        (error, service) = (s.top.error, s.service)
        (readAt, artists) = (s.readAt, s.artistsLoaded)
        (loading, refreshes, coverReads) = (s.top.loading, s.refreshing.count, s.artReads.count)
        if case .loadFailed(_, let gen) = action, gen == s.playGen, s.current != nil { songFailed = true }
        if case .used(let feature) = action { used = feature }
        top = s.appleMusicFirst ? .appleMusic : .spotify
        pick = nil
        if case .position(let t, let gen) = action, t > 0, gen == s.playGen { (played, position) = (true, t) }
        if case .betaBuild(let b) = action { build = b }
        if case .willQuit = action { quit = true }
        switch action {
        case .playlistsLoaded, .tracksLoaded, .playlistsRefreshed, .tracksRefreshed, .artTracksRead, .artistsLoaded: libraryRead = true
        default: break
        }
        if action == .select && !s.setupDone && screen == .color {
            let rows = s.rows(for: s.top)
            if rows.indices.contains(s.top.sel), case .color = rows[s.top.sel] { colorPress = true }
        }
        guard action == .select && !s.setupDone && screen == .pickMusic else { return }
        let rows = s.rows(for: s.top)
        if rows.indices.contains(s.top.sel), case .pickService(let service) = rows[s.top.sel] { pick = service }
    }
}

/// CLA-97: the events of one action, from the state before and after it. Setup is the first
/// setup, and Activate also on a set-up Mac that must activate.
func betaEvents(_ s: inout AppState, _ b: BeforeEvents, _ fx: [Effect], now: Double) -> [Effect] {
    var events: [BetaEvent] = []
    let screen = s.top.screen
    let seconds = s.firstLaunchAt.map { max(0, Int((now - $0).rounded())) }
    let inSetup = !b.setupDone || screen == .activate
    if inSetup {
        if let pick = b.pick {  // Apple Music stays on the screen for the macOS prompt
            events.append(.musicPick(pick, top: b.top, spotifyApp: s.spotifyApp))
        }
        var step: SetupStep? = screen != b.screen ? SetupStep(screen) : nil
        if !b.setupDone && s.setupDone { step = .allSet }
        if let step, step != s.lastSetupStep {
            s.lastSetupStep = step
            if step == .allSet {
                // CLA-197: with the prefetch count (CLA-194). It waits for the count when the
                // setup ends first, as `app_speed` does (`HeldAllSet`).
                let memory = s.librarySize
                let held = HeldAllSet(seconds: seconds, service: s.service, playlists: memory.playlists, songs: memory.songs)
                if let count = s.libraryCount { events.append(held.event(count)) } else { s.heldAllSet = held }
            } else {
                events.append(.setupStep(step, seconds: seconds, service: s.service, color: b.colorPress ? s.deviceColor : nil))
            }
        }
        if let error = setupError(s, changed: screen != b.screen || s.activateStep != b.activateStep) {
            events.append(.setupError(error, service: s.service, reason: error == .noConnection ? s.activateFailure : nil))
        }
    }
    if !s.firstSongSent, s.analyticsOn, let seconds, b.played, s.isPlaying, s.current != nil {
        s.firstSongSent = true
        events.append(.firstSong(seconds: seconds, service: s.service))
    }
    if b.setupDone && screen != .activate {
        var error: UseError?
        if screen == .loginFailed && b.screen != .loginFailed { error = .loginFailed }
        if screen == b.screen && s.top.error && !b.error { error = .listNotLoaded }
        if b.songFailed { error = .songNotPlayed }
        if error == .listNotLoaded {
            events.append(.useError(.listNotLoaded, offline: s.offline, service: s.service, list: s.listKind(s.top.screen),
                                    status: s.top.failStatus.map { Int($0) }))
        } else if let error {
            events.append(.useError(error, offline: s.offline, service: s.service))
        }
        if s.service != b.service { events.append(.serviceSwitch(from: b.service, to: s.service)) }
    }
    if !s.speedSent, let launched = s.launchedAt, b.libraryRead {
        let loaded = s.readAt != b.readAt || s.artistsLoaded != b.artists  // the Artists read sets no `readAt`
        // A failed read that the app took: its load, refresh or cover read ended. A stale or
        // unasked one changes none of them.
        let failed = (b.loading && !s.top.loading) || s.refreshing.count < b.refreshes || s.artReads.count < b.coverReads
        if loaded || failed {
            s.speedSent = true
            let memory: (playlists: Int?, songs: Int?) = loaded ? s.librarySize : (nil, nil)
            let held = HeldSpeed(startMs: s.startMs, libraryMs: max(0, Int(((now - launched) * 1000).rounded())), loaded: loaded,
                                 playlists: memory.playlists, songs: memory.songs)
            // CLA-194: the counts come from the start's prefetch, which reads the playlist list
            // and `albumsList` on every service. When the first read ends before it, the event
            // waits for it (or for the quit).
            if let count = s.libraryCount { events.append(held.event(count)) } else { s.heldSpeed = held }
        }
    }
    if let held = s.heldSpeed, let count = s.libraryCount {
        s.heldSpeed = nil
        events.append(held.event(count))
    }
    // No count by the quit, or the service changed first (the next count is the other
    // service's): what was in memory at the read.
    if b.quit || s.service != b.service, let held = s.heldSpeed {
        s.heldSpeed = nil
        events.append(held.event(nil))
    }
    if let held = s.heldAllSet, let count = s.libraryCount {
        s.heldAllSet = nil
        events.append(held.event(count))
    }
    if b.quit || s.service != b.service, var held = s.heldAllSet {
        s.heldAllSet = nil
        if s.service == held.service {  // what memory has now; after a switch, what it had at the end
            let memory = s.librarySize
            (held.playlists, held.songs) = (memory.playlists ?? held.playlists, memory.songs ?? held.songs)
        }
        events.append(held.event(nil))
    }
    if s.service != b.service { s.libraryCount = nil }
    // CLA-181: `start` the first time the tour turns on (once; a later start for the trial's
    // steps sends it only if none went out), then each tour step that ended, once ever.
    if s.tourOn && !b.tourOn && !s.hintStartSent && s.analyticsOn {
        s.hintStartSent = true
        events.append(.hintStep(.start, how: nil, service: s.service))
    }
    for hint in s.tourSteps where s.hintsDone.contains(hint) && !b.hintsDone.contains(hint) {
        guard let step = HintStep(hint) else { continue }
        let unused = s.tourHides[hint, default: 0] >= AppState.tourHideMax
        events.append(.hintStep(step, how: unused ? .unused : .done, service: s.service))
    }
    let daysLeft = s.beta.map { Int((max(0, $0.endsAt - now) / BetaBuild.day).rounded(.up)) } ?? 0
    if screen != b.screen, let notice = BetaNotice(screen) {
        events.append(.betaRenewal(notice, pressed: false, daysLeft: daysLeft))
    }
    if fx.contains(.getNewBeta), let notice = BetaNotice(b.screen) {
        events.append(.betaRenewal(notice, pressed: true, daysLeft: daysLeft))
    }
    if let build = b.build, build.number > 0 {
        if let old = s.lastBuild, old != build.number {
            events.append(.appUpdated(from: old, to: build.number, days: max(0, Int((now - build.signed) / BetaBuild.day))))
        }
        s.lastBuild = build.number
    }
    return events.map(Effect.track)
}

/// CLA-97: counts today's music and features, and sends `day_active` for a day that ended.
/// A day starts with its first count, so an action with nothing to count changes nothing.
func dayEvents(_ s: inout AppState, _ action: Action, _ b: BeforeEvents, now: Double, in timeZone: TimeZone) -> [Effect] {
    var fx: [Effect] = []
    var quit = false, openSeconds: Double?
    if case .willQuit(let seconds) = action { (quit, openSeconds) = (true, seconds) }
    func send(_ day: DayUse) {
        fx.append(.track(.dayActive(day, service: day.service ?? s.service, color: s.deviceColor,
                                    settings: DaySettings(albumArt: s.albumArt, clicker: s.clicker, menuBar: s.menuBar))))
    }
    /// Ends the day before `t`'s day: `day_active` for it, if it had any use. While music plays
    /// with an open interval, the day ends at the next position report or the pause, which
    /// split the interval at midnight first (Codex on #348): so each day goes out once, whole.
    func roll(_ t: Double, force: Bool = false) -> (day: Int, weekday: Int, band: Int) {
        let at = DayUse.at(t, in: timeZone)
        let open = s.isPlaying && s.dayPlayAt != nil
        if let old = s.today, old.day < at.day, force || !open {
            if old.hadUse { send(old) }
            s.today = nil; s.dayTrack = nil  // the first song of a new day counts again
        }
        return at
    }
    func count(at t: Double, force: Bool = false, _ change: (inout DayUse, Int) -> Void) {
        let at = roll(t, force: force)
        if var today = s.today, at.day < today.day {
            // That day already went out (for example after the clock moved). Its part goes to
            // this day's night band, so no time is lost (Jason: no silent data loss).
            change(&today, 0)
            s.today = today
            return
        }
        var d = s.today ?? DayUse(day: at.day, weekday: at.weekday)
        change(&d, at.band)
        s.today = d
    }
    /// Counts an open 3D view from where it was counted up to `t`, at most `view3DLimit` from its
    /// open. Each part goes to its own day, as music does.
    func settle(_ view: View3D, upTo t: Double) {
        guard let start = s.viewOpen[view] else { return }
        var from = s.viewCounted[view] ?? start
        let stop = min(t, start + view3DLimit), i = view.index
        while from < stop {
            let end = min(stop, DayUse.nextBand(after: from, in: timeZone)), part = end - from
            if let old = s.today, old.day < DayUse.at(from, in: timeZone).day, s.isPlaying && s.dayPlayAt != nil {
                s.pendingViews[i] += part  // the day before waits for the next report
            } else {
                count(at: from) { d, _ in d.views[i] += part }
            }
            from = end
        }
        s.viewCounted[view] = max(s.viewCounted[view] ?? start, stop)
    }
    // Codex on #352: views open over midnight first count their part of each day before, all
    // views up to one midnight before the next, so each day goes out once, whole.
    if !s.viewOpen.isEmpty, let today = s.today, today.day < DayUse.at(now, in: timeZone).day {
        let last = DayUse.startOfDay(now, in: timeZone)
        let from = s.viewOpen.map { s.viewCounted[$0.key] ?? $0.value }.min() ?? last
        var midnight = DayUse.startOfDay(from, in: timeZone)
        repeat {
            midnight = min(last, DayUse.startOfDay(midnight + 26 * 3600, in: timeZone))  // the next midnight
            for view in View3D.allCases { settle(view, upTo: midnight) }
        } while midnight < last
    }
    // CLA-186, `songs_cut`: the counted song ended by itself (the engine moved on, stopped at
    // the end, or failed) under `cutLimit` after its start. `dayPosition` and the time since
    // that report say how far it got. A skip, seek or new pick (a new `playGen`), a pause or a
    // service switch first drops `dayPosition`, so their end never counts. A song shorter than
    // `cutLimit` does not count; one with no known length does.
    var ended = false
    switch action {
    case .trackChanged(let id, _, let gen): ended = gen == b.gen && id != s.dayTrack
    case .trackEnded(let gen), .playbackFailed(_, let gen): ended = gen == b.gen
    default: break
    }
    // Any end drops `dayPosition`, so it is always the counted song's (`dayTrack`).
    if ended, b.playing, let track = s.dayTrack, let at = s.dayPlayAt, let t = s.dayPosition, t + max(0, now - at) < cutLimit {
        let length = s.track(TrackRef(playlist: s.current?.playlist ?? "", track: track))?.duration ?? 0  // 0: not known
        // The cut goes to the day of the song's last report: an end just after midnight, with
        // the music stopped, would roll that day out first (Codex on #474).
        if length == 0 || length >= cutLimit {
            count(at: at) { d, _ in d.songsCut += 1 }
            // CLA-203: the cut song as its own event too (the Store adds the timeline and the cap).
            let pos = Int((t + max(0, now - at)).rounded(.down))
            fx.append(.track(.songCut(pos: pos, len: length > 0 ? Int(length.rounded()) : nil, service: s.service)))
        }
    }
    if ended || s.playGen != b.gen || s.service != b.service || (b.playing && !s.isPlaying) { s.dayPosition = nil }
    if b.played, s.isPlaying, let current = s.current {
        if let last = s.dayPlayAt, now > last {
            // A long gap on the same track counts the music that played in it, as the position
            // moved: App Nap can slow the reports while myPod is hidden. After a Mac sleep this
            // can count too much, by at most the rest of one track. Another track, or a
            // position that went back: at most `dayGapLimit`.
            let wall = now - last
            var add = min(wall, dayGapLimit)
            if wall > dayGapLimit, s.dayTrack == current.track, let from = s.dayPosition, b.position > from {
                add = min(wall, b.position - from)
            }
            // The time goes to the band and the day of each part (Codex on #348).
            var t = now - add
            while t < now {
                let end = min(now, DayUse.nextBand(after: t, in: timeZone)), from = t
                count(at: t, force: true) { d, band in d.bands[band] += end - from }
                t = end
            }
        }
        (s.dayPlayAt, s.dayPosition) = (now, b.position)
        _ = roll(now, force: true)
        if s.dayTrack != current.track {
            s.dayTrack = current.track
            let (shuffle, repeating) = (s.shuffle, s.repeatMode != .off)
            count(at: now) { d, _ in
                d.songs += 1
                if shuffle { d.songsShuffle += 1 }
                if repeating { d.songsRepeat += 1 }
            }
        }
        let service = s.service
        count(at: now) { d, _ in d.service = service }
    } else if !s.isPlaying && s.dayPlayAt != nil {
        s.dayPlayAt = nil
    }
    // CLA-203: music that the Spotify app on this Mac plays while myPod is not in control.
    // The time since the last report goes to the day of this one, at most `outsideGapLimit`.
    // A quit ends it.
    var outsideNow: Bool?, outsideSong = false
    if case .outsideMusic(let playing, let song) = action { (outsideNow, outsideSong) = (playing, song) }
    if quit { outsideNow = false }
    if let playing = outsideNow {
        if let at = s.outsideAt, now > at {
            let add = min(now - at, outsideGapLimit)
            count(at: now) { d, _ in d.outsideSeconds += add }
            s.launchUse.outsideSeconds += add
        }
        if outsideSong { count(at: now) { d, _ in d.outsideSongs += 1 } }
        s.outsideAt = playing ? now : nil
    }
    // Jason 23:58 JST: the time of each 3D view, from its open to its close, at most
    // `view3DLimit` (a window left open). A quit closes them all.
    if case .view3D(let view, open: false) = action {
        settle(view, upTo: now)
        (s.viewOpen[view], s.viewCounted[view]) = (nil, nil)
    }
    // CLA-162: the time since the last window report goes to that report's area and screen, at
    // most `windowGapLimit`. Near midnight up to that much can go to the new day.
    var windowReport = quit
    if case .window = action { windowReport = true }
    if windowReport, let spot = s.windowSpot, let last = s.windowAt, now > last {
        let add = min(now - last, windowGapLimit)
        count(at: now) { d, _ in
            d.areas[spot.area] += add
            d.screens[spot.screenKey, default: 0] += add
            d.screenCount = max(d.screenCount, spot.screens)
        }
    }
    if case .window(let spot) = action { (s.windowSpot, s.windowAt) = (spot, now) }
    // CLA-201: each menu bar icon click, shown or hidden, also in setup. While the day before
    // waits for the next music report (just after midnight), a click goes to that day.
    if case .menuBarClick = action { count(at: now) { d, _ in d.menuBarClicks += 1 } }
    if quit {
        (s.windowSpot, s.windowAt) = (nil, nil)
        for view in View3D.allCases { settle(view, upTo: now) }
        (s.viewOpen, s.viewCounted) = ([:], [:])
    }
    // At a quit no report comes after, so the day that waits ends now.
    _ = roll(now, force: quit)
    var used: Set<Feature> = b.used.map { [$0] } ?? []
    if case .view3D(let view, open: true) = action {
        if s.viewOpen[view] == nil { s.viewOpen[view] = now }
        used.insert(view.feature)
    }
    if s.top.screen == .coverFlow { used.insert(.coverFlow) }
    if b.screen == .settings && s.settings.choices != b.choices { used.insert(.settings) }
    if let old = s.today, old.day < DayUse.at(now, in: timeZone).day {
        // The day before still waits for the next report: a feature used now belongs to the new
        // day, so it waits too (Codex on #348).
        s.pendingFeatures.formUnion(used)
    } else {
        used.formUnion(s.pendingFeatures)
        s.pendingFeatures = []
        if !used.isSubset(of: s.today?.features ?? []) { count(at: now) { d, _ in d.features.formUnion(used) } }
        if s.pendingViews.contains(where: { $0 > 0 }) {
            let views = s.pendingViews
            s.pendingViews = [0, 0, 0]
            count(at: now) { d, _ in for i in views.indices { d.views[i] += views[i] } }
        }
    }
    // CLA-182 (Jason 16:33 JST 11-24): a normal quit sends today's numbers now, so a person who
    // does not come back still counts. Today then starts again from zero: a second run on the
    // same day sends only the rest, and the two events add up to the day. Known limit (CTO): a
    // song that plays on over a quit and a restart on the same day counts once in each run.
    if quit, let today = s.today, today.hadUse {
        send(today)
        s.today = DayUse(day: today.day, weekday: today.weekday)
    }
    countLaunch(&s, action, b, now: now, quit: quit)
    // CLA-186: `app_closed`, in the same batch as that `day_active`. Only the kind of screen.
    if quit {
        fx.append(.track(.appClosed(minutes: openSeconds.map { max(0, $0) / 60 }, screen: s.top.screen.eventName,
                                    service: s.service, use: s.launchUse)))
    }
    // Jason 23:07 JST: the saved copy follows about once a minute, and at each other change,
    // a pause and a quit. A crash while music plays can lose up to 1 minute of the day.
    let saved = s.savedToday, today = s.today
    let minute: (DayUse?) -> Int? = { $0.map { Int($0.seconds / 60) } }
    let changed = saved?.day != today?.day || saved?.songs != today?.songs || saved?.features != today?.features
        || saved?.service != today?.service || minute(saved) != minute(today) || saved?.views != today?.views
        || saved?.visible != today?.visible || saved?.songsCut != today?.songsCut || saved?.menuBarClicks != today?.menuBarClicks
        || saved?.outsideSongs != today?.outsideSongs || saved?.outsideSeconds != today?.outsideSeconds  // CLA-203 (Codex on #526)
    if changed || (b.playing && !s.isPlaying) || quit { s.savedToday = today }
    return fx
}

/// The error that the screen shows now, when it just opened or changed.
private func setupError(_ s: AppState, changed: Bool) -> SetupError? {
    guard changed else { return nil }
    switch s.top.screen {
    case .spotifyApp: return .spotifyNotFound
    case .premium: return s.service == .spotify ? .premiumNeeded : .noPlan
    case .loginFailed: return .loginFailed
    case .accessOff: return .accessOff
    case .activate:
        switch s.activateStep {
        case .mailBusy: return .mailBusy
        case .full: return .betaFull
        case .off: return .accountOff
        case .offline: return .noConnection
        default: return nil
        }
    default: return nil
    }
}

/// CLA-194: an `app_speed` measured at the first read, with the counts in memory then.
struct HeldSpeed: Equatable, Sendable {
    var startMs: Int?
    var libraryMs: Int
    var loaded: Bool
    var playlists: Int?, songs: Int?
    /// The event. A prefetch count wins; a count that its read did not get comes from memory.
    func event(_ count: LibraryCount?) -> BetaEvent {
        .appSpeed(startMs: startMs, libraryMs: libraryMs, loaded: loaded,
                  playlists: count?.playlists ?? playlists, songs: count?.songs ?? songs)
    }
}

/// CLA-197: an `all_set` whose setup ended before the prefetch count came, with the counts in
/// memory then. It goes out once: with the count, or at the quit or a service change without it.
struct HeldAllSet: Equatable, Sendable {
    var seconds: Int?
    var service: MusicService
    var playlists: Int?, songs: Int?
    func event(_ count: LibraryCount?) -> BetaEvent {
        .setupStep(.allSet, seconds: seconds, service: service, playlists: count?.playlists ?? playlists, songs: count?.songs ?? songs)
    }
}

extension AppState {
    /// CLA-186, `app_speed`: the playlists and songs read so far, each nil until its list is read.
    /// Only what is in memory: no read for the count.
    var librarySize: (playlists: Int?, songs: Int?) {
        let playlists = playlistsLoaded ? library.filter { !Playlist.isHidden($0.id) }.count : nil
        let songs = loadedTracks.contains(albumsList) ? library.first { $0.id == albumsList }?.tracks.count : nil
        return (playlists, songs)
    }
}

/// CLA-203: counts this launch's play use for `app_closed` (`LaunchUse`). Not inlined, so
/// `dayEvents`'s stack frame stays small (reducer stack limit).
@inline(never) func countLaunch(_ s: inout AppState, _ action: Action, _ b: BeforeEvents, now: Double, quit: Bool) {
    var use = s.launchUse
    // CTO: a start or a stop by any way (myPod, a song pick, another device, the end of the list).
    // A loss of control counts in `stops_*`, also the `.playbackFailed` that the player sends
    // just after it (Codex on #531), and the quit's own stop is not a pause.
    if !b.playing && s.isPlaying { use.plays += 1 }
    switch action {
    case .controlLost, .willQuit: break
    default: if b.playing && !s.isPlaying && !b.lossOpen { use.pauses += 1 }
    }
    switch action {
    case .next, .prev: if s.current != nil { use.skips += 1 }
    case .controlLost where !b.lossOpen && s.controlLostAt != nil:
        if b.playing { use.stopsPlaying += 1 } else { use.stopsPaused += 1 }
    default: break
    }
    // A pause runs from the music's stop to its next start, or to the quit.
    if b.playing && !s.isPlaying { use.pausedAt = now }
    if let at = use.pausedAt, (!b.playing && s.isPlaying) || quit {
        use.longestPause = max(use.longestPause, now - at)
        use.pausedAt = nil
    }
    if use != s.launchUse { s.launchUse = use }
}
