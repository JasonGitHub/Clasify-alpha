import Foundation

/// CLA-203: a fact from the engine or the Mac that the reducer does not see, for the timeline
/// (`Action.note`). No names, no IDs: devices are only here, gone or other, errors are numbers.
public enum EngineNote: Equatable, Sendable {
    /// The Spotify app on this Mac is the active device, no device is active, or another device is.
    case deviceHere, deviceGone, deviceOther
    /// The Spotify app on this Mac runs, or quit.
    case appRunning, appQuit
    /// librespot's dealer connection came back, a new login finished, a Connect command timed out.
    case dealerReconnect, newLogin, commandTimeout
    /// A librespot error number, and a MusicKit error code.
    case error(Int), musicKitError(Int)
    /// The Mac sleeps, wakes, or its network path changed.
    case sleep, wake, pathChange

    /// The timeline text: `kind` or `kind:number`.
    var text: String {
        switch self {
        case .deviceHere: "dev_here"
        case .deviceGone: "dev_gone"
        case .deviceOther: "dev_other"
        case .appRunning: "app_run"
        case .appQuit: "app_quit"
        case .dealerReconnect: "dealer"
        case .newLogin: "login"
        case .commandTimeout: "timeout"
        case .error(let n): "err:\(n)"
        case .musicKitError(let n): "mk_err:\(n)"
        case .sleep: "sleep"
        case .wake: "wake"
        case .pathChange: "path"
        }
    }
}

/// CLA-203: what happened in the last `span` seconds, in memory only, so a problem event can
/// say what came before it. The Store owns it and records in `send`; it is not in `AppState`,
/// so the reducer's stack frame does not grow (reducer stack limit). It holds no names or IDs.
public final class Timeline {
    struct Entry: Equatable {
        var text: String, at: Double, count = 1
    }

    /// Entries older than this go.
    static let span = 120.0
    /// At most this many entries: the oldest goes first.
    static let limit = 60
    /// Wheel steps closer than this merge into one entry with a count.
    static let wheelMerge = 1.0

    private(set) var entries: [Entry] = []
    /// The newest wheel step, while its entry is the newest one.
    private var wheelAt: Double?

    public init() {}

    /// Adds one fact at `now`. Wheel steps within `wheelMerge` of the last one add to its count.
    func record(_ text: String, at now: Double) {
        if text == "wheel", let last = wheelAt, now - last <= Self.wheelMerge, entries.last?.text == "wheel" {
            entries[entries.count - 1].count += 1
            wheelAt = now
            return
        }
        entries.append(Entry(text: text, at: now))
        wheelAt = text == "wheel" ? now : nil
        prune(now)
    }

    private func prune(_ now: Double) {
        entries.removeAll { now - $0.at > Self.span }
        if entries.count > Self.limit { entries.removeFirst(entries.count - Self.limit) }
    }

    /// The text form, newest last: `kind:value@-seconds`, a space between entries. For example
    /// `play@-75.9 song@-75.1 wheel:3@-66.0 dev_gone@-0.0`. Empty with no entries.
    public func text(at now: Double) -> String {
        prune(now)
        return entries.map { e in
            let ago = String(format: "%.1f", max(0, now - e.at))
            return (e.count > 1 || e.text == "wheel" ? "\(e.text):\(e.count)" : e.text) + "@-" + ago
        }.joined(separator: " ")
    }

    /// The facts of one `Store.send`: the action, and the player facts that it changed.
    /// Not inlined, so `Store.send`'s stack frame stays small (reducer stack limit).
    @inline(never) func record(_ action: Action, from before: AppState, to after: AppState, at now: Double) {
        if let text = Self.text(of: action) { record(text, at: now) }
        if after.current != before.current, after.current != nil { record("song", at: now) }
        if after.isPlaying != before.isPlaying { record(after.isPlaying ? "playing" : "paused", at: now) }
        let screen = after.top.screen.eventName
        if screen != before.top.screen.eventName { record("screen:" + screen, at: now) }
    }

    /// The action's own entry, or nil for an action that is not a fact here (a tick, a position).
    static func text(of action: Action) -> String? {
        switch action {
        case .wheel: "wheel"
        case .select: "select"
        case .menu: "menu"
        case .play: "play"
        case .next: "next"
        case .prev: "prev"
        case .trackEnded: "end"
        case .playbackFailed: "play_failed"
        case .loadFailed: "load_failed"
        case .controlLost(let reason): "lost:" + reason.rawValue
        case .controlBack: "back"
        case .willQuit: "quit"
        case .note(let note): note.text
        default: nil
        }
    }
}
