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
                glowFrom: glowFrom, cometFrom: cometFrom, label: labelGlow, pressed: pressed)
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

    /// The device body, card BH (CLA-95): the mockup's two `bodyBg` gradients, the side shades
    /// of `bodyShadow`, the matte grain and the `bodyEdge` line. The face fills the whole shape,
    /// under the edge line too, so no light hairline shows at the edge (the mockup's
    /// background-origin border-box).
    private func device(_ color: DeviceColor) -> some View {
        let black = color == .black
        let shape = RoundedRectangle(cornerRadius: 34)
        let inner = RoundedRectangle(cornerRadius: 33)  // inside the 1 point edge
        return shape
            .fill(LinearGradient(stops: black ? Self.blackBody : Self.silverBody, startPoint: .top, endPoint: .bottom))
            .overlay { shape.fill(LinearGradient(stops: black ? Self.blackRim : Self.silverRim, startPoint: .top, endPoint: .bottom)) }
            .overlay {
                // The side shades: inner shadows that follow the rounded corners.
                ZStack {
                    if black {
                        SideShade(x: 28, blur: 36, color: .black.opacity(0.8))
                        SideShade(x: -30, blur: 40, color: .black.opacity(0.65))
                    } else {
                        SideShade(x: 24, blur: 30, color: .black.opacity(0.36))
                        SideShade(x: -24, blur: 30, color: .black.opacity(0.44))
                    }
                }
                .padding(1)
            }
            .overlay { shape.strokeBorder(Color.black.opacity(black ? 0.38 : 0.3), lineWidth: 1) }
            .overlay {
                // The grain, over the face and under the screen and the wheel.
                Grain.image.resizable(resizingMode: .tile)
                    .clipShape(inner)
                    .padding(1)
                    .opacity(black ? 0.28 : 0.35)
                    .blendMode(.overlay)
            }
            .background {
                // The shadow comes from a hidden copy of the body that starts lower, so it does not
                // reach above the device into the window's small top margin (CLA-94).
                shape.fill(Color.black).padding(.top, Self.shadowDrop)
                    .shadow(color: preview ? .clear : black ? .black.opacity(0.45) : Color(hex: 0x1e1e1e, opacity: 0.3), radius: 20, y: 20)
            }
            .compositingGroup()  // so the hidden copy does not show through during a color crossfade
    }

    /// How much lower than the device the shadow's shape starts.
    static let shadowDrop: CGFloat = 20

    static var silverBody: [Gradient.Stop] { [
        .init(color: Color(hex: 0xdcdcdc), location: 0), .init(color: Color(hex: 0xdbdbdb), location: 0.5),
        .init(color: Color(hex: 0xc6c6c6), location: 0.72), .init(color: Color(hex: 0xb1b1b1), location: 0.92),
        .init(color: Color(hex: 0xb0b0b0), location: 1),
    ] }
    static var blackBody: [Gradient.Stop] { [
        .init(color: Color(hex: 0x69686b), location: 0), .init(color: Color(hex: 0x656467), location: 0.5),
        .init(color: Color(hex: 0x3a3a3b), location: 0.72), .init(color: Color(hex: 0x2f2f30), location: 0.92),
    ] }
    /// The soft top rim, its bright zone from 2.8% to 4%, and the bottom roll. The roll starts
    /// from clear black, so it never mixes through a light gray.
    static var silverRim: [Gradient.Stop] { [
        .init(color: .black.opacity(0.16), location: 0), .init(color: .black.opacity(0.06), location: 0.006),
        .init(color: .white.opacity(0.25), location: 0.016), .init(color: .white.opacity(0.72), location: 0.028),
        .init(color: .white.opacity(0.72), location: 0.04), .init(color: .white.opacity(0), location: 0.06),
        .init(color: .black.opacity(0), location: 0.92), .init(color: .black.opacity(0.12), location: 0.95),
        .init(color: .black.opacity(0.38), location: 0.978), .init(color: .black.opacity(0.62), location: 1),
    ] }
    static var blackRim: [Gradient.Stop] { [
        .init(color: .black.opacity(0.2), location: 0), .init(color: .black.opacity(0.08), location: 0.006),
        .init(color: .white.opacity(0.08), location: 0.016), .init(color: .white.opacity(0.3), location: 0.028),
        .init(color: .white.opacity(0.3), location: 0.04), .init(color: .white.opacity(0), location: 0.06),
        .init(color: .black.opacity(0), location: 0.89), .init(color: .black.opacity(0.15), location: 0.94),
        .init(color: .black.opacity(0.35), location: 1),
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

/// A CSS inset shadow with a spread of -18 at one side of the body (card BH): the shadow of
/// the area outside a hole, which is the body moved by `x` and grown by 18, blurred, and kept
/// inside the body.
private struct SideShade: View {
    let x: CGFloat, blur: CGFloat
    let color: Color
    /// Room around the body, so the blur has the whole shadow to work on.
    private static let room: CGFloat = 80

    var body: some View {
        RoundedRectangle(cornerRadius: 33).fill(.clear)
            .overlay {
                GeometryReader { g in
                    let r = Self.room, spread: CGFloat = 18
                    let box = CGRect(x: r, y: r, width: g.size.width - 2 * r, height: g.size.height - 2 * r)
                    let hole = box.offsetBy(dx: x, dy: 0).insetBy(dx: -spread, dy: -spread)
                    Path { p in
                        p.addRect(CGRect(origin: .zero, size: g.size))
                        p.addRoundedRect(in: hole, cornerSize: CGSize(width: 33 + spread, height: 33 + spread))
                    }
                    .fill(color, style: FillStyle(eoFill: true))
                    .blur(radius: blur / 2)  // a CSS blur of 30 is a SwiftUI radius of 15, as for the drop shadow
                }
                .padding(-Self.room)
            }
            .clipShape(RoundedRectangle(cornerRadius: 33))
    }
}
