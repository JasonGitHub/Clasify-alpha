import AppKit
import ClasifyCore
import SwiftUI

/// The right side of Pick Your Music (card BM, changes 257 and 264): the big logo of the
/// selected service in place of the small device. A 90 point tile with a 22 point corner
/// radius, on a soft white glow, with a Cover Flow reflection under it. On each turn the logo
/// crossfades in 0.25 s, like the color preview of Pick Your Color. Logos show only here.
struct ServiceLogo: View {
    let service: MusicService

    static let size: CGFloat = 90, radius: CGFloat = 22
    static let fade = 0.25

    /// The bundled logos, each 684 px square. A logo is missing only if the package was built
    /// without its file; then the tile shows the service's name.
    @MainActor static let logos: [MusicService: NSImage] = Dictionary(uniqueKeysWithValues: MusicService.allCases.compactMap { service in
        let name = service == .spotify ? "logo-spotify" : "logo-apple-music"
        return PocketAbout.art(name).map { (service, $0) }
    })

    var body: some View {
        ZStack {
            // The setup side's own background, as behind the small device (card AW).
            RadialGradient(
                colors: [.white, Color(hex: 0xd6e2ec)], center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 0, endRadius: 0.78 * hypot(75, 225 * 0.58))
            // radial-gradient(circle at 50% 42%, rgba(255,255,255,0.85), transparent 62%).
            RadialGradient(
                colors: [Color.white.opacity(0.85), Color.white.opacity(0)], center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 0, endRadius: 0.62 * hypot(75, 225 * 0.58))
            ZStack {
                ForEach(MusicService.allCases, id: \.self) { item in
                    tile(item).opacity(item == service ? 1 : 0)
                }
            }
            .animation(.easeInOut(duration: Self.fade), value: service)
            .offset(y: -7)  // margin-top: -14px in the centered column
        }
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("\(service.rawValue) logo")
    }

    /// One logo tile with its shadow and its reflection, 3 points under it.
    private func tile(_ item: MusicService) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        let logo = Group {
            if let image = Self.logos[item] {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                // A safety net only: the name in white on a dark tile.
                ZStack {
                    Color(hex: 0x1b1f24)
                    Text(item.rawValue)
                        .font(.helvetica(13, bold: true))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(6)
                }
            }
        }
        .frame(width: Self.size, height: Self.size)
        .clipShape(shape)
        return logo
            .overlay(shape.inset(by: 0.25).stroke(Color.white.opacity(0.6), lineWidth: 0.5).mask(alignment: .top) {
                Rectangle().frame(height: 1)  // the 0.5 point inset light on the top edge
            })
            .shadow(color: Color(hex: 0x141e28, opacity: 0.22), radius: 5, y: 4)
            .background(alignment: .top) {
                // -webkit-box-reflect: below 3px, faded from 28% next to the tile to nothing.
                logo
                    .scaleEffect(x: 1, y: -1)
                    .mask {
                        LinearGradient(
                            stops: [.init(color: .black.opacity(0.28), location: 0), .init(color: .clear, location: 0.38)],
                            startPoint: .top, endPoint: .bottom)
                    }
                    .offset(y: Self.size + 3)
            }
    }
}
