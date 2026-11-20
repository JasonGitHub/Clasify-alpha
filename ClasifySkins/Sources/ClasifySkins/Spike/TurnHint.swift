import SwiftUI

/// CLA-163, card BZ option A v2 (changes 357-359), a trial behind `hints.trial`: once ever,
/// under the device, a ⌘ key and the words "Hold ⌘ and drag to turn". The app puts this view
/// in its own clear window, its top at the device's bottom edge. Designer 1's timeline, in
/// seconds from the start: the key fades in and rises 8 pt in 0.85 s; it goes down 4 pt at
/// 1.4 to 1.7 s and stays down; while down, its glow (the blue rings and the blue ⌘) pulses
/// from 0.15 to 1 every 2.4 s; it comes up at 5.0 to 5.3 s; all is gone at 6.6 s. The first
/// Cmd turn ends it early: all fades out in 0.3 s. CSS blurs are halved for SwiftUI radii.
public struct TurnHint: View {
    /// The view's size: the key's top is 27 pt down, the words 16 pt under the key.
    public static let size = CGSize(width: 300, height: 150)
    public static let words = "Hold ⌘ and drag to turn"
    /// The whole hint, and the early fade after the first Cmd turn.
    public static let length = 6.6, endFade = 0.3

    /// The seconds since the start, and when the first Cmd turn came, if it came.
    let start: Date
    let ended: Date?
    /// A fixed time for snapshot tests, in seconds from the start.
    let fixed: Double?

    public init(start: Date, ended: Date? = nil, fixed: Double? = nil) {
        self.start = start
        self.ended = ended
        self.fixed = fixed
    }

    /// The look at one moment.
    struct Frame: Equatable {
        /// The whole hint's opacity, how far the key still has to rise (pt), how far it is
        /// down (0 up, 1 down 4 pt), and the glow's strength.
        var opacity: Double, rise: Double, down: Double, glow: Double
    }

    /// The look `t` seconds after the start; `end` is the first Cmd turn's time, if any.
    static func frame(at t: Double, end: Double? = nil) -> Frame {
        func ramp(_ a: Double, _ b: Double) -> Double { min(max((t - a) / (b - a), 0), 1) }
        func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }
        let shown = ease(ramp(0, 0.85))
        let down = ease(ramp(1.4, 1.7)) - ease(ramp(5.0, 5.3))
        let pulse = 0.15 + 0.85 * (0.5 - 0.5 * cos(2 * .pi * max(t - 1.7, 0) / 2.4))
        var opacity = shown * (1 - ease(ramp(5.6, length)))
        if let end { opacity *= 1 - min(max((t - end) / endFade, 0), 1) }
        return Frame(opacity: opacity, rise: 8 * (1 - shown), down: down, glow: down * pulse)
    }

    /// When the hint is gone, in seconds from the start.
    public static func over(end: Double?) -> Double { min(length, end.map { $0 + endFade } ?? length) }

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
        let look = Self.frame(at: t, end: ended?.timeIntervalSince(start))
        return VStack(spacing: 16) {
            key(look).offset(y: look.rise + 4 * look.down)
            Text(Self.words)
                .font(.system(size: 14, weight: .medium))
                .tracking(0.1)
                .foregroundStyle(.white)
                .shadow(color: Color(red: 10 / 255, green: 20 / 255, blue: 50 / 255).opacity(0.45), radius: 4, y: 1)
                .offset(y: look.rise)
        }
        .padding(.top, 27)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
        .opacity(look.opacity)
    }

    /// 78 x 60 pt, corner 12. Up, its side shows 6 pt (#c3c8ce) over a soft shadow; down, 2 pt.
    private func key(_ look: Frame) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        let d = look.down, ring = Color(red: 90 / 255, green: 163 / 255, blue: 240 / 255)
        return ZStack {
            Text("⌘").font(.system(size: 22, weight: .regular))
                .foregroundStyle(Color(hex: 0x2c3137))
                .overlay { Text("⌘").font(.system(size: 22, weight: .regular)).foregroundStyle(Color(hex: 0x3f8de0)).opacity(look.glow) }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(EdgeInsets(top: 7, leading: 0, bottom: 0, trailing: 10))
            Text("command").font(.system(size: 10, weight: .medium))
                .tracking(0.2)
                .foregroundStyle(Color(hex: 0x5b636c))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(EdgeInsets(top: 0, leading: 10, bottom: 8, trailing: 0))
        }
        .frame(width: 78, height: 60)
        .background {
            ZStack {
                // The glow: three rings of #5aa3f0, 4, 10 and 18 pt, at 0.95, 0.65 and 0.4.
                shape.fill(.white)
                    .shadow(color: ring.opacity(0.95 * look.glow), radius: 2)
                    .shadow(color: ring.opacity(0.65 * look.glow), radius: 5)
                    .shadow(color: ring.opacity(0.4 * look.glow), radius: 9)
                shape.fill(LinearGradient(colors: [.white, Color(hex: 0xf2f4f6)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: Color(hex: 0xc3c8ce), radius: 0, y: 6 - 4 * d)
                    .shadow(color: Color(red: 20 / 255, green: 30 / 255, blue: 60 / 255).opacity(0.35 - 0.05 * d),
                            radius: 11 - 6 * d, y: 12 - 7 * d)
            }
        }
    }
}
