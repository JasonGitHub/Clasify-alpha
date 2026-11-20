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
    /// CLA-162: seconds the device window was visible in each area of its screen (`WindowSpot.area`).
    public var areas = [Double](repeating: 0, count: 9)
    /// CLA-162: visible seconds on each screen (`WindowSpot.screenKey`), and the most screens seen.
    public var screens: [String: Double] = [:], screenCount = 0

    public init(day: Int, weekday: Int) { (self.day, self.weekday) = (day, weekday) }

    public var seconds: Double { bands.reduce(0, +) }
    public var visible: Double { areas.reduce(0, +) }
    /// The day had music, a feature or a 3D view: `day_active` goes out for it (CTO 00:08 JST
    /// 11-20: a day with no music shows as minutes 0).
    public var hadUse: Bool { songs > 0 || seconds > 0 || !features.isEmpty || views.contains { $0 > 0 } }

    /// The day, the weekday and the band of `now` (`Dependencies.now` time) in `timeZone`.
    static func at(_ now: Double, in timeZone: TimeZone) -> (day: Int, weekday: Int, band: Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day, .weekday, .hour], from: Date(timeIntervalSinceReferenceDate: now))
        let hour = c.hour ?? 0
        let band = hour < 6 ? 0 : hour < 9 ? 1 : hour < 18 ? 2 : 3
        return ((c.year ?? 0) * 10_000 + (c.month ?? 0) * 100 + (c.day ?? 0), c.weekday ?? 0, band)
    }

    /// The start of `t`'s day.
    static func startOfDay(_ t: Double, in timeZone: TimeZone) -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.startOfDay(for: Date(timeIntervalSinceReferenceDate: t)).timeIntervalSinceReferenceDate
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
    /// form, then CLA-162's window part "areas;screen count;screens". A day saved before the 3D
    /// views or the window has no such part: its counts are 0.
    var saved: String {
        let b: [String] = bands.map { String($0) }
        let f: [String] = features.map(\.rawValue).sorted()
        let v: [String] = views.map { String($0) }
        return [String(day), String(weekday), String(songs), b.joined(separator: ","), f.joined(separator: ","), service?.rawValue ?? "",
                v.joined(separator: ","), windowSaved].joined(separator: "|")
    }

    /// "0.0,…,60.0,…;2;1x1512x982x1=60.0": the areas, the screen count and the seconds per screen.
    private var windowSaved: String {
        let screens = self.screens.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        return [areas.map { String($0) }.joined(separator: ","), String(screenCount), screens.joined(separator: ",")].joined(separator: ";")
    }

    init?(saved: String) {
        let parts = saved.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard (6...8).contains(parts.count), let day = Int(parts[0]), let weekday = Int(parts[1]), let songs = Int(parts[2]) else { return nil }
        let bands = parts[3].split(separator: ",").compactMap { Double($0) }
        guard bands.count == 4 else { return nil }
        self.init(day: day, weekday: weekday)
        (self.songs, self.bands) = (songs, bands)
        features = Set(parts[4].split(separator: ",").compactMap { Feature(rawValue: String($0)) })
        service = MusicService(rawValue: parts[5])
        if parts.count >= 7 {
            let views = parts[6].split(separator: ",").compactMap { Double($0) }
            guard views.count == 3 else { return nil }
            self.views = views
        }
        if parts.count == 8 {
            let window = parts[7].split(separator: ";", omittingEmptySubsequences: false)
            guard window.count == 3, let count = Int(window[1]) else { return nil }
            let areas = window[0].split(separator: ",").compactMap { Double($0) }
            guard areas.count == 9 else { return nil }
            (self.areas, screenCount) = (areas, count)
            for pair in window[2].split(separator: ",") {
                let kv = pair.split(separator: "=")
                guard kv.count == 2, let seconds = Double(kv[1]) else { return nil }
                screens[String(kv[0])] = seconds
            }
        }
    }

    /// CLA-162: the area with the most visible seconds (a tie goes to the first, top left first),
    /// and the screen with the most (a tie goes to the first key). Nil with no visible time.
    var topArea: Int? { visible > 0 ? areas.indices.max { areas[$0] < areas[$1] || (areas[$0] == areas[$1] && $0 > $1) } : nil }
    var topScreen: String? { screens.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key }
}

/// CLA-162 (Jason 15:09 JST 11-20): where the device window is, for `day_active`. The app sends
/// it about once a minute and at each change, nil when the person cannot see the window.
/// Nothing about other apps or the screen's content.
public struct WindowSpot: Equatable, Sendable {
    /// The area of the device's center on its screen, a 3x3 grid: 0 top left, 1 top, … 8 bottom right.
    public var area: Int
    /// That screen is the main screen (the one with the menu bar), and how many screens there are.
    public var mainScreen: Bool, screens: Int
    /// That screen's size in points, and its display number, so two screens of one size count apart.
    public var width: Int, height: Int, display: Int

    public init(area: Int, mainScreen: Bool, screens: Int, width: Int, height: Int, display: Int = 0) {
        (self.area, self.mainScreen, self.screens) = (min(8, max(0, area)), mainScreen, screens)
        (self.width, self.height, self.display) = (width, height, display)
    }

    var screenKey: String { "\(mainScreen ? 1 : 0)x\(width)x\(height)x\(display)" }
    static let areaNames = ["top_left", "top", "top_right", "left", "center", "right", "bottom_left", "bottom", "bottom_right"]
}

/// The longest gap between two window reports that counts: the app reports about once a minute,
/// so a longer gap is a Mac sleep.
let windowGapLimit = 90.0

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
