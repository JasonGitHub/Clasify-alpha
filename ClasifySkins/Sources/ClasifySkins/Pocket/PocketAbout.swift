import AppKit
import SwiftUI

/// The About screen, option E, Round 8 card AB (Jason, 11-07 17:08 JST): a capybara scene in
/// Osaka, faded into the glass, then "Clasify", "Made with ♥ in Osaka" and the version. Each open shows the next
/// scene (17:11 JST); the store picks it. The points are from the top of the 300 x 206 area under
/// the title bar. It is the same on both body colors.
struct PocketAbout: View {
    /// A bundled art scene, with its vertical crop anchor and its VoiceOver label.
    struct Art {
        let image: NSImage?
        let anchor: Double
        let label: String
    }

    /// The scenes in the store's order: 0 the castle, 1 the takoyaki. Each JPEG is 600 x 280 px.
    /// An image is nil only if the package was built without it.
    @MainActor static let scenes = [
        Art(image: art("about-castle"), anchor: 0.40, label: "Capybara at Osaka Castle"),
        Art(image: art("about-takoyaki"), anchor: 0.45, label: "Capybara eating takoyaki"),
    ]

    private static func art(_ name: String) -> NSImage? {
        Bundle.module.url(forResource: name, withExtension: "jpg").flatMap { NSImage(contentsOf: $0) }
    }

    let scene: Int

    var body: some View {
        let current = Self.scenes[min(max(scene, 0), Self.scenes.count - 1)]
        ZStack(alignment: .top) {
            if let image = current.image {
                Self.fill(image, anchor: current.anchor)
                    .accessibilityElement()
                    .accessibilityLabel(current.label)
            }
            // The art fades into the glass, with no hard edge where it ends.
            fade.frame(height: 82).offset(y: 60)
            // Card AB: each line box is as tall as its font (CSS line-height 1). The name's box
            // starts at y 142, and the second line's box starts 3 pt under it, at y 161.
            Text("Clasify").font(.helvetica(16, bold: true)).foregroundStyle(Pocket.ink)
                .frame(height: 16)
                .offset(y: 142)
            HStack(spacing: 3.5) {
                Text("Made with")
                Heart().fill(Color(hex: 0xe0565b)).frame(width: 10, height: 9)
                Text("in Osaka")
            }
            .font(.helvetica(11))
            .foregroundStyle(Color(hex: 0x5d6772))
            .frame(height: 11)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Made with love in Osaka")
            .offset(y: 161)
            Text(Labels.aboutVersion)
                .font(.helvetica(8))
                .foregroundStyle(Color(hex: 0x8a949e))
                .frame(height: 8)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 7)
        }
        .frame(width: Pocket.screenWidth, height: Pocket.listHeight, alignment: .top)
        .clipped()
    }

    /// The art fills 300 x 140, centered across. Down, the spare height splits at `anchor`, so
    /// 0.4 cuts 40% of it from the top and 60% from the bottom.
    private static func fill(_ image: NSImage, anchor: Double) -> some View {
        let box = CGSize(width: Pocket.screenWidth, height: 140)
        let size = image.size.width > 0 && image.size.height > 0 ? image.size : box
        let scale = max(box.width / size.width, box.height / size.height)
        let drawn = CGSize(width: size.width * scale, height: size.height * scale)
        return Image(nsImage: image)
            .resizable()
            .frame(width: drawn.width, height: drawn.height)
            .offset(x: (box.width - drawn.width) / 2, y: (box.height - drawn.height) * anchor)
            .frame(width: box.width, height: box.height, alignment: .topLeading)
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
