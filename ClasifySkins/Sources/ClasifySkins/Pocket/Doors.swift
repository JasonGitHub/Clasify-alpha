import SwiftUI

/// One side of a whole-screen move, between a half screen and a full one. `side` is as in
/// `Push`: 1 is the incoming screen before it comes in, -1 the outgoing screen after it goes,
/// and 0 a screen in place. Most moves push, as `Push` does.
///
/// Between the main menu and Cover Flow (`AppState.navMove` is `.doors`), the menu opens like two doors
/// instead (Round 9, card AE, change 82): the left half (the title bar and the list) slides
/// left and fades out, and the right half (the covers) slides right. Cover Flow is behind
/// them, with no title bar and no names. The names fade in, then the title bar slides down.
/// MENU does the reverse. The views read the stage from `doorsStage`.
///
/// The move runs on a linear animation (`DoorsStage.openTime` or `closeTime`), and this
/// modifier gives each frame its own curves. It reads the direction and the kind of move
/// from the environment, as `Push` does: a removed screen keeps the transition of its last update.
struct ScreenMove: ViewModifier, Animatable {
    var side: Double
    @Environment(\.navForward) private var forward
    @Environment(\.navDoors) private var doors

    // `Animatable` is nonisolated while `ViewModifier` is on the main actor. `side` is a plain
    // Double in a value type, so reading and writing it from any isolation is safe.
    nonisolated var animatableData: Double {
        get { side }
        set { side = newValue }
    }

    func body(content: Content) -> some View {
        let part = doors ? 0 : Push.offset(side: side, forward: forward)
        content
            .environment(\.doorsStage, doors ? DoorsStage(side: side, forward: forward) : DoorsStage())
            .visualEffect { view, proxy in view.offset(x: part * proxy.size.width) }
    }
}

/// Where the doors and Cover Flow's title bar and names are at one moment of the move.
struct DoorsStage: Equatable {
    /// How far the main menu's doors are open: 0 closed, 1 fully open. The left half moves
    /// `open` x 150 points left and fades out; the right half moves the same distance right.
    var open = 0.0
    /// Cover Flow's title bar, in points from its place: -20 is above the screen.
    var headerY = 0.0
    /// The opacity of Cover Flow's album and artist names.
    var names = 1.0

    /// Opening: the doors take 0.25 s, speeding up. The names fade in from 0.45 s to
    /// 0.55 s, and the title bar slides down from 0.5 s to 0.6 s.
    static let openTime = 0.6
    /// Closing: the names go at once and the title bar slides up in 0.1 s. Then the doors
    /// close in 0.25 s, slowing down.
    static let closeTime = 0.35

    /// The mockup's `cubic-bezier(0.55,0,1,0.45)` and `cubic-bezier(0,0.55,0.45,1)`.
    static var easeIn: UnitCurve { .bezier(startControlPoint: UnitPoint(x: 0.55, y: 0), endControlPoint: UnitPoint(x: 1, y: 0.45)) }
    static var easeOut: UnitCurve { .bezier(startControlPoint: UnitPoint(x: 0, y: 0.55), endControlPoint: UnitPoint(x: 0.45, y: 1)) }

    init() {}

    /// The stage of one screen in the move. A negative `side` is the screen that goes, a
    /// positive one the screen that comes. On the way in (`forward`) the main menu goes and
    /// Cover Flow comes; on the way back, the other way round.
    init(side: Double, forward: Bool) {
        func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
        let going = side < 0
        switch (forward, going) {
        case (true, true):  // the main menu opens
            let t = Self.openTime * abs(side)
            open = Self.easeIn.value(at: clamp(t / 0.25))
        case (true, false):  // Cover Flow, behind the doors
            let t = Self.openTime * (1 - side)
            headerY = t < 0.5 ? -20 : -20 * (1 - Self.easeOut.value(at: clamp((t - 0.5) / 0.1)))
            names = clamp((t - 0.45) / 0.1)
        case (false, true):  // Cover Flow, before the doors close over it
            let t = Self.closeTime * abs(side)
            headerY = -20 * Self.easeIn.value(at: clamp(t / 0.1))
            names = t > 0 ? 0 : 1
        case (false, false):  // the main menu closes
            let t = Self.closeTime * (1 - side)
            open = 1 - Self.easeOut.value(at: clamp((t - 0.1) / 0.25))
        }
    }
}

private struct NavDoorsKey: EnvironmentKey {
    static let defaultValue = false
}

private struct DoorsStageKey: EnvironmentKey {
    static let defaultValue = DoorsStage()
}

extension EnvironmentValues {
    /// True when the last whole-screen move was between the main menu and Cover Flow.
    var navDoors: Bool {
        get { self[NavDoorsKey.self] }
        set { self[NavDoorsKey.self] = newValue }
    }

    /// The stage of the doors move for the views of one screen. In place, nothing moves.
    var doorsStage: DoorsStage {
        get { self[DoorsStageKey.self] }
        set { self[DoorsStageKey.self] = newValue }
    }
}

/// One half of the main menu in the doors move: the left half (`side` -1) slides left and
/// fades out, the right half (`side` 1) slides right.
struct DoorHalf: ViewModifier {
    let side: Double
    @Environment(\.doorsStage) private var stage

    func body(content: Content) -> some View {
        content
            .offset(x: side * stage.open * Pocket.paneWidth)
            .opacity(side < 0 ? 1 - stage.open : 1)
    }
}

/// Cover Flow's title bar in the doors move: above the screen until it slides down.
struct DoorsHeader: ViewModifier {
    @Environment(\.doorsStage) private var stage

    func body(content: Content) -> some View {
        content.offset(y: stage.headerY)
    }
}
