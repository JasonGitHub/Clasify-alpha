import ClasifyCore
import SwiftUI

/// The Hello screen's word and times (Round 13, card AT, changes 159 to 168). Times are in
/// seconds since Hello opened (`AppState.helloAt`). These functions only shape time.
enum Hello {
    /// Our own hand-lettered "hello" (HP in round13/gen.py): one path in a 300 x 120 space.
    static let pathData = """
        M20 80 C40 70 60 40 62 20 C63 8 52 8 50 20 C47 40 44 70 42 95 C50 70 70 62 74 72 C77 80 72 92 78 95 \
        C84 98 92 88 96 80 C110 78 122 72 118 64 C114 56 98 62 98 78 C98 92 112 98 128 88 C145 75 160 45 160 25 \
        C160 10 148 12 148 28 C148 50 146 80 152 92 C156 98 166 94 172 86 C188 70 200 45 200 25 C200 10 188 12 \
        188 28 C188 50 186 80 192 92 C196 98 206 94 212 86 C218 74 226 66 238 68 C250 70 254 86 244 94 \
        C234 100 220 94 222 82 C224 72 236 66 250 70 C262 73 272 70 282 62
        """

    /// The start point and the cubic curves (control 1, control 2, end), in path units.
    static let curves: (start: CGPoint, curves: [(CGPoint, CGPoint, CGPoint)]) = {
        let separators: Set<Character> = [" ", "\n", "M", "C"]
        let words: [Substring] = pathData.split(whereSeparator: { separators.contains($0) })
        let numbers: [Double] = words.compactMap { Double(String($0)) }
        var points: [CGPoint] = []
        for i in stride(from: 0, to: numbers.count - 1, by: 2) { points.append(CGPoint(x: numbers[i], y: numbers[i + 1])) }
        var curves: [(CGPoint, CGPoint, CGPoint)] = []
        for i in stride(from: 1, to: points.count - 2, by: 3) { curves.append((points[i], points[i + 1], points[i + 2])) }
        return (points[0], curves)
    }()

    /// The word is drawn at 200 x 80 points (scale 2/3), centered on the 300 x 225 screen.
    static let size = CGSize(width: 200, height: 80)
    static let unit = 2.0 / 3.0

    // MARK: Times (change 165)

    /// One loop of the five looks. Look n starts at n x `slot`.
    static let loop = 22.5, slot = 3.0, write = 2.0, hold = 0.6, fade = 0.4
    /// The center glow starts here and pulses; the begin text comes after 3 pulses (change 166).
    static let glowAt = 16.0, pulse = 2.4, textAfter = 7.2

    /// CSS ease-in-out, cubic-bezier(0.42, 0, 0.58, 1).
    static func ease(_ x: Double) -> Double {
        let x = min(max(x, 0), 1)
        func bezier(_ u: Double, _ a: Double, _ b: Double) -> Double {
            let m: Double = 1 - u
            let first: Double = 3 * m * m * u * a
            let second: Double = 3 * m * u * u * b
            return first + second + u * u * u
        }
        var lo = 0.0, hi = 1.0
        for _ in 0..<30 {  // the x curve only grows, so halving finds u
            let mid = (lo + hi) / 2
            if bezier(mid, 0.42, 0.58) < x { lo = mid } else { hi = mid }
        }
        return bezier((lo + hi) / 2, 0, 1)
    }

    /// How much of look `look` (0 = T1 to 4 = T5) is written at loop time `t`, from 0 to 1.
    /// T1's pixels come on in path order at an even pace; the lines write with ease-in-out.
    static func written(look: Int, at t: Double) -> Double {
        let x = (t - (Double(look) * slot + 0.2)) / write
        return look == 0 ? min(max(x, 0), 1) : ease(x)
    }

    /// The opacity of look `look` at loop time `t`. T1 to T4 hold 0.6 s after writing and fade in
    /// 0.4 s. T5 stays to 22.0 s and fades by 22.4 s.
    static func opacity(look: Int, at t: Double) -> Double {
        let start = Double(look) * slot
        let end = look == 4 ? 22.0 : start + 0.2 + write + hold
        if t < start { return 0 }
        if t <= end { return 1 }
        return max(0, 1 - (t - end) / fade)
    }

    /// T5's wobble after it is written (0.75 s): its x and y scale.
    static func wobble(at t: Double) -> CGSize {
        let keys: [(Double, CGSize)] = [
            (14.2, CGSize(width: 1, height: 1)), (14.45, CGSize(width: 1.035, height: 0.97)),
            (14.7, CGSize(width: 0.99, height: 1.015)), (14.95, CGSize(width: 1, height: 1)),
        ]
        for (a, b) in zip(keys, keys.dropFirst()) where t >= a.0 && t < b.0 {
            let k = ease((t - a.0) / (b.0 - a.0))
            return CGSize(width: a.1.width + (b.1.width - a.1.width) * k, height: a.1.height + (b.1.height - a.1.height) * k)
        }
        return CGSize(width: 1, height: 1)
    }

