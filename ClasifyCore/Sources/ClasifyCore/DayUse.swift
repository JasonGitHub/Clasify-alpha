import Foundation

/// CLA-97: one day of use, for `day_active`. Saved with the settings (`analytics.day`), so a
/// quit does not lose the day. Exact numbers, no rounding.
public struct DayUse: Equatable, Sendable {
    /// The local day, as yyyymmdd, and its weekday (1 Sunday … 7 Saturday).
    public var day: Int, weekday: Int
    public var songs = 0
    /// Seconds of music in each time band: night (0-6), morning (6-9), work (9-18), evening (18-24).
    public var bands = [0.0, 0, 0, 0]
    public var features: Set<Feature> = []
    /// Seconds of each 3D view (`View3D`, in its order): the Cmd turn, the parts apart, the About flip.
    public var views = [0.0, 0, 0]
    /// The service of the day's last counted music, which `day_active` sends.
    public var service: MusicService?

    public init(day: Int, weekday: Int) { (self.day, self.weekday) = (day, weekday) }

    public var seconds: Double { bands.reduce(0, +) }
    /// The day had music: `day_active` goes out for it.
    public var hadMusic: Bool { songs > 0 || seconds > 0 }

    /// The day, the weekday and the band of `now` (`Dependencies.now` time) in `timeZone`.
    static func at(_ now: Double, in timeZone: TimeZone) -> (day: Int, weekday: Int, band: Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day, .weekday, .hour], from: Date(timeIntervalSinceReferenceDate: now))
        let hour = c.hour ?? 0
        let band = hour < 6 ? 0 : hour < 9 ? 1 : hour < 18 ? 2 : 3
        return ((c.year ?? 0) * 10_000 + (c.month ?? 0) * 100 + (c.day ?? 0), c.weekday ?? 0, band)
    }

    /// The next start of a band after `t`: 6:00, 9:00, 18:00 or the next midnight.
    static func nextBand(after t: Double, in timeZone: TimeZone) -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let start = cal.startOfDay(for: Date(timeIntervalSinceReferenceDate: t))
        for hour in [6, 9, 18, 24] {
            if let next = cal.date(byAdding: .hour, value: hour, to: start)?.timeIntervalSinceReferenceDate, next > t { return next }
        }
        return t + 3600
    }

    /// "20261119|5|3|0.0,0.0,1200.5,0.0|coverFlow,settings|Spotify|12.5,0.0,3.0": the saved
    /// form. A day saved before the 3D views has no last part: its views are 0.
    var saved: String {
        let b: [String] = bands.map { String($0) }
        let f: [String] = features.map(\.rawValue).sorted()
        let v: [String] = views.map { String($0) }
        return [String(day), String(weekday), String(songs), b.joined(separator: ","), f.joined(separator: ","), service?.rawValue ?? "",
                v.joined(separator: ",")].joined(separator: "|")
    }

    init?(saved: String) {
        let parts = saved.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 6 || parts.count == 7, let day = Int(parts[0]), let weekday = Int(parts[1]), let songs = Int(parts[2]) else { return nil }
        let bands = parts[3].split(separator: ",").compactMap { Double($0) }
        guard bands.count == 4 else { return nil }
        self.init(day: day, weekday: weekday)
        (self.songs, self.bands) = (songs, bands)
        features = Set(parts[4].split(separator: ",").compactMap { Feature(rawValue: String($0)) })
        service = MusicService(rawValue: parts[5])
        if parts.count == 7 {
            let views = parts[6].split(separator: ",").compactMap { Double($0) }
            guard views.count == 3 else { return nil }
            self.views = views
        }
    }
}

/// CLA-97: features of `day_active`, one flag a day each.
public enum Feature: String, CaseIterable, Sendable {
    case coverFlow, aboutFlip, takeApart, settings
    /// The Cmd 3D turn of the device (two fingers or a mouse drag), not the About flip.
    case turn3D
}

/// CLA-97 (Jason 23:58 JST): the 3D views that `day_active` times. The skin sends
/// `Action.view3D` when one opens and when it closes, also when the window closes or is no
/// longer visible.
public enum View3D: String, CaseIterable, Sendable {
    /// From the start of a Cmd turn to the device's return to the front.
    case turn
    /// The parts are apart or moving, anywhere.
    case apart
    /// About's showroom shows the flipped or turned device.
    case aboutFlip

    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    var property: String { ["seconds_3d", "seconds_apart", "seconds_about_flip"][index] }
    /// The flag of the day that the view also sets.
    var feature: Feature { [.turn3D, .takeApart, .aboutFlip][index] }
}

/// The longest one 3D view counts: a window left open counts no more (CTO 23:58 JST).
let view3DLimit = 1800.0

/// The longest gap between two position reports that counts as music: longer is a pause or a sleep.
let dayGapLimit = 5.0
