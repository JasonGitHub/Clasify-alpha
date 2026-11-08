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
    /// `strength` is where a real cover's reflection starts, `placeholderStrength` the default art's.
    func reflection(side: CGFloat, height: CGFloat, strength: Double = 0.35, placeholderStrength: Double = 0.45) -> some View {
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
        .mask(LinearGradient.vertical(.black.opacity(image == nil ? placeholderStrength : strength), .clear))
    }
}

/// The photo's tilt: the mockup's CSS `matrix3d(1.164835, 0.082418, 0, 0.001259, 0,1,0,0,
/// 0,0,1,0, 0,0,0,1)` with `transform-origin: 0 0`. A point (x, y) moves to
/// (1.164835 x, 0.082418 x + y) / (1 + 0.001259 x), so the 126.6 point cover is 126.6 tall
/// on the left and about 109 on the right.
struct Tilt: GeometryEffect {
    func effectValue(size: CGSize) -> ProjectionTransform {
        var t = ProjectionTransform()
        t.m11 = 1.164835
        t.m12 = 0.082418
        t.m13 = 0.001259
        return t
    }
}
