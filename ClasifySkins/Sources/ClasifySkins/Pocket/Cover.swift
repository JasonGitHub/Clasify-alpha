import SwiftUI

/// A track's cover in Now Playing and the main menu: the loaded image, or else a blue-grey
/// square with white joined notes. The square is the same for a track with no cover, a cover
/// that is loading and a cover that failed (Jason, 2026-11-06).
struct CoverArt: View {
    let image: CGImage?
    /// The size of the joined notes.
    var notesSize: CGFloat = 54

    /// A cover that showed, with the cover ID it belongs to.
    struct Shown {
        let coverID: String
        let image: CGImage
    }

    /// The image to draw: the track's cover, or the last cover that showed. The last cover stays
    /// while the next one loads, and always when it is the same cover, so a cover that drops out
    /// of memory never blinks to the square. A track with no cover, or whose cover failed, gets
    /// the square at once.
    static func shown(fresh: CGImage?, coverID: String?, pending: Bool, last: Shown?) -> CGImage? {
        if let fresh { return fresh }
        guard let last, pending || last.coverID == coverID else { return nil }
        return last.image
    }

    var body: some View {
        if let image {
            // A new image fades in over 0.2 s instead of a hard cut.
            Image(decorative: image, scale: 1).resizable().scaledToFill()
                .id(ObjectIdentifier(image))
                .transition(.opacity)
        } else {
            LinearGradient.vertical(Color(hex: 0xd5dee8), Color(hex: 0xa9b8c8))
                .overlay { IconView(.notes, width: notesSize, height: notesSize).foregroundStyle(.white) }
        }
    }

    /// The reflection under a cover of `side` points: the cover's lower part mirrored, fading out downward.
    func reflection(side: CGFloat, height: CGFloat) -> some View {
        Group {
            if image != nil {
                self.frame(width: side, height: side)
                    .scaleEffect(x: 1, y: -1, anchor: .center)
                    .frame(width: side, height: height, alignment: .top)
                    .clipped()
            } else {  // the mockup turns the placeholder's gradient over, without the notes
                LinearGradient.vertical(Color(hex: 0xa9b8c8), Color(hex: 0xd5dee8))
            }
        }
        .frame(width: side, height: height)
        .mask(LinearGradient.vertical(.black.opacity(image == nil ? 0.45 : 0.35), .clear))
    }
}

/// CSS `perspective(240px) rotateY(18deg)` with `transform-origin: left center`: the right
/// edge turns away from the viewer.
struct Tilt: GeometryEffect {
    var degrees = 18.0
    var distance = 240.0

    func effectValue(size: CGSize) -> ProjectionTransform {
        // A point (x, y) moves to (x cos a, y + x s h/2) / (1 + x s), with s = sin a / distance.
        let a = degrees * .pi / 180, s = sin(a) / distance
        var t = ProjectionTransform()
        t.m11 = cos(a)
        t.m12 = size.height / 2 * s
        t.m13 = s
        return t
    }
}
