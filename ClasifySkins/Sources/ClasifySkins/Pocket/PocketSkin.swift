import ClasifyCore
import SwiftUI

/// The Pocket skin from the mockup: a silver or black pocket player with an LCD and a click wheel.
/// It renders `state` and sends input actions. It holds no logic.
public struct PocketSkin: View {
    /// The device's size in points, as in the mockup: the photo's shape.
    public static let size = CGSize(width: 366, height: 613)

    let state: AppState
    let send: @MainActor (Action) -> Void
    /// False in snapshot tests. See `ClickWheel.catchesScroll`.
    var interactive = true
    /// A wheel button drawn pressed, for snapshot tests.
    var pressed: ClickWheel.Zone?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The small device on a setup screen: no glow, no comet, no keys and no drop shadow.
    @Environment(\.pocketPreview) private var preview

    public init(state: AppState, send: @escaping @MainActor (Action) -> Void) {
        self.state = state
        self.send = send
    }

    init(state: AppState, interactive: Bool, pressed: ClickWheel.Zone? = nil) {
        self.state = state
        self.send = { _ in }
        self.interactive = interactive
        self.pressed = pressed
    }

    public var body: some View {
        // The bezel and the wheel, centered, with the mockup's 55.8 point gap between them.
        VStack(spacing: 55.8) {
            PocketScreen(state: state, input: input)
            ClickWheel(
                input: input, color: state.shownColor, catchesScroll: interactive, movesBar: state.wheelMovesBar,
                glowFrom: glowFrom, cometFrom: cometFrom, followsThumb: !preview && state.top.screen == .color,
                turns: state.colorTurns, label: labelGlow, pressed: pressed)
                .animation(.easeInOut(duration: ColorPick.colorFade), value: state.shownColor)
        }
        // The mockup's 24.8 point padding starts inside the 1 point border.
        .padding(.top, 25.8)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
        .background {
            // A new color crossfades in 0.45 s (card AW, changes 150 and 203).
            ZStack {
                device(.silver).opacity(state.shownColor == .silver ? 1 : 0)
                device(.black).opacity(state.shownColor == .black ? 1 : 0)
            }
            .animation(.easeInOut(duration: ColorPick.colorFade), value: state.shownColor)
        }
        // Keys come through a window-level monitor, not SwiftUI focus (CLA-79).
        .background { if interactive && !preview { KeyCatcher { key($0, repeated: $1) } } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Clasify pocket player. Arrow keys scroll, Return selects, Escape goes back, Space plays or pauses, S and R change shuffle and repeat.")
    }

    /// The center glows on Hello from 13 s (from the start with Reduce Motion), and on the color
    /// pick from the first turn.
    private var glowFrom: Double? {
        if preview { return nil }
        switch state.top.screen {
        case .hello: return state.helloAt + (reduceMotion ? 0 : Hello.glowAt)
        case .color where state.colorTurnAt > 0: return state.colorTurnAt
        default: return nil
        }
    }

    /// The wheel label of the first-time hint that shows (card BA, change 151).
    private var labelGlow: ClickWheel.LabelGlow? {
        guard !preview, let hint = state.hint else { return nil }
        let zones: [ClickWheel.Zone] = switch hint {
        case .menu, .tourMenu: [.menu]
        case .playPause, .tourPlay: [.play]
        case .next: [.next]
        case .tourNext: [.prev, .next]
        }
        return ClickWheel.LabelGlow(zones: zones, from: state.hintAt)
    }

    /// The waiting comet goes over the wheel on the color pick until the first turn (change
    /// 200). Not with Reduce Motion.
    private var cometFrom: Double? {
        guard !preview, !reduceMotion, state.top.screen == .color, state.colorTurnAt == 0 else { return nil }
        return state.colorAt
    }

    /// The device body, card BH (CLA-95): a base gradient, then the top lip and bottom roll, then
    /// darker sides, as the mockup's three `bodyBg` layers. A dark edge line and the drop shadow.
    private func device(_ color: DeviceColor) -> some View {
        let black = color == .black
        let shape = RoundedRectangle(cornerRadius: 34)
        return shape
            .fill(LinearGradient(stops: black ? Self.blackBody : Self.silverBody, startPoint: .top, endPoint: .bottom))
            .overlay { shape.fill(LinearGradient(stops: Self.lip(black), startPoint: .top, endPoint: .bottom)) }
            .overlay { shape.fill(LinearGradient(stops: Self.sides(black), startPoint: .leading, endPoint: .trailing)) }
            .overlay { shape.strokeBorder(Color.black.opacity(black ? 0.6 : 0.3), lineWidth: 1) }
            .shadow(color: preview ? .clear : black ? .black.opacity(0.45) : Color(hex: 0x1e1e1e, opacity: 0.3), radius: 20, y: 20)
    }

    static var silverBody: [Gradient.Stop] { [
        .init(color: Color(hex: 0xdcdcdc), location: 0), .init(color: Color(hex: 0xdbdbdb), location: 0.5),
        .init(color: Color(hex: 0xc6c6c6), location: 0.72), .init(color: Color(hex: 0xb4b4b4), location: 0.92),
    ] }
    static var blackBody: [Gradient.Stop] { [
        .init(color: Color(hex: 0x636265), location: 0), .init(color: Color(hex: 0x5f5e61), location: 0.5),
        .init(color: Color(hex: 0x3a3a3b), location: 0.72), .init(color: Color(hex: 0x2f2f30), location: 0.92),
    ] }

    /// The top lip (a dark hairline, then a white shine that fades by 4.5%) and the bottom roll.
    static func lip(_ black: Bool) -> [Gradient.Stop] {
        let top: [Gradient.Stop] = [
            .init(color: .black.opacity(0.3), location: 0), .init(color: .white.opacity(black ? 0.3 : 0.55), location: 0.008),
            .init(color: .white.opacity(black ? 0.18 : 0.35), location: 0.025), .init(color: .white.opacity(0), location: 0.045),
            .init(color: .white.opacity(0), location: 0.89),
        ]
        let bottom: [Gradient.Stop] = black
            ? [.init(color: .black.opacity(0.15), location: 0.94), .init(color: .black.opacity(0.35), location: 1)]
            : [
                .init(color: .black.opacity(0.1), location: 0.93), .init(color: .black.opacity(0.3), location: 0.975),
                .init(color: .black.opacity(0.5), location: 1),
            ]
        return top + bottom
    }

    /// The darker sides, fading out by 9% of the width.
    static func sides(_ black: Bool) -> [Gradient.Stop] {
        let (left, nearLeft, nearRight, right) = black ? (0.45, 0.12, 0.15, 0.45) : (0.17, 0.05, 0.07, 0.2)
        return [
            .init(color: .black.opacity(left), location: 0), .init(color: .black.opacity(nearLeft), location: 0.04),
            .init(color: .black.opacity(0), location: 0.09), .init(color: .black.opacity(0), location: 0.9),
            .init(color: .black.opacity(nearRight), location: 0.95), .init(color: .black.opacity(right), location: 1),
        ]
    }

    /// The mockup's keys: arrows turn the wheel and skip, Return selects, Escape and Delete go back,
    /// Space plays, S and R change shuffle and repeat.
    static func action(for key: KeyEquivalent) -> Action? {
        switch key {
        case .upArrow: .wheel(-1)
        case .downArrow: .wheel(1)
        case .return: .select
        case .escape, .delete: .menu
        case .space: .play
        case .rightArrow: .next
        case .leftArrow: .prev
        case "s", "S": .toggleShuffle
        case "r", "R": .cycleRepeat
        default: nil
        }
    }

    /// Sends the action for a key. Returns false for a key the device does not use, so it goes on
    /// to the menus.
    private func key(_ key: KeyEquivalent, repeated: Bool) -> Bool {
        guard let action = Self.action(for: key) else { return false }
        if !repeated || Self.repeats(action) { input(action) }
        return true
    }

    /// A held arrow key turns the wheel on. A held Space, Return or skip key acts once.
    static func repeats(_ action: Action) -> Bool {
        if case .wheel = action { true } else { false }
    }

    /// A button press clicks when the Clicker setting is on. A wheel step clicks in the app,
    /// and only when it moved something. Then it sends the action.
    private func input(_ action: Action) {
        if state.clicker, !Self.repeats(action) { Clicker.shared.click() }
        send(action)
    }
}
