import Foundation

/// CLA-186: a person's first steps after setup, each sent once per install as `first_step`, so
/// the time between `all_set` and the first song is no longer empty (Jason 12:23 JST 11-25).
public enum FirstStep: String, CaseIterable, Sendable {
    /// The first open of a list of songs: a playlist, an album, an artist, Songs or the liked list.
    case listOpened = "list_opened"
    /// The first press of Play or the center button that asks for a song.
    case playPressed = "play_pressed"
    /// The first play that brought no music: it failed, or it stayed silent for `FirstSteps.silentAfter`.
    case playNoMusic = "play_no_music"
}

/// How a play brought no music, for `play_no_music`.
public enum NoMusic: String, Sendable {
    /// The player said the song did not load (`Action.loadFailed`, as `use_error song_not_played`).
    case failed
    /// No music and no failure `FirstSteps.silentAfter` seconds after the press.
    case silent
}

/// CLA-186: the state of `first_step`, in `AppState.firstStepsBox`.
struct FirstSteps: Equatable, Sendable {
    /// The steps that went out. Saved with the settings (`Settings.firstSteps`).
    var sent: Set<FirstStep> = []
    /// When this launch started, and when `all_set` went out in it: `seconds` counts from
    /// `all_set` in the launch of the setup, else from the launch. Not saved.
    var launchAt: Double?, allSetAt: Double?
    /// When a play press brings `play_no_music` with `silent`, if no music or failure comes
    /// first. nil while no press waits. Not saved: a quit cancels it.
    var silentAt: Double?
    /// Music played in this launch. Not saved: `first_song` (`AppState.firstSongSent`) keeps it
    /// across launches, but a Mac set up before CLA-97 never sends that.
    var heard = false
    /// `AppState.launchedAt`, for `app_speed`.
    var speedFrom: Double?
    /// CLA-194: the start's prefetch count, and an `app_speed` that waits for it. Not saved.
    var libraryCount: LibraryCount?, heldSpeed: HeldSpeed?
    /// CLA-197: an `all_set` that waits for the count. Not saved.
    var heldAllSet: HeldAllSet?

    /// The wait for music after a press (CTO 12:26 JST 11-25).
    static let silentAfter = 20.0
}

extension AppState {
    /// CLA-186: the `first_step` events that went out (saved).
    public var firstStepsSent: Set<FirstStep> {
        get { firstStepsBox.value.sent }
        set { firstStepsBox.value.sent = newValue }
    }

    /// CLA-186: a play press waits for music, and its 20 s are over. The app sends `.tick`.
    public func firstStepDue(at now: Double) -> Bool {
        firstStepsBox.value.silentAt.map { now >= $0 } ?? false
    }
}

/// CLA-186: the state before an action that `firstStepEvents` needs.
struct BeforeFirstSteps {
    var setupDone: Bool, screen: Screen, depth: Int, service: MusicService, startToken: Int?, shuffleToken: Int?
    /// The action is the player's report of music (a position past 0 for the playing load), or
    /// its failure to load the playing song.
    var played = false, failed = false

    init(_ s: AppState, _ action: Action) {
        (setupDone, screen, depth, service) = (s.setupDone, s.top.screen, s.stack.count, s.service)
        (startToken, shuffleToken) = (s.startToken, s.shuffleToken)
        if case .position(let t, let gen) = action, t > 0, gen == s.playGen { played = true }
        if case .loadFailed(_, let gen) = action, gen == s.playGen, s.current != nil { failed = true }
    }
}

/// CLA-186: the `first_step` events of one action. Outside `apply()`, for the stack limit.
func firstStepEvents(_ s: inout AppState, _ b: BeforeFirstSteps, _ action: Action, _ fx: [Effect], now: Double) -> [Effect] {
    if action == .launch && s.firstStepsBox.value.launchAt == nil { s.firstStepsBox.value.launchAt = now }
    if !b.setupDone && s.setupDone { s.firstStepsBox.value.allSetAt = now }
    guard b.setupDone && s.setupDone && s.top.screen != .activate else { return [] }
    var events: [BetaEvent] = []
    func send(_ step: FirstStep, how: NoMusic? = nil) {
        guard s.analyticsOn, !s.firstStepsSent.contains(step) else { return }
        s.firstStepsSent.insert(step)
        let from = s.firstStepsBox.value.allSetAt ?? s.firstStepsBox.value.launchAt ?? now
        events.append(.firstStep(step, how: how, seconds: max(0, Int((now - from).rounded())), service: s.service))
    }
    // A list of songs opened: a new screen with songs on top.
    if s.top.screen.songList != nil && (s.top.screen != b.screen || s.stack.count != b.depth) { send(.listOpened) }
    // A press that asks for music: a song loads or goes on, or a list or Shuffle Songs starts
    // after its read (Codex on #471).
    let asks = fx.contains { if case .load = $0 { true } else { $0 == .resume } }
        || (s.startToken != nil && s.startToken != b.startToken) || (s.shuffleToken != nil && s.shuffleToken != b.shuffleToken)
    let pressed = (action == .play || action == .select) && asks
    if pressed { send(.playPressed) }
    // `silent` waits only until music was heard once or `play_no_music` went out.
    let music = b.played && s.isPlaying && s.current != nil
    if music { s.firstStepsBox.value.heard = true }
    let waits = s.analyticsOn && !s.firstSongSent && !s.firstStepsBox.value.heard && !s.firstStepsSent.contains(.playNoMusic)
    if music || !waits || s.service != b.service || fx.contains(.pause) {
        s.firstStepsBox.value.silentAt = nil  // music came, a Pause, a service switch, or no more waits
    }
    if b.failed {
        s.firstStepsBox.value.silentAt = nil
        send(.playNoMusic, how: .failed)
    } else if pressed && waits && !music {
        s.firstStepsBox.value.silentAt = now + FirstSteps.silentAfter  // a new pick waits again from its press
    } else if s.firstStepDue(at: now) {
        s.firstStepsBox.value.silentAt = nil
        send(.playNoMusic, how: .silent)
    }
    return events.map(Effect.track)
}
