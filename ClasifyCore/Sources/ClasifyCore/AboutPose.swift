/// The capybara on About (card BF, change 210). It waves when About opens and on a press, then
/// its idle clock runs: think at 4 s, stand at 6.5 s, boba at 10 s, stand at 13 s, sleep at
/// 20 s. The pose is a pure function of time, so the skin only draws it.
public enum AboutPose: Sendable, Equatable, CaseIterable {
    case stand, wave, think, boba, sleep
}

/// The pose at one moment, and how it came: `since` is when it started, `from` the pose before
/// it. A cut shows at once; any other change is a 0.3 s crossfade over `from`.
public struct AboutPoseNow: Sendable, Equatable {
    public var pose: AboutPose
    public var since: Double
    public var from: AboutPose
    public var cut: Bool

    public init(pose: AboutPose, since: Double, from: AboutPose, cut: Bool) {
        self.pose = pose; self.since = since; self.from = from; self.cut = cut
    }
}

extension AppState {
    /// The wave waits 0.35 s after About opens, and lasts 1 s.
    public static let aboutWaveDelay = 0.35, aboutWaveTime = 1.0
    /// The idle clock, in seconds from the end of the wave or from the last input.
    public static let aboutIdle: [(at: Double, pose: AboutPose)] = [
        (4, .think), (6.5, .stand), (10, .boba), (13, .stand), (20, .sleep),
    ]

    /// The capybara's pose at time `t`.
    public func aboutPose(at t: Double) -> AboutPoseNow {
        let waveEnd = aboutWaveAt + Self.aboutWaveTime
        if t < aboutWaveAt { return AboutPoseNow(pose: .stand, since: aboutAt, from: .stand, cut: true) }
        if t < waveEnd { return AboutPoseNow(pose: .wave, since: aboutWaveAt, from: .stand, cut: true) }
        // An input after the wave restarts the clock, but the pose stays until the clock
        // changes it, as in the mock.
        let restarted = aboutIdleAt > waveEnd
        let start = restarted ? aboutIdleAt : waveEnd
        var now = restarted ? aboutIdleHold : AboutPoseNow(pose: .stand, since: waveEnd, from: .wave, cut: true)
        for step in Self.aboutIdle where start + step.at <= t && step.pose != now.pose {
            now = AboutPoseNow(pose: step.pose, since: start + step.at, from: now.pose, cut: false)
        }
        return now
    }

    /// The wave runs at `t`.
    public func aboutWaving(at t: Double) -> Bool { aboutPose(at: t).pose == .wave }
}
