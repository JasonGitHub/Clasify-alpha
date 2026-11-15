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
    /// For tests: the color fade drawn at this fraction, from 0 (Silver) to 1 (Black).
    var fade: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The small device on a setup screen: no glow, no fingertip dot, no keys and no drop shadow.
    @Environment(\.pocketPreview) private var preview
    /// SPIKE (CLA-101): off while the 3D flip draws this shadow itself.
    @Environment(\.pocketDropShadow) private var dropShadow
    /// Changes 289 and 290: a color spin sets the color, with no fade.
    @Environment(\.spinBlack) private var spinBlack

    public init(state: AppState, send: @escaping @MainActor (Action) -> Void) {
        self.state = state
        self.send = send
    }

    init(state: AppState, interactive: Bool, pressed: ClickWheel.Zone? = nil, fade: Double? = nil) {
        self.state = state
        self.send = { _ in }
        self.interactive = interactive
        self.pressed = pressed
        self.fade = fade
    }

    public var body: some View {
        // The bezel and the wheel, centered, with the mockup's 55.8 point gap between them.
        VStack(spacing: 55.8) {
            PocketScreen(state: state, input: input)
            ClickWheel(
                input: input, color: color, catchesScroll: interactive, movesBar: state.wheelMovesBar,
                glowFrom: glowFrom, fingerFrom: fingerFrom, label: labelGlow, pressed: pressed)
                .animation(colorFade, value: color)
        }
        // The mockup's 24.8 point padding starts inside the 1 point border.
        .padding(.top, 25.8)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
        .background {
            // A new color crossfades in 0.45 s (card AW, changes 150 and 203).
            Bodies(black: fade ?? (color == .black ? 1 : 0), shadow: !preview && dropShadow)
                .animation(colorFade, value: color)
        }
        // Keys come through a window-level monitor, not SwiftUI focus (CLA-79).
        .background { if interactive && !preview { KeyCatcher { key($0, repeated: $1) } } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "myPod pocket player. Arrow keys scroll, Return selects, Escape goes back, Space plays or pauses, S and R change shuffle and repeat.")
    }

    /// The device's color: the state's, or a color spin's (changes 289 and 290).
    private var color: DeviceColor { spinBlack.map { $0 ? .black : .silver } ?? state.shownColor }
    /// A new color fades in, except during a spin: the spin changes it.
    private var colorFade: Animation? { spinBlack == nil ? .easeInOut(duration: ColorPick.colorFade) : nil }

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

    /// The fingertip dot shows the turn on the color pick until the first turn (card BQ, change
    /// 287). Not with Reduce Motion, as the AW comet before it.
    private var fingerFrom: Double? {
        guard !preview, !reduceMotion, state.top.screen == .color, state.colorTurnAt == 0 else { return nil }
        return state.colorAt
    }

    /// The device body, card BL v3 (CLA-101): BL's tone, side shade and top line, its 1 point
    /// edge and the matte grain.
    static func device(_ color: DeviceColor) -> some View {
        let black = color == .black
        let shape = RoundedRectangle(cornerRadius: 34)
        return BL.body(black: black)
            .overlay { shape.strokeBorder(Color.black.opacity(BL.edge(black: black)), lineWidth: 1) }
            .overlay {
                Grain.image.resizable(resizingMode: .tile)
                    .clipShape(RoundedRectangle(cornerRadius: 33))
                    .padding(1)
                    .opacity(BL.grain(black: black))
                    .blendMode(.overlay)
            }
            .compositingGroup()  // so its opacity in the color fade applies to the body as a whole
    }

    /// How much lower than the device the shadow's shape starts.
    static let shadowDrop: CGFloat = 20

    /// The drop shadow's color at a point of the color fade: #1e1e1e at 30% for Silver, black at
    /// 45% for Black.
    static func shadowColor(_ black: Double) -> Color {
        let gray = Double(0x1e) / 255 * (1 - black)
        return Color(.sRGB, red: gray, green: gray, blue: gray, opacity: 0.3 + 0.15 * black)
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

/// The two device bodies and their one drop shadow, at a point of the color fade (CLA-100).
/// The Silver body stays opaque, and the Black body fades in over it, so the desktop never
/// shows through. One shadow sits under both and changes its color, so Black has no double shadow.
private struct Bodies: View, Animatable {
    /// 0 is Silver, 1 is Black.
    var black: Double
    /// The drop shadow shows: not on a setup screen's small device, nor while the 3D flip draws it.
    let shadow: Bool

    // `Animatable` is nonisolated while `View` is on the main actor. `black` is a plain Double
    // in a value type, so reading and writing it from any isolation is safe.
    nonisolated var animatableData: Double {
        get { black }
        set { black = newValue }
    }

    var body: some View {
        ZStack {
            if shadow {
                // The shadow comes from a hidden copy of the body that starts lower, so it does not
                // reach above the device into the window's small top margin (CLA-94). The opaque
                // body above always covers it.
                RoundedRectangle(cornerRadius: 34).fill(Color.black).padding(.top, PocketSkin.shadowDrop)
                    .shadow(color: PocketSkin.shadowColor(black), radius: 20, y: 20)
            }
            // Hidden once the fade ends, so no Silver shows at Black's soft outer edge.
            PocketSkin.device(.silver).opacity(black < 1 ? 1 : 0)
            PocketSkin.device(.black).opacity(black)
        }
    }
}
