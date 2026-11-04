import ClasifyCore
import SwiftUI

/// The click wheel. A turn sends `.wheel` detents. MENU, prev, next, play and the center
/// button send their actions. It only maps input to actions.
struct ClickWheel: View {
    let input: @MainActor (Action) -> Void
    /// False in snapshot tests, which cannot draw the AppKit scroll view.
    var catchesScroll = true

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

    static let size: CGFloat = 196
    /// A turn of this many degrees sends one detent. A turn of more than `clickSlop` cancels the click.
    static let detent = 24.0, clickSlop = 12.0

    /// The mockup's button rectangles, in the wheel's coordinates.
    private static let zones: [(Zone, CGRect)] = [
        (.menu, CGRect(x: 68, y: 12, width: 60, height: 30)),
        (.prev, CGRect(x: 8, y: 78, width: 40, height: 40)),
        (.next, CGRect(x: 148, y: 78, width: 40, height: 40)),
        (.play, CGRect(x: 73, y: 154, width: 50, height: 32)),
    ]
    private static let centerRadius: CGFloat = 34

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
        ZStack(alignment: .topLeading) {
            Circle()
                .fill(RadialGradient(
                    stops: [
                        .init(color: .white, location: 0), .init(color: Color(hex: 0xe9ecef), location: 0.55),
                        .init(color: Color(hex: 0xdadee3), location: 1),
                    ],
                    center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0, endRadius: 161))
                .overlay { Circle().strokeBorder(Color(hex: 0xc3c9d0), lineWidth: 1) }
                .frame(width: Self.size, height: Self.size)
            key(.menu) { Text("MENU").font(.helvetica(11, bold: true)).tracking(1) }
            key(.prev) { IconView(.prev, width: 18, height: 12) }
            key(.next) { IconView(.next, width: 18, height: 12) }
            key(.play) { IconView(.playPause, width: 20, height: 12) }
            center
        }
        .frame(width: Self.size, height: Self.size)
        .overlay { if catchesScroll { ScrollCatcher { input(.wheel($0)) }.clipShape(Circle()) } }
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

    private func key<Label: View>(_ zone: Zone, @ViewBuilder label: () -> Label) -> some View {
        let rect = Self.zones.first { $0.0 == zone }?.1 ?? .zero
        return label()
            .foregroundStyle(Color(hex: hovered == zone || pressed == zone ? 0x3f454d : 0x7d838c))
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }

    private var center: some View {
        let down = pressed == .center
        let light = Color(hex: 0xf3f5f7), dark = Color(hex: 0xdfe3e8)
        return Circle()
            .fill(LinearGradient.vertical(down ? dark : light, down ? light : dark))
            .overlay { Circle().strokeBorder(Color(hex: 0xc3c9d0), lineWidth: 1) }
            .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
            .frame(width: Self.centerRadius * 2, height: Self.centerRadius * 2)
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
