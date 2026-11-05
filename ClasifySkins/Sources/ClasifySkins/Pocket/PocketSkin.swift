import ClasifyCore
import SwiftUI

/// The Pocket skin from the mockup: a white pocket player with an LCD and a click wheel.
/// It renders `state` and sends input actions. It holds no logic.
public struct PocketSkin: View {
    /// The device's size in points, as in the mockup.
    public static let size = CGSize(width: 300, height: 540)

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
        VStack(spacing: 32) {
            PocketScreen(state: state, input: input)
            ClickWheel(input: input, catchesScroll: interactive, pressed: pressed)
        }
        // The mockup's padding starts inside the 1 point border.
        .padding(.vertical, 25)
        .padding(.horizontal, 21)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 28)
                .fill(LinearGradient(
                    stops: [
                        .init(color: .white, location: 0), .init(color: Color(hex: 0xeef0f2), location: 0.6),
                        .init(color: Color(hex: 0xdfe2e6), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom))
                .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(Color(hex: 0xa9b0b8), lineWidth: 1) }
                .shadow(color: Color(hex: 0x28323c, opacity: 0.3), radius: 20, y: 20)
        }
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

    /// Clicks when the Clicker setting is on, then sends the action.
    private func input(_ action: Action) {
        if state.clicker { Clicker.shared.click() }
        send(action)
    }
}
