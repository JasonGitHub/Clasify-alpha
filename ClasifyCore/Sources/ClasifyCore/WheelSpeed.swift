/// A fast wheel moves further, as in the mockup. Wheel steps that come less than `gap`
/// seconds apart build a streak, and a longer streak moves more rows for each step:
/// 1, then 2 after 5 quick steps, 3 after 9, and 4 after 15.
/// `AppState` keeps one, and the reducer applies it to wheel steps on lists.
public struct WheelSpeed: Equatable, Sendable {
    public static let gap = 0.11

    private var last = -Double.infinity
    private var streak = 0

    public init() {}

    /// The rows that a wheel step at `time` (in seconds) moves.
    public mutating func rows(at time: Double) -> Int {
        streak = time - last < Self.gap ? streak + 1 : 0
        last = time
        return streak > 14 ? 4 : streak > 8 ? 3 : streak > 4 ? 2 : 1
    }
}
