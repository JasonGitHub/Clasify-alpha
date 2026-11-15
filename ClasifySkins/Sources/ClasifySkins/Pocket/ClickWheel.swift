import ClasifyCore
import SwiftUI

/// The click wheel. A turn sends `.wheel` detents. MENU, prev, next, play and the center
/// button send their actions. It only maps input to actions.
struct ClickWheel: View {
    let input: @MainActor (Action) -> Void
    /// Silver: a white wheel with gray labels. Black: a dark gray wheel with near white labels.
    var color = DeviceColor.silver
    /// False in snapshot tests, which cannot draw the AppKit scroll view.
    var catchesScroll = true
    /// The wheel moves a bar, not a list: a trackpad scroll goes the other way (CLA-48).
    var movesBar = false
    /// When the center starts to glow: on Hello (card AT, change 166) and after the first turn
    /// on the color pick (card AW, change 150). Nil: no glow.
    var glowFrom: Double?
    /// When the fingertip dot's loop starts, on the color pick until the first turn (card BQ,
    /// change 287).
    var fingerFrom: Double?
    /// The labels that glow for a first-time hint (card BA, change 151), and when they started.
    /// The tour's step 2 lights Previous and Next together (card BA.1, change 199).
    var label: LabelGlow?

    struct LabelGlow {
        var zones: [Zone]
        var from: Double

        /// The glow's strength `t` seconds after the hint shows (CLA-86): 0 at the start, 1 at
        /// 1.2 s and 0 again at 2.4 s, then again. Each half is eased as CSS ease-in-out,
        /// cubic-bezier(.42, 0, .58, 1).
        nonisolated static func strength(at t: Double) -> Double {
            let half = Hello.pulse / 2
            let phase = max(t, 0).truncatingRemainder(dividingBy: Hello.pulse)
            return easeInOut(phase < half ? phase / half : 2 - phase / half)
        }

        /// cubic-bezier(.42, 0, .58, 1) at `x`: finds the curve point with that x by bisection,
        /// and returns its y.
        nonisolated static func easeInOut(_ x: Double) -> Double {
            if x <= 0 { return 0 }
            if x >= 1 { return 1 }
            func curve(_ s: Double, _ a: Double, _ b: Double) -> Double {
                3 * (1 - s) * (1 - s) * s * a + 3 * (1 - s) * s * s * b + s * s * s
            }
            var low = 0.0, high = 1.0
            for _ in 0..<32 {
                let mid = (low + high) / 2
                if curve(mid, 0.42, 0.58) < x { low = mid } else { high = mid }
            }
            return curve((low + high) / 2, 0, 1)
        }
    }

    init(
        input: @escaping @MainActor (Action) -> Void, color: DeviceColor = .silver, catchesScroll: Bool = true,
        movesBar: Bool = false, glowFrom: Double? = nil, fingerFrom: Double? = nil, label: LabelGlow? = nil,
        pressed: Zone? = nil
    ) {
        self.input = input
        self.color = color
        self.catchesScroll = catchesScroll
        self.movesBar = movesBar
        self.glowFrom = glowFrom
        self.fingerFrom = fingerFrom
        self.label = label
        _pressed = State(initialValue: pressed)  // a snapshot test draws a pressed button
    }

    /// The parts of the wheel that act as buttons.
    enum Zone {
        case menu, prev, next, play, center

        var action: Action {
            switch self {
            case .menu: .menu
            case .prev: .prev
            case .next: .next
            case .play: .play
            case .center: .select
            }
        }
    }

    static let size: CGFloat = 225
    /// A turn of this many degrees sends one detent. A turn of more than `clickSlop` cancels the click.
    nonisolated static let detent = 24.0
    static let clickSlop = 12.0

    /// The mockup's button rectangles, in the wheel's coordinates.
    private static let zones: [(Zone, CGRect)] = [
        (.menu, CGRect(x: 82.5, y: 4, width: 60, height: 29)),
        (.prev, CGRect(x: 4, y: 92.5, width: 40, height: 40)),
        (.next, CGRect(x: 181, y: 92.5, width: 40, height: 40)),
        (.play, CGRect(x: 87.5, y: 190.4, width: 50, height: 32)),
    ]
    private static let centerRadius: CGFloat = 40.8

    static func zone(at point: CGPoint) -> Zone? {
        let r = hypot(point.x - size / 2, point.y - size / 2)
        if r <= centerRadius { return .center }
        if r > size / 2 { return nil }
        return zones.first { $0.1.contains(point) }?.0
    }

    /// Clockwise is positive, as on the screen, where y grows downward.
    static func angle(of point: CGPoint) -> Double {
        atan2(point.y - size / 2, point.x - size / 2) * 180 / .pi
    }

    private struct Turn {
        var last: Double
        var turned = 0.0
        var moved = 0.0
    }

    @State private var turn: Turn?
    @State private var pressed: Zone?
    @State private var hovered: Zone?