    /// Where the drop of light on T5 starts along the path, from 14.0 to 15.9 s. It is 5% of the
    /// path long. Nil when no part of it is on the path.
    static func glint(at t: Double) -> ClosedRange<Double>? {
        guard t >= 14.0, t <= 15.9 else { return nil }
        let start = -0.1 + 1.2 * (t - 14.0) / 1.9
        let (lower, upper) = (max(start, 0), min(start + 0.05, 1))
        return upper > lower ? lower...upper : nil
    }

    /// The center glow's opacity at time `t` since Hello opened: off before 16 s (from the start
    /// with Reduce Motion), a 0.4 s fade in, then a pulse between 1 and 0.55 every 2.4 s.
    static func glow(at t: Double, reduceMotion: Bool) -> Double {
        pulse(t - (reduceMotion ? 0 : glowAt))
    }

    /// The center glow's opacity `t` seconds after it starts, on Hello and on the color pick
    /// (change 147): a 0.4 s fade in, then a pulse between 1 and 0.55 every 2.4 s.
    static func pulse(_ t: Double) -> Double {
        if t < 0 { return 0 }
        if t < 0.4 { return t / 0.4 }
        return 0.775 + 0.225 * cos(2 * .pi * (t - 0.4) / pulse)
    }

    /// "Press center button to begin": after 3 pulses of the glow, a 0.4 s fade in. Then it stays.
    static func text(at t: Double, reduceMotion: Bool) -> Double {
        let start = (reduceMotion ? 0 : glowAt) + textAfter
        return min(max((t - start) / 0.4, 0), 1)
    }

    // MARK: T1 Pixel (change 160)

    /// The 1.875 point pixels of T1, in screen pixels, with the part of the writing (0 to 39 of
    /// 40) that turns each on. A pixel is on where its center is within the 2.8 point pen of
    /// the path, as gen.py draws it.
    static let pixels: [(x: Int, y: Int, part: Int)] = {
        let size = 1.875, pen = 2.8 / 1.875
        var points: [CGPoint] = []
        var p0 = curves.start
        for (c1, c2, end) in curves.curves {
            for k in 0..<400 {
                let u = Double(k) / 400, m = 1 - u
                let w0: Double = m * m * m, w1: Double = 3 * m * m * u, w2: Double = 3 * m * u * u, w3: Double = u * u * u
                let x: Double = w0 * Double(p0.x) + w1 * Double(c1.x) + w2 * Double(c2.x) + w3 * Double(end.x)
                let y: Double = w0 * Double(p0.y) + w1 * Double(c1.y) + w2 * Double(c2.y) + w3 * Double(end.y)
                points.append(CGPoint(x: (50 + x * unit) / size, y: (72.5 + y * unit) / size))
            }
            p0 = end
        }
        var first: [Int: Int] = [:]  // key x * 1000 + y: the first sample that turns it on
        for (i, p) in points.enumerated() {
            let px = Double(p.x), py = Double(p.y)
            for x in Int(px - pen - 1)..<Int(px + pen + 2) {
                for y in Int(py - pen - 1)..<Int(py + pen + 2) where first[x * 1000 + y] == nil {
                    let dx: Double = Double(x) + 0.5 - Double(p.x), dy: Double = Double(y) + 0.5 - Double(p.y)
                    if (dx * dx + dy * dy).squareRoot() <= pen { first[x * 1000 + y] = i }
                }
            }
        }
        var pixels: [(x: Int, y: Int, part: Int)] = []
        for (key, sample) in first {
            pixels.append((x: key / 1000, y: key % 1000, part: min(39, sample * 40 / points.count)))
        }
        return pixels.sorted { a, b in (a.part, a.y, a.x) < (b.part, b.y, b.x) }
    }()
}

/// The hello path, drawn into its frame (200 x 80 points on the screen).
struct HelloWord: Shape {
    func path(in rect: CGRect) -> Path {
        let k = rect.width / 300
        func p(_ q: CGPoint) -> CGPoint { CGPoint(x: rect.minX + q.x * k, y: rect.minY + q.y * k) }
        var path = Path()
        path.move(to: p(Hello.curves.start))
        for (c1, c2, end) in Hello.curves.curves { path.addCurve(to: p(end), control1: p(c1), control2: p(c2)) }
        return path
    }
}

