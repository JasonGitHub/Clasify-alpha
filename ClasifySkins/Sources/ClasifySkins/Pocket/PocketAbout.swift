import AppKit
import ClasifyCore
import SwiftUI

/// The About screen, card BF (About J1, Jason 23:05 JST 11-10, changes 207, 208, 211 and 212):
/// one page that scrolls 5 wheel steps of 22.9 pt. The headphone capybara on its ground shadow,
/// "Clasify", the tagline and "Made with ♥ by CappyAI" in engraved steel, the Version and
/// Licenses rows, then the legal text. The points are from the top of the 321.5 pt page.
struct PocketAbout: View {
    let state: AppState
    /// The scroll bar waits 0.3 s after About opens.
    @State private var barReady = false

    static let step: CGFloat = 22.9, page: CGFloat = 321.5
    /// The capybara, 440 px square. Nil only if the package was built without it.
    @MainActor static let stand = art("about-hp-stand")

    static func art(_ name: String) -> NSImage? {
        Bundle.module.url(forResource: name, withExtension: "png").flatMap { NSImage(contentsOf: $0) }
    }

    /// The steel of "Clasify", and of the other lines (change 209).
    static let nameSteel = steel([0x7d8892, 0x5a646e, 0x262c33, 0x3c444d, 0x8f99a3])
    static let lineSteel = steel([0x9aa4ae, 0x76808a, 0x46505a, 0x5a646e, 0xa7b1bb])

    private static func steel(_ colors: [UInt32]) -> LinearGradient {
        let stops = zip(colors, [0, 0.3, 0.52, 0.7, 1]).map { Gradient.Stop(color: Color(hex: $0.0), location: $0.1) }
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        let off = state.top.off
        ZStack(alignment: .topLeading) {
            page(licenses: off >= AppState.aboutLicensesStep)
                .frame(width: Pocket.screenWidth, height: Self.page, alignment: .top)
                .offset(y: -CGFloat(off) * Self.step)
                .animation(.easeOut(duration: 0.15), value: off)
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
            capybara.offset(y: 20)
            plate.offset(y: 127)  // under the 96 pt capybara and its 11 pt gap
            PocketRow(text: .init(label: "Version", value: Labels.version), selected: false, scrolls: false)
                .offset(y: 214)
            PocketRow(text: .init(label: "Licenses", opens: true), selected: licenses, scrolls: false)
                .offset(y: 236.9)
            legal.offset(y: 270)
        }
    }

    /// 96 pt, on a soft ground shadow 52 x 7 pt that ends 3 pt under the box.
    private var capybara: some View {
        ZStack {
            EllipticalGradient(colors: [Color(hex: 0x1b1f24, opacity: 0.2), Color(hex: 0x1b1f24, opacity: 0)])
                .frame(width: 52, height: 7)
                .offset(y: 47.5)
            if let stand = Self.stand {
                Image(nsImage: stand).resizable().interpolation(.high)
            }
        }
        .frame(width: 96, height: 96)
        .accessibilityElement()
        .accessibilityLabel("Capybara with headphones")
    }

    /// "Clasify" 20 bold, the tagline 14, and 60 pt under the top "Made with ♥ by CappyAI" 11.
    /// The steel has a white line under it and a faint dark line over it.
    private var plate: some View {
        VStack(spacing: 0) {
            Self.engraved(Text("Clasify").font(.helvetica(20, bold: true)), height: 23, Self.nameSteel)
            Self.engraved(Text("AI-native craftsmanship").font(.helvetica(14)), height: 16, Self.lineSteel)
                .padding(.top, 2)
        }
        .overlay(alignment: .top) {
            HStack(spacing: 3.5) {
                Self.engraved(Text("Made with").font(.helvetica(11)), height: 13, Self.lineSteel)
                Heart().fill(Color(hex: 0xe0565b)).frame(width: 10, height: 9)
                Self.engraved(Text("by").font(.helvetica(11)), height: 13, Self.lineSteel)
                Self.engraved(Text("CappyAI").font(.helvetica(11, weight: .medium)), height: 13, Self.lineSteel)
            }
            .fixedSize()
            .offset(y: 60)
        }
        .shadow(color: .white.opacity(0.9), radius: 0, y: 1)
        .shadow(color: .black.opacity(0.18), radius: 0, y: -0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Clasify. AI-native craftsmanship. Made with love by CappyAI.")
    }

    /// 10 pt lines, 14 pt apart, each line in its own steel.
    private var legal: some View {
        VStack(spacing: 0) {
            ForEach(["© 2026 CappyAI Ltd. All rights reserved.", "Spotify is a trademark of Spotify AB.",
                     "Clasify is not affiliated with Spotify."], id: \.self) { line in
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
