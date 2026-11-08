import SwiftUI

/// One line of text with no "…" (card AM). Text that fits shows as it is, with no mask.
/// Text wider than its room is cut, and its last `FadeMask.width` points fade out, as on Now
/// Playing (card AA). Use it for every skin text that can be too long, so all screens match.
struct FadeLine: View {
    let text: Text

    init(_ text: Text) { self.text = text }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            text.lineLimit(1).fixedSize()
            text.lineLimit(1).fixedSize()
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)  // starts at the left
                .clipped()
                .mask { FadeMask() }
        }
    }
}

/// The fade at the end of a cut line: opaque, then clear over the last 22 points.
struct FadeMask: View {
    static let width: CGFloat = 22

    var body: some View {
        HStack(spacing: 0) {
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: Self.width)
        }
    }
}
