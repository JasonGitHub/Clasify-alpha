import SwiftUI

/// One side of the screen slide. `side` 1 is the incoming screen before it slides in, -1 the
/// outgoing screen after it slides out, and 0 a screen in place.
/// It reads the direction from the environment, not from its own value: a removed screen keeps
/// the transition of its last update, which has the direction of the push that showed it.
struct Push: ViewModifier {
    let side: Double
    @Environment(\.navForward) private var forward

    /// The offset as a part of the width: on a push forward, the new screen comes from the
    /// right (+1) and the old one goes to the left (-1). A way back is the mirror.
    static func offset(side: Double, forward: Bool) -> Double { forward ? side : -side }

    func body(content: Content) -> some View {
        let part = Self.offset(side: side, forward: forward)
        content.visualEffect { view, proxy in view.offset(x: part * proxy.size.width) }
    }
}

private struct NavForwardKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// True when the last screen change opened a screen, false on a way back.
    var navForward: Bool {
        get { self[NavForwardKey.self] }
        set { self[NavForwardKey.self] = newValue }
    }
}
