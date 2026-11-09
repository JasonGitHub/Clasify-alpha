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

    @FocusState private var focused: Bool

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
            ClickWheel(input: input, color: state.deviceColor, catchesScroll: interactive, movesBar: state.wheelMovesBar, pressed: pressed)
        }
        // The mockup's 24.8 point padding starts inside the 1 point border.
        .padding(.top, 25.8)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
        .background { device(state.deviceColor) }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .repeat]) { press in
            // Keys with Command, Option or Control belong to the menus.
            guard press.modifiers.isDisjoint(with: [.command, .option, .control]),
                  let action = Self.action(for: press.key)
            else { return .ignored }
            if press.phase == .repeat && !Self.repeats(action) { return .handled }
            input(action)
            return .handled
        }
        .onAppear { focused = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Clasify pocket player. Arrow keys scroll, Return selects, Escape goes back, Space plays or pauses, S and R change shuffle and repeat.")
    }

    /// The device body: silver, or black (round 8, card Z), with a light line inside the top
    /// edge and fainter ones at the sides.
    private func device(_ color: DeviceColor) -> some View {
        let black = color == .black
        let shape = RoundedRectangle(cornerRadius: 34)
        return shape
            .fill(LinearGradient(stops: black ? Self.blackBody : Self.silverBody, startPoint: .top, endPoint: .bottom))
            .overlay {
                if black {  // slightly darker sides
                    shape.fill(LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.16), location: 0), .init(color: .white.opacity(0.05), location: 0.2),
                            .init(color: .white.opacity(0.07), location: 0.5), .init(color: .white.opacity(0.05), location: 0.8),
                            .init(color: .black.opacity(0.16), location: 1),
                        ],
                        startPoint: .leading, endPoint: .trailing))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 33).strokeBorder(Color.white.opacity(black ? 0.12 : 0.5), lineWidth: 1).padding(1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 33).strokeBorder(Color.white.opacity(black ? 0.35 : 1), lineWidth: 1).padding(1)
                    .mask(LinearGradient.vertical(.white, .clear, .clear))
            }
            .overlay { shape.strokeBorder(Color(hex: black ? 0x1c1c1c : 0x9c9c9c), lineWidth: 1) }
            .shadow(color: black ? .black.opacity(0.45) : Color(hex: 0x1e1e1e, opacity: 0.3), radius: 20, y: 20)
    }

    static var silverBody: [Gradient.Stop] { [
        .init(color: Color(hex: 0xf4f4f4), location: 0), .init(color: Color(hex: 0xe4e4e4), location: 0.55),
        .init(color: Color(hex: 0xc8c8c8), location: 1),
    ] }
    static var blackBody: [Gradient.Stop] { [
        .init(color: Color(hex: 0x6c6b6e), location: 0), .init(color: Color(hex: 0x626164), location: 0.22),
        .init(color: Color(hex: 0x555457), location: 0.5), .init(color: Color(hex: 0x3f3f3f), location: 0.7),
        .init(color: Color(hex: 0x2c2c2c), location: 0.86), .init(color: Color(hex: 0x212121), location: 1),
    ] }

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
