import Foundation

/// CLA-97: a beta analytics event. The reducer decides it and returns it as `Effect.track`;
/// the app's sender (A3) adds the account ID (before activation, a random install ID), the build
/// and the macOS version, and sends it only from a signed beta build with a key, with `analytics.on`. No
/// email, no song or playlist names.
public enum BetaEvent: Equatable, Sendable {
    /// Each setup screen a person reaches, once in a row (`log_in` covers the login and the browser).
    /// `seconds` is nil on a Mac with no first launch time (set up before CLA-97).
    /// `color` is on the step that the press on Color sends: the color picked (CLA-97, Jason 14:23 JST 11-22).
    case setupStep(SetupStep, seconds: Int?, service: MusicService, color: DeviceColor? = nil)
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
    case useError(UseError, offline: Bool, service: MusicService)
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
    /// CLA-186: a first step after setup, once per install (`FirstStep`). `how` on `play_no_music`
    /// only. `seconds` from `all_set` in the setup's launch, else from this launch.
    case firstStep(FirstStep, how: NoMusic?, seconds: Int, service: MusicService)

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
        case .firstStep: "first_step"
        }
    }

    /// The event's own data. The sender adds the rest.
    public var properties: [String: BetaValue] {
        switch self {
        case .setupStep(let step, let seconds, let service, let color):
            var p: [String: BetaValue] = ["step": .text(step.rawValue), "service": .text(service.eventName)]
            if let seconds { p["seconds"] = .number(seconds) }
            if let color { p["color"] = .text(color.eventName) }
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
        case .useError(let kind, let offline, let service):
            return ["kind": .text(kind.rawValue), "offline": .flag(offline), "service": .text(service.eventName)]
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
        case .appProblem(let problem, let service):
            return problem.properties.merging(["service": .text(service.eventName)]) { old, _ in old }
        case .dayActive(let d, let service, let color, let settings):
            var p: [String: BetaValue] = [
                "color": .text(color.eventName), "album_art": .text(settings.albumArt.eventName),
                "clicker": .flag(settings.clicker), "menu_bar": .flag(settings.menuBar),
                "songs_shuffle": .number(d.songsShuffle), "songs_repeat": .number(d.songsRepeat),
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

    init(_ s: AppState, _ action: Action) {
        (screen, setupDone, activateStep) = (s.top.screen, s.setupDone, s.activateStep)
        choices = s.settings.choices
        (tourOn, hintsDone) = (s.tourOn, s.hintsDone)
        playing = s.isPlaying
        (error, service) = (s.top.error, s.service)
        (readAt, artists) = (s.readAt, s.artistsLoaded)
        (loading, refreshes, coverReads) = (s.top.loading, s.refreshing.count, s.artReads.count)
        if case .loadFailed(_, let gen) = action, gen == s.playGen, s.current != nil { songFailed = true }
        if case .used(let feature) = action { used = feature }
        top = s.appleMusicFirst ? .appleMusic : .spotify
        pick = nil
        if case .position(let t, let gen) = action, t > 0, gen == s.playGen { (played, position) = (true, t) }
        if case .betaBuild(let b) = action { build = b }
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
            events.append(.setupStep(step, seconds: seconds, service: s.service, color: b.colorPress ? s.deviceColor : nil))
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
        if let error { events.append(.useError(error, offline: s.offline, service: s.service)) }
        if s.service != b.service { events.append(.serviceSwitch(from: b.service, to: s.service)) }
    }
    if !s.speedSent, let launched = s.launchedAt, b.libraryRead {
        let loaded = s.readAt != b.readAt || s.artistsLoaded != b.artists  // the Artists read sets no `readAt`
        // A failed read that the app took: its load, refresh or cover read ended. A stale or
        // unasked one changes none of them.
        let failed = (b.loading && !s.top.loading) || s.refreshing.count < b.refreshes || s.artReads.count < b.coverReads
        if loaded || failed {
            s.speedSent = true
            let (playlists, songs) = loaded ? s.librarySize : (nil, nil)
            events.append(.appSpeed(startMs: s.startMs, libraryMs: max(0, Int(((now - launched) * 1000).rounded())), loaded: loaded,
                                    playlists: playlists, songs: songs))
        }
    }
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
    // Jason 23:58 JST: the time of each 3D view, from its open to its close, at most
    // `view3DLimit` (a window left open). A quit closes them all.
    if case .view3D(let view, open: false) = action {
        settle(view, upTo: now)
        (s.viewOpen[view], s.viewCounted[view]) = (nil, nil)
    }
    // CLA-162: the time since the last window report goes to that report's area and screen, at
    // most `windowGapLimit`. Near midnight up to that much can go to the new day.
    var windowReport = action == .willQuit
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
    if action == .willQuit {
        (s.windowSpot, s.windowAt) = (nil, nil)
        for view in View3D.allCases { settle(view, upTo: now) }
        (s.viewOpen, s.viewCounted) = ([:], [:])
    }
    // At a quit no report comes after, so the day that waits ends now.
    _ = roll(now, force: action == .willQuit)
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
    if action == .willQuit, let today = s.today, today.hadUse {
        send(today)
        s.today = DayUse(day: today.day, weekday: today.weekday)
    }
    // Jason 23:07 JST: the saved copy follows about once a minute, and at each other change,
    // a pause and a quit. A crash while music plays can lose up to 1 minute of the day.
    let saved = s.savedToday, today = s.today
    let minute: (DayUse?) -> Int? = { $0.map { Int($0.seconds / 60) } }
    let changed = saved?.day != today?.day || saved?.songs != today?.songs || saved?.features != today?.features
        || saved?.service != today?.service || minute(saved) != minute(today) || saved?.views != today?.views
        || saved?.visible != today?.visible
    if changed || (b.playing && !s.isPlaying) || action == .willQuit { s.savedToday = today }
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

extension AppState {
    /// CLA-186, `app_speed`: the playlists and songs read so far, each nil until its list is read.
    /// Only what is in memory: no read for the count.
    var librarySize: (playlists: Int?, songs: Int?) {
        let playlists = playlistsLoaded ? library.filter { !Playlist.isHidden($0.id) }.count : nil
        let songs = loadedTracks.contains(albumsList) ? library.first { $0.id == albumsList }?.tracks.count : nil
        return (playlists, songs)
    }
}
