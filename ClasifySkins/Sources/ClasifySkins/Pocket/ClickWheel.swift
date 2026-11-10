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
    /// When the waiting comet starts, on the color pick until the first turn (card AW, change 200).
    var cometFrom: Double?
    /// On the color pick a light follows the thumb (change 202). `turns` is
    /// `AppState.colorTurns`: a step from the trackpad or a key moves the light 24°.
    var followsThumb = false
    var turns = 0
    /// The labels that glow for a first-time hint (card BA, change 151), and when they started.
    /// The tour's step 2 lights Previous and Next together (card BA.1, change 199).
    var label: LabelGlow?

    struct LabelGlow {
        var zones: [Zone]
        var from: Double
    }

    init(
        input: @escaping @MainActor (Action) -> Void, color: DeviceColor = .silver, catchesScroll: Bool = true,
        movesBar: Bool = false, glowFrom: Double? = nil, cometFrom: Double? = nil, followsThumb: Bool = false,
        turns: Int = 0, label: LabelGlow? = nil, pressed: Zone? = nil
    ) {
        self.input = input
        self.color = color
        self.catchesScroll = catchesScroll
        self.movesBar = movesBar
        self.glowFrom = glowFrom
        self.cometFrom = cometFrom
        self.followsThumb = followsThumb
        self.turns = turns
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
    static let detent = 24.0, clickSlop = 12.0

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
        /// The light is under this drag's thumb (change 202).
        var anchored = false
    }

    /// The light under the thumb (change 202): its angle, clockwise from 3 o'clock and not
    /// wrapped, so a glide never goes the long way; its direction; when it came and last moved.
    struct ThumbLight: Equatable {
        var angle: Double
        var clockwise = true
        var from: Double
        var last: Double
    }

    @State private var turn: Turn?
    @State private var light: ThumbLight?
    @State private var pressed: Zone?
    @State private var hovered: Zone?

    var body: some View {
        lights(face)
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
            // Flat white, as in the photo: no gradient and no ring line. The mockup's shadows
            // are a faint 1 point line around it and a white line under it.
            Circle()
                .fill(Color(hex: black ? 0x2f2f2f : 0xfefefe))
                .background { Circle().fill(Color.white.opacity(black ? 0.12 : 0.8)).offset(y: 1).blur(radius: 0.5) }
                .background { Circle().fill(Color.black.opacity(black ? 0.25 : 0.06)).padding(-1) }
                .frame(width: Self.size, height: Self.size)
            key(.menu) { Text("MENU").font(.helvetica(14, weight: .medium)).tracking(0.7) }
            key(.prev) { IconView(.prev, width: 19.8, height: 10.2) }
            key(.next) { IconView(.next, width: 19.8, height: 10.2) }
            key(.play) { IconView(.playPause, width: 24.6, height: 9.6) }
            comets
            center
        }
        .frame(width: Self.size, height: Self.size)
    }

    /// The color pick's lights: the waiting comet until the first touch, then the light under
    /// the thumb (changes 200 and 202).
    @ViewBuilder private var comets: some View {
        if let cometFrom, light == nil {
            WaitingComet(from: cometFrom)
                .transition(.opacity.animation(.easeOut(duration: ColorPick.waitingOut)))
        }
        if followsThumb, let light { ThumbComet(light: light) }
    }

    /// The light follows the steps, goes off the pick and goes when it has faded.
    private func lights(_ content: some View) -> some View {
        content
            .onChange(of: followsThumb) { _, follows in
                if !follows { light = nil }  // off the color pick, the light goes at once
            }
            .onChange(of: turns) { old, new in
                // A trackpad or key step. A drag moves the light itself.
                if followsThumb && turn == nil { moveLight(by: Double(new - old) * Self.detent, to: nil, anchor: false) }
            }
            .task(id: light?.last) {
                // The light has faded out: it goes, and the next move starts a new one.
                guard let last = light?.last else { return }
                try? await Task.sleep(for: .seconds(ColorPick.hold + ColorPick.fadeOut + 0.1))
                if light?.last == last { light = nil }
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
                    .foregroundStyle(Color(hex: hovered == zone || pressed == zone ? (black ? 0xbdbdbd : 0x6c7076) : (black ? 0xf2f2f2 : 0x9f9f9f)))
            }
        }
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: rect.minY)
    }

    private var center: some View {
        // Pressed in, as in the photo: dark at the top, with a faint inner shadow and no ring
        // line. Pressed, it gets a little darker.
        let down = pressed == .center
        let (top, bottom): (UInt32, UInt32) = switch (black, down) {
        case (false, false): (0xc8c8c8, 0xe9e9e9)
        case (false, true): (0xbcbcbc, 0xdcdcdc)
        case (true, false): (0x38383a, 0x706e71)
        case (true, true): (0x2e2e30, 0x636164)
        }
        return Circle()
            .fill(LinearGradient.vertical(Color(hex: top), Color(hex: bottom)))
            .overlay {
                Circle().stroke(Color.black.opacity(black ? 0.35 : 0.12), lineWidth: 2).blur(radius: 1).offset(y: 1)
                    .clipShape(Circle())
            }
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
        if followsThumb && delta != 0 {
            moveLight(by: delta, to: angle, anchor: !t.anchored)
            t.anchored = true
        }
        t.turned += delta
        t.moved += abs(delta)
        while t.turned >= Self.detent { t.turned -= Self.detent; input(.wheel(1)) }
        while t.turned <= -Self.detent { t.turned += Self.detent; input(.wheel(-1)) }
        if t.moved > Self.clickSlop { pressed = nil }
        turn = t
    }

    /// Moves the light by `delta` degrees. A new light starts at `angle`, under the thumb, or
    /// for a step with no thumb at 12 o'clock. With `anchor`, the first move of a drag, a light
    /// that still shows goes under the thumb the short way, so it never lags behind it.
    private func moveLight(by delta: Double, to angle: Double?, anchor: Bool) {
        guard delta != 0 else { return }
        let now = Date.timeIntervalSinceReferenceDate
        if var l = light {
            if anchor, let angle {
                var gap = (angle - l.angle).truncatingRemainder(dividingBy: 360)
                if gap > 180 { gap -= 360 } else if gap < -180 { gap += 360 }
                l.angle += gap
            } else {
                l.angle += delta
            }
            l.clockwise = delta > 0; l.last = now
            light = l
        } else {
            light = ThumbLight(angle: angle ?? -90, clockwise: delta > 0, from: now, last: now)
        }
    }

    private func ended(_ value: DragGesture.Value) {
        let start = Self.zone(at: value.startLocation)
        let turned = (turn?.moved ?? 0) > Self.clickSlop
        if let start, !turned, Self.zone(at: value.location) == start { input(start.action) }
        turn = nil
        pressed = nil
    }
}

/// A wheel label that a first-time hint lights (card BA, change 151): soft blue #3f8de0 with a
/// #5aa3f0 glow in three layers at the pulse peak, 95%, 65% and 40% (change 205): the mock's
/// drop-shadow 4/10/18 px = radius 2/5/9. It pulses between full and 55% every 2.4 s, as the
/// center glow does. With Reduce Motion, it stays full.
private struct GlowingLabel<Label: View>: View {
    let from: Double
    let label: Label
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.animationTime) private var fixedTime

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || fixedTime != nil)) { context in
            let t = (fixedTime ?? context.date.timeIntervalSinceReferenceDate) - from
            label
                .foregroundStyle(Color(hex: 0x3f8de0))
                .shadow(color: Color(hex: 0x5aa3f0, opacity: 0.95), radius: 2)
                .shadow(color: Color(hex: 0x5aa3f0, opacity: 0.65), radius: 5)
                .shadow(color: Color(hex: 0x5aa3f0, opacity: 0.4), radius: 9)
                .opacity(reduceMotion ? 1 : 0.775 + 0.225 * cos(2 * .pi * max(t, 0) / Hello.pulse))
        }
        .allowsHitTesting(false)
    }
}