    var body: some View {
        face
            .background { if catchesScroll { ScrollCatcher(movesBar: movesBar) { input(.wheel($0)) } } }
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { changed($0) }.onEnded { ended($0) })
            .onContinuousHover { phase in
                if case .active(let point) = phase { hovered = Self.zone(at: point) } else { hovered = nil }
            }
            .accessibilityElement()
            .accessibilityLabel("Click wheel")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: input(.wheel(1))
                case .decrement: input(.wheel(-1))
                @unknown default: break
                }
            }
            .accessibilityAction(named: "Select") { input(.select) }
            .accessibilityAction(named: "Menu") { input(.menu) }
            .accessibilityAction(named: "Play or pause") { input(.play) }
            .accessibilityAction(named: "Next track") { input(.next) }
            .accessibilityAction(named: "Previous track") { input(.prev) }
    }

    /// The wheel, its labels, the lights and the center.
    private var face: some View {
        ZStack(alignment: .topLeading) {
            // Card BL v3: Silver has a light gradient and thin rings; Black is flat #202123. Both
            // have a soft shade at the hole and the rim.
            Circle()
                .fill(BL.wheel(black: black))
                .overlay { Circle().fill(BL.wheelShade(black: black, radius: Self.size / 2)) }
                .overlay { Circle().strokeBorder(Color.black.opacity(BL.wheelInnerRing(black: black)), lineWidth: 1) }
                .background { Circle().fill(Color.black.opacity(BL.wheelRing(black: black))).padding(-0.5) }
                .frame(width: Self.size, height: Self.size)
            key(.menu) { Text("MENU").font(.helvetica(14, weight: .medium)).tracking(0.7) }
            key(.prev) { IconView(.prev, width: 19.8, height: 10.2) }
            key(.next) { IconView(.next, width: 19.8, height: 10.2) }
            key(.play) { IconView(.playPause, width: 24.6, height: 9.6) }
            finger
            center
        }
        .frame(width: Self.size, height: Self.size)
    }

    /// The color pick's fingertip dot until the first color step (card BQ, change 287). No light
    /// follows the turn (card AW.1, change 236).
    @ViewBuilder private var finger: some View {
        if let fingerFrom {
            FingerDot(from: fingerFrom)
                .transition(.opacity.animation(.easeOut(duration: ColorPick.fingerOut)))
        }
    }

    private var black: Bool { color == .black }

    private func key<Label: View>(_ zone: Zone, @ViewBuilder label: () -> Label) -> some View {
        let rect = Self.zones.first { $0.0 == zone }?.1 ?? .zero
        return Group {
            if let glow = self.label, glow.zones.contains(zone) {
                GlowingLabel(from: glow.from, label: label())
            } else {
                label()
                    .foregroundStyle(Color(hex: hovered == zone || pressed == zone ? (black ? 0xbdbdbd : 0x6c7076) : BL.label(black: black)))
            }
        }
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: rect.minY)
    }

    /// Card BL's flat center, its thin ring and its top line.
    private var center: some View {
        Circle()
            .fill(LinearGradient(stops: BL.center(black: black, down: pressed == .center), startPoint: .top, endPoint: .bottom))
            .overlay { Circle().fill(BL.centerShade(black: black, radius: Self.centerRadius)) }
            .overlay {
                TopCrescent().fill(Color.black.opacity(BL.centerTopLine(black: black)), style: FillStyle(eoFill: true))
                    .clipShape(Circle())
            }
            .background { Circle().fill(Color.black.opacity(BL.centerRing(black: black))).padding(-0.5) }
            .frame(width: Self.centerRadius * 2, height: Self.centerRadius * 2)
            .background { if let glowFrom { CenterGlow(from: glowFrom, radius: Self.centerRadius) } }
            .offset(x: Self.size / 2 - Self.centerRadius, y: Self.size / 2 - Self.centerRadius)
    }

    private func changed(_ value: DragGesture.Value) {
        let start = Self.zone(at: value.startLocation)
        guard start != .center else {  // the center button is a button only, as in the mockup
            pressed = .center
            return
        }
        if turn == nil { pressed = start }
        var t = turn ?? Turn(last: Self.angle(of: value.startLocation))
        let angle = Self.angle(of: value.location)
        var delta = angle - t.last
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        t.last = angle
        t.turned += delta
        t.moved += abs(delta)
        while t.turned >= Self.detent { t.turned -= Self.detent; input(.wheel(1)) }
        while t.turned <= -Self.detent { t.turned += Self.detent; input(.wheel(-1)) }
        if t.moved > Self.clickSlop { pressed = nil }
        turn = t
    }

    private func ended(_ value: DragGesture.Value) {
        let start = Self.zone(at: value.startLocation)
        let turned = (turn?.moved ?? 0) > Self.clickSlop
        if let start, !turned, Self.zone(at: value.location) == start { input(start.action) }
        turn = nil
        pressed = nil
    }
}

/// A wheel label that a first-time hint lights (card BA, change 151): solid soft blue #3f8de0
/// with a #5aa3f0 glow in three layers, 95%, 65% and 40% (change 205): the mock's drop-shadow
/// 4/10/18 px = radius 2/5/9. Only the glow pulses (CLA-86): its radii and opacities scale with
/// `LabelGlow.strength`, so there is no glow at the start of each 2.4 s pulse. With Reduce
/// Motion, the glow stays full.
private struct GlowingLabel<Label: View>: View {
    let from: Double
    let label: Label
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.animationTime) private var fixedTime

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || fixedTime != nil)) { context in
            let t = (fixedTime ?? context.date.timeIntervalSinceReferenceDate) - from
            let p = reduceMotion ? 1 : ClickWheel.LabelGlow.strength(at: t)
            label
                .foregroundStyle(Color(hex: 0x3f8de0))
                .shadow(color: Color(hex: 0x5aa3f0, opacity: 0.95 * p), radius: 2 * p)
                .shadow(color: Color(hex: 0x5aa3f0, opacity: 0.65 * p), radius: 5 * p)
                .shadow(color: Color(hex: 0x5aa3f0, opacity: 0.4 * p), radius: 9 * p)
        }
        .allowsHitTesting(false)
    }
}