/// The Hello screen (card AT): our "hello" writes itself in five looks, T1 Pixel, T2 Ink, T3
/// Selection Blue, T4 Nano Rainbow and T5 Liquid Glass, one after the other, on a loop until the
/// press. "Press center button to begin" comes late and stays. With Reduce Motion, T5 shows at
/// once (change 168).
struct PocketHello: View {
    /// When Hello opened, in `Date.timeIntervalSinceReferenceDate` time.
    let helloAt: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A fixed clock for snapshot tests, in the same time as `helloAt`.
    @Environment(\.animationTime) private var fixedTime
    /// In the small device of the setup screens, Hello is a still T4 Nano Rainbow (card AW).
    @Environment(\.pocketPreview) private var preview

    static let nano: [Color] = ([0x8e5cc6, 0x2d8be0, 0x3fb6c9, 0x5cc24a, 0xf2c230, 0xf28a30, 0xe65c9c] as [UInt32]).map { Color(hex: $0) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: fixedTime != nil || preview)) { context in
            let t = max(0, (fixedTime ?? context.date.timeIntervalSinceReferenceDate) - helloAt)
            if preview { still } else { screen(at: t) }
        }
        .frame(width: Pocket.screenWidth, height: Pocket.screenHeight)
        .accessibilityElement()
        .accessibilityLabel("Hello. Press center button to begin.")
    }

    /// The preview's screen: the T4 line, still and whole, 260 points wide.
    private var still: some View {
        ZStack {
            EllipticalGradient(colors: [.white.opacity(0.95), .white.opacity(0)])
                .frame(width: 240, height: 150)
                .position(x: Pocket.screenWidth / 2, y: Pocket.screenHeight * 0.44)
            HelloWord()
                .stroke(HelloGlass.across(Self.nano), style: StrokeStyle(lineWidth: 6 * 260 / 300, lineCap: .round, lineJoin: .round))
                .frame(width: 260, height: 104)
        }
        .frame(width: Pocket.screenWidth, height: Pocket.screenHeight)
    }

    private func screen(at t: Double) -> some View {
        let loop = t.truncatingRemainder(dividingBy: Hello.loop)
        return ZStack {
            // The soft white glow on our glass, the whole time (change 159).
            EllipticalGradient(colors: [.white.opacity(0.95), .white.opacity(0)])
                .frame(width: 240, height: 150)
                .position(x: Pocket.screenWidth / 2, y: Pocket.screenHeight * 0.44)
            if reduceMotion {
                HelloGlass(written: 1, wobble: CGSize(width: 1, height: 1), glint: nil)
            } else {
                HelloPixels(written: Hello.written(look: 0, at: loop)).opacity(Hello.opacity(look: 0, at: loop))
                line(look: 1, [Pocket.ink], at: loop)
                line(look: 2, [Color(hex: 0x6fb2f5), Color(hex: 0x1f6fd1)], at: loop)
                line(look: 3, Self.nano, at: loop)
                HelloGlass(written: Hello.written(look: 4, at: loop), wobble: Hello.wobble(at: loop), glint: Hello.glint(at: loop))
                    .opacity(Hello.opacity(look: 4, at: loop))
            }
            Text("Press center button to begin")
                .font(.helvetica(11))
                .foregroundStyle(Color(hex: 0x5d6772))
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 14)
                .opacity(Hello.text(at: t, reduceMotion: reduceMotion))
        }
        .frame(width: Pocket.screenWidth, height: Pocket.screenHeight)
    }

    /// T2 to T4: a smooth line, 6 path units wide, with the colors from left to right (x 20 to 282).
    @ViewBuilder private func line(look: Int, _ colors: [Color], at t: Double) -> some View {
        let opacity = Hello.opacity(look: look, at: t), written = Hello.written(look: look, at: t)
        if opacity > 0 && written > 0 {
            HelloWord().trim(from: 0, to: written)
                .stroke(HelloGlass.across(colors), style: StrokeStyle(lineWidth: 6 * Hello.unit, lineCap: .round, lineJoin: .round))
                .frame(width: Hello.size.width, height: Hello.size.height)
                .opacity(opacity)
        }
    }
}

/// T1 Pixel: 1-bit ink pixels of 1.875 points, solid, with no gaps, on in path order.
struct HelloPixels: View {
    let written: Double

    var body: some View {
        Canvas { context, _ in
            let size = 1.875, shown = Int((written * 40).rounded(.down))
            var path = Path()
            for pixel in Hello.pixels where pixel.part < shown || written >= 1 {
                // A hair wider than a pixel, so that two pixels side by side show no seam.
                path.addRect(CGRect(x: Double(pixel.x) * size, y: Double(pixel.y) * size, width: size * 1.06, height: size * 1.06))
            }
            context.fill(path, with: .color(Pocket.ink))
        }
        .frame(width: Pocket.screenWidth, height: Pocket.screenHeight)
    }
}

