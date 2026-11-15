import AppKit
import ClasifyCore
import SwiftUI

/// The About screen, card BF (About J1, Jason 23:05 JST 11-10, changes 207, 208, 211 and 212):
/// one page that scrolls 5 wheel steps of 22.9 pt. The headphone capybara on its ground shadow,
/// "myPod", the tagline and "Made with ♥ by CappyAI" in engraved steel, the Version and
/// Licenses rows, then the legal text. The points are from the top of the 321.5 pt page.
/// The capybara waves, thinks, drinks boba and sleeps as `AppState.aboutPose(at:)` says, and
/// the tagline's glint runs with each wave (changes 209, 210). Card BF.1 (J1.3, changes 214-216)
/// set the front page: two text styles, and "Made with ♥ by CappyAI" before the tagline.
struct PocketAbout: View {
    let state: AppState
    /// The scroll bar waits 0.3 s after About opens.
    @State private var barReady = false
    /// A fixed clock for snapshot tests, in the same time as `AppState.aboutAt`.
    @Environment(\.animationTime) private var fixedTime

    static let step: CGFloat = 22.9, page: CGFloat = 321.5
    /// The capybara's poses, each 440 px square. A pose is missing only if the package was built
    /// without its art.
    @MainActor static let poses: [AboutPose: NSImage] = Dictionary(uniqueKeysWithValues: AboutPose.allCases.compactMap { pose in
        art("about-hp-\(pose)").map { (pose, $0) }
    })

    static func art(_ name: String) -> NSImage? {
        Bundle.module.url(forResource: name, withExtension: "png").flatMap { NSImage(contentsOf: $0) }
    }

    /// The steel of "myPod", and of the other lines (change 209).
    static let nameSteel = steel([0x7d8892, 0x5a646e, 0x262c33, 0x3c444d, 0x8f99a3])
    static let lineSteel = steel([0x9aa4ae, 0x76808a, 0x46505a, 0x5a646e, 0xa7b1bb])

    private static func steel(_ colors: [UInt32]) -> LinearGradient {
        let stops = zip(colors, [0, 0.3, 0.52, 0.7, 1]).map { Gradient.Stop(color: Color(hex: $0.0), location: $0.1) }
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        let off = state.top.off
        ZStack(alignment: .topLeading) {
            // CLA-114: only the page's offset slides. The Licenses selection bar comes and goes
            // at once, so it never fades at the wrong place while the page moves.
            page(licenses: off >= AppState.aboutLicensesStep)
                .frame(width: Pocket.screenWidth, height: Self.page, alignment: .top)
                .animation(.easeOut(duration: 0.15)) { $0.offset(y: -CGFloat(off) * Self.step) }
            scrollBar(off)
        }
        .frame(width: Pocket.screenWidth, height: Pocket.listHeight, alignment: .topLeading)
        .clipped()
        .task(id: state.aboutAt) {
            barReady = false
            try? await Task.sleep(for: .seconds(0.3))
            barReady = true
        }
    }

    private func page(licenses: Bool) -> some View {
        ZStack(alignment: .top) {
            capybara.offset(y: 18)
            plate.offset(y: 116)
            PocketRow(text: .init(label: "Version", value: Labels.aboutVersion(in: state)), selected: false, scrolls: false)
                .offset(y: 214)
            PocketRow(text: .init(label: "Licenses", opens: true), selected: licenses, scrolls: false)
                .offset(y: 236.9)
            legal.offset(y: 270)
        }
    }

