import ClasifyCore
import SwiftUI

/// CLA-183, card CS: the Search screen under the title bar. The search field, then the results
/// (4 rows of 34 points, `searchRows`) or a message, then the letter strip. Sizes and colors are
/// from the card's try page (design-review/search/try): `.field`, `.rr`, `.empty` and `.strip`.
struct PocketSearch: View {
    let state: AppState

    /// The card's result row height.
    static let rowHeight: CGFloat = 34
    /// The field with its margins: 6 above, 22 tall, 4 below.
    static let fieldHeight: CGFloat = 32
    /// The strip with its 1 point top line.
    static let stripHeight: CGFloat = 35
    static let mutedInk = Color(hex: 0x5d6772)
    static let faint = Color(hex: 0x9ba3ad)

    var body: some View {
        VStack(spacing: 0) {
            SearchField(query: state.searchQuery)
                .padding(EdgeInsets(top: 6, leading: 8, bottom: 4, trailing: 8))
            Group {
                if state.searchQuery.isEmpty {
                    SearchMessage(mark: .key, words: Labels.searchEmpty)
                } else if state.searchResults.isEmpty {
                    SearchMessage(mark: .glass, words: Labels.searchNoMatch)
                } else {
                    results
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
            LetterStrip(index: Search.stripIndex(state.searchQuery))
        }
        .frame(width: Pocket.screenWidth, height: Pocket.listHeight)
    }

    /// The rows that show: `searchRows` from the scroll place, and a part of the next one, as
    /// on the try page. No row is selected until the wheel or Return (`searchPicked`).
    private var results: some View {
        let top = state.top
        let found = state.searchResults
        return VStack(spacing: 0) {
            ForEach(Array(found.indices.dropFirst(top.off).prefix(searchRows + 1)), id: \.self) { i in
                SearchRow(result: found[i], selected: state.searchPicked && i == top.sel)
            }
        }
    }
}

/// The white field: a magnifier, the typed text and a blue caret that blinks every 1.05 s.
struct SearchField: View {
    let query: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.animationTime) private var fixedTime

    var body: some View {
        HStack(spacing: 0) {
            SearchMark.glass.view(size: 11, line: 2.6, color: PocketSearch.mutedInk)
                .padding(.trailing, 5)
            Text(query).font(.helvetica(13, bold: true)).foregroundStyle(Pocket.ink).lineLimit(1)
                .fixedSize()
            TimelineView(.periodic(from: .distantPast, by: 0.525)) { context in
                let t = fixedTime ?? context.date.timeIntervalSinceReferenceDate
                // `@keyframes bl{50%{opacity:0}}` with steps(1): on for the first half of 1.05 s.
                Rectangle().fill(Pocket.blue)
                    .frame(width: 1.5, height: 14)
                    .opacity(reduceMotion || t.truncatingRemainder(dividingBy: 1.05) < 0.525 ? 1 : 0)
            }
            .frame(width: 1.5, height: 14)
            .padding(.leading, 1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background {
            RoundedRectangle(cornerRadius: 5).fill(.white)
                // `inset 0 1px 2px rgba(0,0,0,0.15)`: a soft shade under the top edge.
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.black.opacity(0.15), lineWidth: 2)
                        .blur(radius: 1)
                        .offset(y: 1)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
        }
        .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(Color(hex: 0x9aa4ae), lineWidth: 1) }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(query.isEmpty ? "Search" : "Search: \(query)")
    }
}

/// One result: the kind's 12 point mark, the name in bold 13, the sub line in 11, and on a
/// selected artist, album or playlist the white chevron.
struct SearchRow: View {
    let result: Search.Result
    let selected: Bool

