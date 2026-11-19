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

    /// "20261119|5|3|0.0,0.0,1200.5,0.0|coverFlow,settings": the saved form.
    var saved: String {
        "\(day)|\(weekday)|\(songs)|\(bands.map(String.init).joined(separator: ","))|\(features.map(\.rawValue).sorted().joined(separator: ","))"
    }

    init?(saved: String) {
        let parts = saved.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 5, let day = Int(parts[0]), let weekday = Int(parts[1]), let songs = Int(parts[2]) else { return nil }
        let bands = parts[3].split(separator: ",").compactMap { Double($0) }
        guard bands.count == 4 else { return nil }
        self.init(day: day, weekday: weekday)
        (self.songs, self.bands) = (songs, bands)
        features = Set(parts[4].split(separator: ",").compactMap { Feature(rawValue: String($0)) })
    }
}

/// CLA-97: features of `day_active`, one flag a day each.
public enum Feature: String, CaseIterable, Sendable {
    case coverFlow, aboutFlip, takeApart, settings
}

/// The longest gap between two position reports that counts as music: longer is a pause or a sleep.
let dayGapLimit = 5.0