    /// 96 pt, on a soft ground shadow 52 x 7 pt that ends 3 pt under the box. The poses are
    /// stacked: the new one fades in over the old one in 0.3 s (CSS ease), so the body never
    /// dims; the old one fades out after. A cut (the wave in and out) shows at once.
    private var capybara: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: fixedTime != nil)) { context in
            let t = fixedTime ?? context.date.timeIntervalSinceReferenceDate
            let now = state.aboutPose(at: t), into = t - now.since
            ZStack {
                EllipticalGradient(colors: [Color(hex: 0x1b1f24, opacity: 0.2), Color(hex: 0x1b1f24, opacity: 0)])
                    .frame(width: 48, height: 7)
                    .offset(y: 43.5)  // its bottom 3 pt under the 88 pt box
                ForEach(AboutPose.allCases, id: \.self) { pose in
                    if let image = Self.poses[pose] {
                        // The old pose stays whole under the new one for 0.32 s, then fades out in 0.3 s.
                        let on = pose == now.pose, under = !now.cut && pose == now.from && into < 0.62
                        Image(nsImage: image).resizable().interpolation(.high)
                            .scaleEffect(on && pose == .sleep ? Self.breath(into) : CGSize(width: 1, height: 1),
                                         anchor: UnitPoint(x: 0.5, y: 0.85))
                            .rotationEffect(.degrees(on && pose == .wave ? Self.rock(into) : 0), anchor: UnitPoint(x: 0.5, y: 0.92))
                            .opacity(on ? (now.cut ? 1 : Self.bezier(0.25, 0.1, 0.25, 1, into / 0.3))
                                     : under ? 1 - Self.bezier(0.25, 0.1, 0.25, 1, (into - 0.32) / 0.3) : 0)
                            .zIndex(on ? 2 : under ? 1 : 0)
                    }
                }
            }
            .frame(width: 88, height: 88)
            .accessibilityElement()
            .accessibilityLabel("Capybara with headphones" + Self.doing[now.pose, default: ""])
        }
    }

    private static let doing: [AboutPose: String] = [.wave: ", waving", .think: ", thinking", .boba: ", drinking boba", .sleep: ", asleep"]

    /// The wave rocks 0, -4°, +4°, 0 at 0, 25, 75 and 100% of 0.5 s, twice, with ease-in-out
    /// on each part.
    nonisolated static func rock(_ t: Double) -> Double {
        let x = max(t, 0).truncatingRemainder(dividingBy: 0.5) / 0.5
        func ease(_ u: Double) -> Double { bezier(0.42, 0, 0.58, 1, u) }
        if x < 0.25 { return -4 * ease(x / 0.25) }
        if x < 0.75 { return -4 + 8 * ease((x - 0.25) / 0.5) }
        return 4 - 4 * ease((x - 0.75) / 0.25)
    }

    /// Asleep, it breathes: after 0.3 s, to scale (1.012, 1.03) and back every 3.2 s, with
    /// ease-in-out on each half.
    nonisolated static func breath(_ t: Double) -> CGSize {
        guard t > 0.3 else { return CGSize(width: 1, height: 1) }
        let x = (t - 0.3).truncatingRemainder(dividingBy: 3.2) / 3.2
        let k = bezier(0.42, 0, 0.58, 1, x < 0.5 ? x * 2 : 2 - x * 2)
        return CGSize(width: 1 + 0.012 * k, height: 1 + 0.03 * k)
    }

    /// CSS cubic-bezier(x1, y1, x2, y2) at `x`, from 0 to 1: finds the curve point with that x
    /// by bisection, and returns its y.
    nonisolated static func bezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        func curve(_ s: Double, _ a: Double, _ b: Double) -> Double {
            3 * (1 - s) * (1 - s) * s * a + 3 * (1 - s) * s * s * b + s * s * s
        }
        var low = 0.0, high = 1.0
        for _ in 0..<32 {
            let mid = (low + high) / 2
            if curve(mid, x1, x2) < x { low = mid } else { high = mid }
        }
        return curve((low + high) / 2, y1, y2)
    }

    /// Change 214-216: "myPod" 20 bold in its 23 pt line, then 37 pt down "Made with ♥ by
    /// CappyAI" and 56 pt down the tagline, both 14 regular in 16 pt lines. The steel has a white
    /// line under it and a faint dark line over it.
    private var plate: some View {
        ZStack(alignment: .top) {
            Self.engraved(Text("myPod").font(.helvetica(20, bold: true)), height: 23, Self.nameSteel)
            signature.offset(y: 37)
            tagline.offset(y: 56)
        }
        .shadow(color: .white.opacity(0.9), radius: 0, y: 1)
        .shadow(color: .black.opacity(0.18), radius: 0, y: -0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("myPod. Made with love by CappyAI. AI-native craftsmanship.")
    }

    /// "Made with ♥ by CappyAI" in steel. The glint sweeps the whole line as one, from the start
    /// of each wave; the red heart has none (change 218, Jason 00:14 JST 11-11).
    private var signature: some View {
        func words(heart: Bool) -> some View {
            HStack(spacing: 4) {
                Text("Made with").font(.helvetica(14)).opacity(heart ? 0 : 1)
                Heart().fill(Color(hex: 0xe0565b)).frame(width: 12, height: 11).opacity(heart ? 1 : 0)
                Text("by CappyAI").font(.helvetica(14)).opacity(heart ? 0 : 1)
            }
            .lineLimit(1).fixedSize().frame(height: 16)
        }
        return glinting(words(heart: false), after: 0).overlay { words(heart: true) }
    }

    /// "AI-native craftsmanship" in steel. Its glint starts 0.15 s after the signature's.
    private var tagline: some View {
        glinting(Text("AI-native craftsmanship").font(.helvetica(14)).lineLimit(1).fixedSize().frame(height: 16), after: 0.15)
    }

    /// `line` in the line steel, with a bright band that sweeps left to right in 1.8 s
    /// (ease-in-out) from `after` seconds after the start of each wave.
    private func glinting(_ line: some View, after delay: Double) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: fixedTime != nil)) { context in
            let t = fixedTime ?? context.date.timeIntervalSinceReferenceDate
            line.hidden().overlay {
                ZStack { Self.lineSteel; Self.glint(Self.bezier(0.42, 0, 0.58, 1, (t - state.aboutWaveAt - delay) / 1.8)) }
                    .mask { line }
            }
        }
    }

    /// The CSS glint: a 100° band (clear 40%, .75 at 47%, .95 at 50%, .75 at 53%, clear 60%) in a
    /// layer 3 times as wide as the text. At 0 the layer's right edge is on the text's right edge,
    /// so the band is off the left; at 1 its left edge is on the text's left edge.
    static func glint(_ progress: Double) -> some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let angle = 100.0 * .pi / 180, dx = sin(angle), dy = -cos(angle)
            let length = 3 * w * abs(dx) + h * abs(dy)
            let start = UnitPoint(x: 0.5 - dx * length / 2 / (3 * w), y: 0.5 - dy * length / 2 / h)
            let end = UnitPoint(x: 0.5 + dx * length / 2 / (3 * w), y: 0.5 + dy * length / 2 / h)
            let light = Color(red: 235 / 255, green: 240 / 255, blue: 245 / 255)
            LinearGradient(stops: [
                .init(color: .white.opacity(0), location: 0.4), .init(color: light.opacity(0.75), location: 0.47),
                .init(color: .white.opacity(0.95), location: 0.5), .init(color: light.opacity(0.75), location: 0.53),
                .init(color: .white.opacity(0), location: 0.6),
            ], startPoint: start, endPoint: end)
            .frame(width: 3 * w, height: h)
            .offset(x: -2 * w * (1 - progress))
        }
    }

    /// 10 pt lines, 14 pt apart, each line in its own steel.
    private var legal: some View {
        VStack(spacing: 0) {
            ForEach(["© 2026 CappyAI Ltd. All rights reserved.", "Spotify is a trademark of Spotify AB.",
                     "myPod is not affiliated with Spotify."], id: \.self) { line in
                Self.engraved(Text(line).font(.helvetica(10)), height: 14, Self.lineSteel)
            }
        }
        .shadow(color: .white.opacity(0.85), radius: 0, y: 1)
        .shadow(color: .black.opacity(0.12), radius: 0, y: -0.5)
        .accessibilityElement(children: .combine)
    }

    /// The text in a steel gradient that spans its line box, as CSS background-clip: text.
    private static func engraved(_ text: Text, height: CGFloat, _ steel: LinearGradient) -> some View {
        let line = text.lineLimit(1).fixedSize().frame(height: height)
        return line.hidden().overlay { steel.mask { line } }
    }

    /// A 3 pt thumb, 64.1% of the track, on the right; the track is 2 pt in from the top and the
    /// bottom. It moves with the page and shows as the list scroll bars do.
    private func scrollBar(_ off: Int) -> some View {
        GeometryReader { geo in
            let track = geo.size.height
            Capsule().fill(Color(hex: 0x5d6772))
                .frame(height: track * 0.641)
                .offset(y: track * 0.359 * CGFloat(off) / CGFloat(AppState.aboutSteps))
                .animation(.easeOut(duration: 0.15), value: off)
        }
        .frame(width: 3)
        .padding(.vertical, 2)
        .padding(.trailing, 1.5)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .opacity(barReady && state.scrollUntil > 0 ? 1 : 0)
        .animation(.easeInOut(duration: 0.4), value: barReady && state.scrollUntil > 0)
        .accessibilityHidden(true)
    }
}

