import Foundation

/// CLA-202 spike: what the tester copies to us. Numbers, times, states and error kinds only: no
/// names, no IDs, no account data. Lines stay in memory; nothing goes to disk.
@MainActor final class Probe {
    private(set) var lines: [String] = []
    private let start = Date.now

    /// The play press that waits for its first sound: when the list was tapped, and when the
    /// player got the load (after the list read).
    private var playPressed: (n: Int, tapped: Date, loaded: Date)?
    private var plays = 0
    /// The song that plays now (by ID, kept here only), how far it played, and its length.
    private var song: (id: String, played: Double, duration: Double)?
    /// A Next, Prev or play press whose song change has not come yet: that change is not a short song.
    private var userMove = false
    private var backgroundAt: (at: Date, status: String, time: Double)?
    private var backgrounds = 0

    /// A number with `digits` decimals.
    private func f(_ x: Double, _ digits: Int = 1) -> String { String(format: "%.\(digits)f", x) }

    func log(_ text: String) {
        lines.append(String(format: "+%.1f s  ", Date.now.timeIntervalSince(start)) + text)
    }

    func play(tapped: Date) {
        plays += 1
        playPressed = (plays, tapped, Date.now)
        userMove = true
        song = nil
        log("play \(plays): pressed")
    }

    func skip(_ forward: Bool) {
        userMove = true
        log(forward ? "next pressed" : "prev pressed")
    }

    /// A `.position` report: the player polls every 0.5 s and reports only while it plays.
    func position(_ t: Double) {
        if let press = playPressed, t > 0 {
            log(String(format: "play %d: first sound %.2f s after the tap, %.2f s after the load (polled, +/- 0.5 s)",
                       press.n, Date.now.timeIntervalSince(press.tapped), Date.now.timeIntervalSince(press.loaded)))
            playPressed = nil
        }
        if let s = song { song = (s.id, max(s.played, t), s.duration) }
    }

    func trackChanged(_ id: String, playing: Bool, duration: Double) {
        if song?.id != id {
            let moved = userMove
            userMove = false  // this change (also the first song after a play) is the one that the press asked for
            if let s = song, s.played < 5 && !moved {
                log(String(format: "short song: changed after %.1f s of %.0f s, no Next/Prev pressed", s.played, s.duration))
            }
        }
        if song?.id != id { song = (id, 0, duration) }
        log("song changed, playing: \(playing)")
    }

    func ended() {
        if let s = song, s.played < 5 { log(String(format: "short song: queue ended after %.1f s of %.0f s", s.played, s.duration)) }
        log("queue ended")
    }

    func error(_ kind: String, _ message: String) { log("error: \(kind): \(message)") }

    func background(audioMode: Bool, status: String, time: Double) {
        backgrounds += 1
        backgroundAt = (Date.now, status, time)
        log("background \(backgrounds) (Audio mode \(audioMode ? "on" : "off")): \(status) at \(f(time)) s")
    }

    func active(status: String, time: Double) {
        guard let before = backgroundAt else { return }
        backgroundAt = nil
        let away = Date.now.timeIntervalSince(before.at)
        log("back after \(f(away, 0)) s: \(status) at \(f(time)) s (moved \(f(time - before.time)) s; \(before.status) before)")
    }
}
