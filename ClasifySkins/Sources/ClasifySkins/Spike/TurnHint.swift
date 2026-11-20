import SwiftUI

/// CLA-163, card CE.1 (from BZ D), a trial behind `hints.trial`: a hint of the tour, under
/// the device, a ⌘ key and the words "Hold ⌘ and drag to turn". The app puts this view in its
/// own clear window, its top at the device's bottom edge, while the tour shows the hint
/// (`Hint.tourTurn`). No timer ends it. The timeline, in seconds from when it shows: all fades
/// in place in 0.5 s, with no rise (Jason 00:34 JST 11-21: "it shouldnt rise"). From 1.4 s
/// its glow is on (0.7 s): the blue rings pulse from 0.15 to 1 every 2.4 s, and the ⌘ is blue.
/// From 1.4 s the key presses itself in a 7.2 s loop (393): it sinks 4 pt in 0.7 s, stays down
/// until 3.0 s, rises in 0.7 s and rests. The app nudges the device on each press
/// (`nextNudge`). After the person's first own ⌘ press, the key only follows their ⌘ key,
/// 0.08 s down and up, and never loops again (394). When the hint ends, all fades out in place
/// in 0.5 s. CSS blurs are halved for SwiftUI radii.
public struct TurnHint: View {
    /// The view's size: the key's top is 27 pt down, the words 16 pt under the key.
    public static let size = CGSize(width: 300, height: 150)
    public static let words = "Hold ⌘ and drag to turn"
    /// The fade in and out, in place.
    public static let fade = 0.5
    /// The loop (393): its first press, its length, how long a press stays down (its sink
    /// included), the sink and the rise, and the person's own press (394).
    public static let loopStart = 1.4, loop = 7.2, downTime = 3.0, move = 0.7, keyMove = 0.08
    /// The device's nudge starts this long into each press of the loop (mock: 0.6 s).
    public static let nudgeAfter = 0.6

    /// The person's own ⌘ key, after their first press: when it last went down or up, in
    /// seconds from the start, which way, and how far down the key was then.
    public struct Press: Equatable, Sendable {
        public var at: Double, down: Bool, from: Double
        public init(at: Double, down: Bool, from: Double) {
            (self.at, self.down, self.from) = (at, down, from)
        }
    }

    let start: Date
    /// When the hint ended, if it did, and the person's ⌘ key, if they pressed it.
    let ended: Date?
    let press: Press?
    /// A fixed time for snapshot tests, in seconds from the start.
    let fixed: Double?

    public init(start: Date, ended: Date? = nil, press: Press? = nil, fixed: Double? = nil) {
        self.start = start
        self.ended = ended
        self.press = press
        self.fixed = fixed
    }

    /// The look at one moment.
    struct Frame: Equatable {
        /// The whole hint's opacity, how far the key is down (0 up, 1 down 4 pt), the rings'
        /// strength and the blue ⌘'s.
        var opacity: Double, down: Double, glow: Double, blue: Double
    }

