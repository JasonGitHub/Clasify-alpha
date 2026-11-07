import AppKit
import SwiftUI

/// The About screen, option E (Jason, 11-07 17:08 JST): the capybara at Osaka Castle, faded
/// into the glass, then "Clasify", "Made with ♥ in Osaka" and the version. The points are from
/// the top of the 300 x 206 area under the title bar. It is the same on both body colors.
struct PocketAbout: View {
    /// The bundled art, 718 x 306 pixels. Nil only if the package was built without it.
    @MainActor static let castle: NSImage? = Bundle.module.url(forResource: "about-castle", withExtension: "png")
        .flatMap { NSImage(contentsOf: $0) }

    var body: some View {
        ZStack(alignment: .top) {
            if let castle = Self.castle {
                Image(nsImage: castle)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Pocket.screenWidth, height: 140)
                    .clipped()
                    .accessibilityHidden(true)
            }
            // The art fades into the glass, with no hard edge where it ends.
            fade.frame(height: 82).offset(y: 60)
            VStack(spacing: 3) {
                Text("Clasify").font(.helvetica(16, bold: true)).foregroundStyle(Pocket.ink)
                HStack(spacing: 3.5) {
                    Text("Made with")
                    Heart().fill(Color(hex: 0xe0565b)).frame(width: 10, height: 9)
                    Text("in Osaka")
                }
                .font(.helvetica(11))
                .foregroundStyle(Color(hex: 0x5d6772))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Made with love in Osaka")
            }
            .offset(y: 142)
            Text(Labels.aboutVersion)
                .font(.helvetica(8))
                .foregroundStyle(Color(hex: 0x8a949e))
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 7)
        }
        .frame(width: Pocket.screenWidth, height: Pocket.listHeight, alignment: .top)
        .clipped()
    }

    /// Clear to the glass color at y 142, about rgb(226, 235, 242), with the spec's stops.
    private var fade: some View {
        let glass = Color(red: 226 / 255, green: 235 / 255, blue: 242 / 255)
        let stops: [(Double, Double)] = [(0, 0), (0.18, 0.08), (0.40, 0.30), (0.63, 0.62), (0.84, 0.90), (1, 1)]
        return LinearGradient(
            stops: stops.map { .init(color: glass.opacity($0.1), location: $0.0) }, startPoint: .top, endPoint: .bottom)
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