/// T5 Liquid Glass (iOS 26): a clear tube of glass. The layers, from the bottom (change 164),
/// in path units: a color caustic, a shadow, a dark edge band, the inside (the background
/// seen upside down), a nano tint, two color fringes, an inner rim and the top shine.
struct HelloGlass: View {
    let written: Double
    let wobble: CGSize
    /// The drop of light along the path, after the word is written.
    let glint: ClosedRange<Double>?

    /// A gradient across the word, from path x 20 to 282.
    static func across(_ colors: [Color]) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: UnitPoint(x: 20 / 300, y: 0.5), endPoint: UnitPoint(x: 282 / 300, y: 0.5))
    }

    /// The inside: light at the bottom, darker at the top, from path y 8 to 112.
    static var inside: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(hex: 0xc9d6e3), location: 0), .init(color: Color(hex: 0xeef3f8), location: 0.55),
                .init(color: .white, location: 1),
            ],
            startPoint: UnitPoint(x: 0.5, y: 8 / 120), endPoint: UnitPoint(x: 0.5, y: 112 / 120))
    }

    var body: some View {
        if written > 0 {
            ZStack {
                layer(Self.across(PocketHello.nano), opacity: 0.42, width: 12, y: 6, blur: 3.2)
                layer(Color(hex: 0x1b2a40), opacity: 0.10, width: 13, y: 4, blur: 3.2)
                layer(Color(hex: 0x41566f), opacity: 0.5, width: 15, blur: 0.35)
                layer(Self.inside, opacity: 0.96, width: 12.6, blur: 0.35)
                layer(Self.across(PocketHello.nano), opacity: 0.4, width: 7, blur: 1.1)
                layer(Color(hex: 0x43c6ff), opacity: 0.6, width: 1.1, y: -6.3, blur: 0.35)
                layer(Color(hex: 0xff7a59), opacity: 0.55, width: 1.1, y: 6.3, blur: 0.35)
                layer(Color.white, opacity: 0.9, width: 2.2, y: 3.8, blur: 1.1)
                layer(Color.white, opacity: 1, width: 2.4, y: -4.2, blur: 0.35)
                layer(Color.white, opacity: 0.55, width: 5, y: -3.4, blur: 1.1)
                if let glint {
                    HelloWord().trim(from: glint.lowerBound, to: glint.upperBound)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 6 * Hello.unit, lineCap: .butt))
                        .offset(y: -3.6 * Hello.unit)
                        .blur(radius: 1.1 * Hello.unit)
                }
            }
            .frame(width: Hello.size.width, height: Hello.size.height)
            .scaleEffect(x: wobble.width, y: wobble.height)
        }
    }

    /// One layer: the written part of the path, with its width, offset and blur in path units.
    private func layer(_ style: some ShapeStyle, opacity: Double, width: Double, y: Double = 0, blur: Double) -> some View {
        HelloWord().trim(from: 0, to: written)
            .stroke(style, style: StrokeStyle(lineWidth: width * Hello.unit, lineCap: .round, lineJoin: .round))
            .opacity(opacity)
            .offset(y: y * Hello.unit)
            .blur(radius: blur * Hello.unit)
    }
}

/// The soft blue glow around the wheel's center (changes 147 and 166): a 1.5 point ring
/// #7db7f5 and a blurred glow, pulsing from time `from`.
struct CenterGlow: View {
    let from: Double
    let radius: CGFloat
    @Environment(\.animationTime) private var fixedTime

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: fixedTime != nil)) { context in
            let t = (fixedTime ?? context.date.timeIntervalSinceReferenceDate) - from
            ZStack {
                // box-shadow 0 0 16px 4px rgba(90,163,240,0.7): a circle 4 points wider, blurred.
                Circle().fill(Color(hex: 0x5aa3f0, opacity: 0.7))
                    .frame(width: radius * 2 + 8, height: radius * 2 + 8)
                    .blur(radius: 8)
                // The ring sits just outside the button.
                Circle().stroke(Color(hex: 0x7db7f5), lineWidth: 1.5)
                    .frame(width: radius * 2 + 1.5, height: radius * 2 + 1.5)
            }
            .opacity(Hello.pulse(t))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct PocketPreviewKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The small device on the setup screens' right side: still, with no glow and no input.
    var pocketPreview: Bool {
        get { self[PocketPreviewKey.self] }
        set { self[PocketPreviewKey.self] = newValue }
    }
}