/// The spec's heart, drawn from its 16 x 14 SVG path and scaled to the frame.
struct Heart: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 8, y: 13.2))
        p.addCurve(to: CGPoint(x: 1, y: 4.6), control1: CGPoint(x: 3.2, y: 9.6), control2: CGPoint(x: 1, y: 7.4))
        p.addCurve(to: CGPoint(x: 4.5, y: 1), control1: CGPoint(x: 1, y: 2.6), control2: CGPoint(x: 2.6, y: 1))
        p.addCurve(to: CGPoint(x: 8, y: 3.1), control1: CGPoint(x: 6, y: 1), control2: CGPoint(x: 7.3, y: 1.9))
        p.addCurve(to: CGPoint(x: 11.5, y: 1), control1: CGPoint(x: 8.7, y: 1.9), control2: CGPoint(x: 10, y: 1))
        p.addCurve(to: CGPoint(x: 15, y: 4.6), control1: CGPoint(x: 13.4, y: 1), control2: CGPoint(x: 15, y: 2.6))
        p.addCurve(to: CGPoint(x: 8, y: 13.2), control1: CGPoint(x: 15, y: 7.4), control2: CGPoint(x: 12.8, y: 9.6))
        p.closeSubpath()
        return p.applying(CGAffineTransform(scaleX: rect.width / 16, y: rect.height / 14).translatedBy(x: rect.minX, y: rect.minY))
    }
}
