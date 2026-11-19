/// CLA-97: a beta analytics event. The reducer decides it and returns it as `Effect.track`;
/// the app's sender (A3) adds the account ID, the build and the macOS version, and sends it
/// only from a signed beta build with a key, on an activated Mac, with `analytics.on`. No
/// email, no song or playlist names.
public enum BetaEvent: Equatable, Sendable {
    /// Each setup screen a person reaches, once in a row (`log_in` covers the login and the browser).
    /// `seconds` is nil on a Mac with no first launch time (set up before CLA-97).
    case setupStep(SetupStep, seconds: Int?, service: MusicService)
    /// Setup stops on an error.
    case setupError(SetupError, service: MusicService)
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
        }
    }

    /// The event's own data. The sender adds the rest.
    public var properties: [String: BetaValue] {
        switch self {
        case .setupStep(let step, let seconds, let service):
            var p: [String: BetaValue] = ["step": .text(step.rawValue), "service": .text(service.eventName)]
            if let seconds { p["seconds"] = .number(seconds) }
            return p
        case .setupError(let kind, let service):
            return ["kind": .text(kind.rawValue), "service": .text(service.eventName)]
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
        }
    }
}

/// A value in an event's data.
public enum BetaValue: Equatable, Sendable {
    case text(String), number(Int), flag(Bool)
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

extension MusicService {
    /// `spotify` or `apple_music`, as the events name it.
    public var eventName: String { self == .spotify ? "spotify" : "apple_music" }
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
    var played = false

    init(_ s: AppState, _ action: Action) {
        (screen, setupDone, activateStep) = (s.top.screen, s.setupDone, s.activateStep)
        top = s.appleMusicFirst ? .appleMusic : .spotify
        pick = nil
        if case .position(let t, let gen) = action, t > 0, gen == s.playGen { played = true }
        if case .betaBuild(let b) = action { build = b }
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
            events.append(.setupStep(step, seconds: seconds, service: s.service))
        }
        if let error = setupError(s, changed: screen != b.screen || s.activateStep != b.activateStep) {
            events.append(.setupError(error, service: s.service))
        }
    }
    if !s.firstSongSent, let seconds, b.played, s.isPlaying, s.current != nil {
        s.firstSongSent = true
        events.append(.firstSong(seconds: seconds, service: s.service))
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