    var body: some View {
        HStack(spacing: 7) {
            SearchMark(result.kind).view(size: 12, color: selected ? .white : PocketSearch.mutedInk)
            VStack(alignment: .leading, spacing: 0) {
                FadeLine(Text(result.name).font(.helvetica(13, bold: true)))
                FadeLine(Text(result.detail).font(.helvetica(11)))
                    .foregroundStyle(selected ? Pocket.detailSelected : PocketSearch.faint)
            }
            Spacer(minLength: 0)
            // The list rule (Designer 2): a selected row that opens a list shows the white chevron; a song has none.
            if selected && result.kind != .song { IconView(.chevron, width: 8, height: 12) }
        }
        .padding(.leading, 9)
        .padding(.trailing, 10)
        .frame(height: PocketSearch.rowHeight)
        .foregroundStyle(selected ? Color.white : Pocket.ink)
        .background { if selected { Pocket.selection } }
        // `border-bottom: 1px solid rgba(0,0,0,0.04)`.
        .overlay(alignment: .bottom) { Color.black.opacity(0.04).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// "Type to search" with a key cap, or "Hmm, no luck" with a magnifier, centered under the field.
struct SearchMessage: View {
    let mark: SearchMark
    let words: Labels.SearchWords

    var body: some View {
        VStack(spacing: 0) {
            mark.view(size: 34, line: 2.2, color: PocketSearch.faint)
                .padding(.bottom, 6)
            Text(words.title).font(.helvetica(14, bold: true)).foregroundStyle(Pocket.ink)
            Text(words.line).font(.helvetica(11)).foregroundStyle(PocketSearch.mutedInk)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .padding(EdgeInsets(top: 18, leading: 12, bottom: 0, trailing: 12))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// The marks of card CS, from the try page's SVGs in a 24 unit view box.
enum SearchMark: Equatable {
    case song, artist, album, playlist
    /// The magnifier of the field and of "Hmm, no luck".
    case glass
    /// The key cap with an "A" of "Type to search".
    case key

    init(_ kind: Search.Kind) {
        switch kind {
        case .song: self = .song
        case .artist: self = .artist
        case .album: self = .album
        case .playlist: self = .playlist
        }
    }

    /// The mark at `size` points. `line` is the stroke width in view box units, where the SVG has one.
    @ViewBuilder func view(size: CGFloat, line: CGFloat = 2.4, color: Color) -> some View {
        let k = size / 24
        let scale = CGAffineTransform(scaleX: k, y: k)
        ZStack {
            switch self {
            case .song:
                Self.song.applying(scale).fill(color)
            case .artist:
                Self.artist.applying(scale).fill(color)
            case .album:
                Path(roundedRect: CGRect(x: 2.5, y: 2.5, width: 19, height: 19), cornerRadius: 2).applying(scale)
                    .stroke(color, lineWidth: 2.4 * k)
                Path(ellipseIn: CGRect(x: 8, y: 8, width: 8, height: 8)).applying(scale).fill(color)
            case .playlist:
                Self.playlist.applying(scale).fill(color)
            case .glass:
                Path(ellipseIn: CGRect(x: 3.5, y: 3.5, width: 13, height: 13)).applying(scale)
                    .stroke(color, lineWidth: line * k)
                Path { p in p.move(to: CGPoint(x: 15, y: 15)); p.addLine(to: CGPoint(x: 21, y: 21)) }.applying(scale)
                    .stroke(color, style: StrokeStyle(lineWidth: (line + 0.2) * k, lineCap: .round))
            case .key:
                Path(roundedRect: CGRect(x: 3, y: 3, width: 18, height: 18), cornerRadius: 4).applying(scale)
                    .stroke(color, lineWidth: line * k)
                Text("A").font(.helvetica(10.5 * k, bold: true)).foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private static var song: Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: 3.2, y: 15.2, width: 6, height: 6))
        p.addEllipse(in: CGRect(x: 14.2, y: 13.2, width: 6, height: 6))
        p.addRect(CGRect(x: 7.6, y: 4.8, width: 1.8, height: 13.4))
        p.addRect(CGRect(x: 18.6, y: 2.4, width: 1.8, height: 13.8))
        p.addLines([CGPoint(x: 7.6, y: 4.8), CGPoint(x: 20.4, y: 1.9), CGPoint(x: 20.4, y: 5.3), CGPoint(x: 7.6, y: 8.2)])
        p.closeSubpath()
        return p
    }

    private static var artist: Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: 7.5, y: 3, width: 9, height: 9))
        // "M3 22c0-5 4-8.5 9-8.5s9 3.5 9 8.5z"
        p.move(to: CGPoint(x: 3, y: 22))
        p.addCurve(to: CGPoint(x: 12, y: 13.5), control1: CGPoint(x: 3, y: 17), control2: CGPoint(x: 7, y: 13.5))
        p.addCurve(to: CGPoint(x: 21, y: 22), control1: CGPoint(x: 17, y: 13.5), control2: CGPoint(x: 21, y: 17))
        p.closeSubpath()
        return p
    }

    private static var playlist: Path {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 2, y: 4, width: 20, height: 2.6), cornerSize: CGSize(width: 1, height: 1))
        p.addRoundedRect(in: CGRect(x: 2, y: 10.7, width: 20, height: 2.6), cornerSize: CGSize(width: 1, height: 1))
        p.addRoundedRect(in: CGRect(x: 2, y: 17.4, width: 13, height: 2.6), cornerSize: CGSize(width: 1, height: 1))
        return p
    }
}

/// The letter strip A–Z 0–9 under the list, as decor (card CS). The letter of the last typed
/// key sits in the blue box in the middle. On a new letter the strip slides the short way round
/// in 0.15 s, ease-out; with Reduce Motion, and in snapshots, it moves at once.
struct LetterStrip: View {
    /// The letter's place in `Search.stripLetters`, from Core.
    let index: Int
    /// The strip's place in letters, counted on past Z: it slides from one to the next.
    @State private var place: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.animationTime) private var fixedTime

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient.vertical(Color(hex: 0xe9eef3), Color(hex: 0xc9d2db))
            Pocket.line.frame(height: 1)
            // `.hl`: 28 x 25 at x 136, 4 points under the top line.
            RoundedRectangle(cornerRadius: 5).fill(Pocket.selection)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                .frame(width: 28, height: 25)
                .offset(x: 136, y: 5)
            StripLetters(place: place ?? Double(index))
                .offset(y: 1)
        }
        .frame(width: Pocket.screenWidth, height: PocketSearch.stripHeight)
        .clipped()
        .onChange(of: index) { old, new in
            let n = Search.stripLetters.count
            var step = new - old
            if step > n / 2 { step -= n }
            if step < -n / 2 { step += n }
            let from = place ?? Double(old)
            let still = reduceMotion || fixedTime != nil
            withAnimation(still ? nil : .easeOut(duration: 0.15)) { place = from + Double(step) }
        }
        .accessibilityHidden(true)
    }
}

/// The strip's letters around `place`: 19 points apart, the one at `place` white and 17 points
/// big at the middle (x 150); the others 13 points, fading 11 % a letter, to 25 % at most.
struct StripLetters: View, Animatable {
    var place: Double

    nonisolated var animatableData: Double {
        get { place }
        set { place = newValue }
    }

    static let cell: CGFloat = 19

    var body: some View {
        let letters = Search.stripLetters
        let n = letters.count
        let first = Int(place.rounded(.down)) - 9
        ZStack(alignment: .topLeading) {
            ForEach(first...(first + 19), id: \.self) { k in
                let d = abs(Double(k) - place)
                let on = max(0, 1 - d)  // 1 at the middle, 0 a letter away
                Text(String(letters[((k % n) + n) % n]))
                    .font(.helvetica(CGFloat(13 + 4 * on), bold: true))
                    .foregroundStyle(on > 0.5 ? Color.white : Pocket.ink)
                    .opacity(d < 0.5 ? 1 : max(0.25, 1 - d * 0.11))
                    .frame(width: Self.cell, height: 34)
                    .offset(x: 150 - Self.cell / 2 + CGFloat(Double(k) - place) * Self.cell)
            }
        }
    }
}