    private static func ramp(_ t: Double, _ a: Double, _ b: Double) -> Double { min(max((t - a) / (b - a), 0), 1) }
    private static func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }

    /// How far the key is down `t` seconds after the start: the loop, or the person's own key.
    public static func down(at t: Double, press: Press?) -> Double {
        if let press {
            return press.from + ((press.down ? 1 : 0) - press.from) * ease(ramp(t, press.at, press.at + keyMove))
        }
        guard t > loopStart else { return 0 }
        let phase = (t - loopStart).truncatingRemainder(dividingBy: loop)
        return phase < downTime ? ease(ramp(phase, 0, move)) : 1 - ease(ramp(phase, downTime, downTime + move))
    }

    /// The look `t` seconds after the start; `end` is when the hint ended, if it did.
    static func frame(at t: Double, end: Double? = nil, press: Press? = nil) -> Frame {
        var opacity = ease(ramp(t, 0, fade))
        if let end { opacity *= 1 - ease(ramp(t, end, end + fade)) }
        let on = ease(ramp(t, loopStart, loopStart + move))
        let pulse = 0.15 + 0.85 * (0.5 - 0.5 * cos(2 * .pi * t / 2.4))
        return Frame(opacity: opacity, down: down(at: t, press: press), glow: on * pulse,
                     blue: ease(ramp(t, loopStart, loopStart + 0.3)))
    }

    /// When the hint is gone, in seconds from the start, after it ended at `end`.
    public static func over(end: Double) -> Double { end + fade }

    /// The first nudge of the loop after `t` seconds from the start.
    public static func nextNudge(after t: Double) -> Double {
        let first = loopStart + nudgeAfter
        guard t >= first else { return first }
        return first + loop * ((t - first) / loop).rounded(.down) + loop
    }

    public var body: some View {
        Group {
            if let fixed {
                look(at: fixed)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60)) { context in
                    look(at: context.date.timeIntervalSince(start))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func look(at t: Double) -> some View {
        let look = Self.frame(at: t, end: ended?.timeIntervalSince(start), press: press)
        return VStack(spacing: 16) {
            key(look)
            Text(Self.words)
                .font(.system(size: 14, weight: .medium))
                .tracking(0.1)
                .foregroundStyle(.white)
                .shadow(color: Color(red: 10 / 255, green: 20 / 255, blue: 50 / 255).opacity(0.45), radius: 4, y: 1)
        }
        .padding(.top, 27)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
        .opacity(look.opacity)
    }

    /// The key's face at rest: the gradient, the gray ⌘ and "command". 78 x 60 pt, corner 12.
    private static var face: some View {
        ZStack {
            mark(Color(hex: 0x2c3137))
            Text("command").font(.system(size: 10, weight: .medium))
                .tracking(0.2)
                .foregroundStyle(Color(hex: 0x5b636c))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(EdgeInsets(top: 0, leading: 10, bottom: 8, trailing: 0))
        }
        .frame(width: 78, height: 60)
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(LinearGradient(colors: [.white, Color(hex: 0xf2f4f6)], startPoint: .top, endPoint: .bottom)))
    }

    /// The ⌘ in its place on the face, in `color`.
    private static func mark(_ color: Color) -> some View {
        Text("⌘").font(.system(size: 22, weight: .regular))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(EdgeInsets(top: 7, leading: 0, bottom: 0, trailing: 10))
            .frame(width: 78, height: 60)
    }

    /// Jason (build 390): the press moved in whole-pixel steps. SwiftUI places views and text
    /// on whole device pixels, so a 4 pt move was 8 steps at 2x. The face and the blue ⌘ are
    /// drawn once as pictures, and a Canvas draws them at the exact fraction of a point in each
    /// frame (`TurnHintMotionTests` measures it). Shapes and shadows in a Canvas move smoothly.
    @MainActor private static let faceImage = picture(face)
    @MainActor private static let blueImage = picture(mark(Color(hex: 0x3f8de0)))

    @MainActor private static func picture(_ view: some View) -> Image? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.cgImage.map { Image(decorative: $0, scale: 2) }
    }

    /// Room round the key for its glow and its shadow, in the Canvas.
    private static let margin = 24.0

    /// 78 x 60 pt, corner 12, down 4 pt at `look.down` 1. Up, its side shows 6 pt (#c3c8ce)
    /// over a soft shadow; down, 2 pt: the side's bottom stays still.
    private func key(_ look: Frame) -> some View {
        Color.clear
            .frame(width: 78, height: 60)
            .overlay(alignment: .topLeading) {
                Self.drawing(look)
                    .frame(width: 78 + 2 * Self.margin, height: 60 + 4 + 2 * Self.margin)
                    .offset(x: -Self.margin, y: -Self.margin)
            }
    }

    /// The key drawn at `look`, with `margin` round it.
    private static func drawing(_ look: Frame) -> Canvas<EmptyView> {
        let m = margin, d = look.down, glow = look.glow, blue = look.blue
        let face = faceImage, mark = blueImage
        let ring = Color(red: 90 / 255, green: 163 / 255, blue: 240 / 255)
        let dark = Color(red: 20 / 255, green: 30 / 255, blue: 60 / 255)
        let side = Color(hex: 0xc3c8ce)
        return Canvas { (context: inout GraphicsContext, _: CGSize) in
            let rect = CGRect(x: m, y: m + 4 * d, width: 78, height: 60)
            let shape = RoundedRectangle(cornerRadius: 12).path(in: rect)
            // The glow: three rings of #5aa3f0, 4, 10 and 18 pt, at 0.95, 0.65 and 0.4.
            if glow > 0 {
                var rings = context
                rings.addFilter(.shadow(color: ring.opacity(0.95 * glow), radius: 2))
                rings.addFilter(.shadow(color: ring.opacity(0.65 * glow), radius: 5))
                rings.addFilter(.shadow(color: ring.opacity(0.4 * glow), radius: 9))
                rings.fill(shape, with: .color(.white))
            }
            // The side, a copy of the face 6 - 4d pt lower, and the soft shadow of both.
            var shade = context
            shade.addFilter(.shadow(color: dark.opacity(0.35 - 0.05 * d), radius: 11 - 6 * d, y: 12 - 7 * d))
            shade.drawLayer { (layer: inout GraphicsContext) in
                layer.fill(shape.offsetBy(dx: 0, dy: 6 - 4 * d), with: .color(side))
                layer.fill(shape, with: .color(.white))
            }
            if let face { context.draw(face, in: rect) }
            if blue > 0, let mark {
                var tint = context
                tint.opacity = blue
                tint.draw(mark, in: rect)
            }
        }
    }
}
