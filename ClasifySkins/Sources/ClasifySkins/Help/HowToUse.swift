import SwiftUI

/// Help › How to Use myPod (Round 14 card BC, change 152, with the BC.1 look, change 196):
/// each wheel action with its mark, how to do it, and its keys. Then Shuffle / Repeat, which
/// are not on the wheel. It shows words only and sends no actions.
public struct HowToUse: View {
    public static let title = "How to Use myPod"
    public static let width: CGFloat = 549

    public init() {}

    /// One row: the wheel mark, the action, how to do it, and the keys.
    struct Row: Sendable {
        var mark: Mark
        var action: String
        var how: String
        var keys: [Key]
    }

    /// The wheel's marks, in the blue of the selection, as SF Symbols where they match.
    enum Mark: Sendable {
        case turn, select, menu, playPause, prevNext, shuffle
    }

    /// A key as printed on the Mac keyboard: a word, a letter, or an arrow.
    enum Key: Sendable {
        case word(String), letter(String), arrow(String)  // arrow: an SF Symbol name
    }

    static let wheelRows = [
        Row(mark: .turn, action: "Turn", how: "Swipe with two fingers, or drag in a circle",
            keys: [.arrow("arrow.up"), .arrow("arrow.down")]),
        Row(mark: .select, action: "Select", how: "Click the center", keys: [.word("return")]),
        Row(mark: .menu, action: "Back", how: "Click MENU at the top", keys: [.word("esc")]),
        Row(mark: .playPause, action: "Play / Pause", how: "Click the bottom", keys: [.word("space")]),
        Row(mark: .prevNext, action: "Previous / Next", how: "Click the left or right side",
            keys: [.arrow("arrow.left"), .arrow("arrow.right")]),
    ]
    static let otherRows = [
        Row(mark: .shuffle, action: "Shuffle / Repeat", how: "Click their marks on Now Playing, or press S or R",
            keys: [.letter("S"), .letter("R")]),
    ]

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Use the wheel, the trackpad or the keys.")
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: 0x5d6772))
                .padding(EdgeInsets(top: 14, leading: 16, bottom: 10, trailing: 16))
            ForEach(Self.wheelRows.indices, id: \.self) { row(Self.wheelRows[$0]) }
            Text("Not on the wheel")  // a Mac section label
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: 0x8a929b))
                .padding(EdgeInsets(top: 16, leading: 16, bottom: 5, trailing: 16))
            ForEach(Self.otherRows.indices, id: \.self) { row(Self.otherRows[$0]) }
            Spacer().frame(height: 8)
        }
        .frame(width: Self.width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(.white)
    }

    /// 42 points tall. The hairline starts at the text, after the mark.
    private func row(_ row: Row) -> some View {
        HStack(spacing: 12) {
            mark(row.mark).frame(width: 30, height: 30)
            HStack(spacing: 10) {
                Text(row.action)
                    .font(.helvetica(13, bold: true))
                    .foregroundStyle(Color(hex: 0x1b1f24))
                    .frame(width: 118, alignment: .leading)
                Text(row.how)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: 0x5d6772))
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    ForEach(row.keys.indices, id: \.self) { keyCap(row.keys[$0]) }
                }
            }
            .padding(.trailing, 16)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .top) { Rectangle().fill(Color(hex: 0xdfe3e7)).frame(height: 0.5) }
        }
        .padding(.leading, 16)
        .frame(height: 42)
        .accessibilityElement(children: .combine)
    }

    /// Only the mark, in blue #1f6fd1, with no shape behind it, at one weight.
    private func mark(_ mark: Mark) -> some View {
        Group {
            switch mark {
            case .turn: Image(systemName: "arrow.triangle.2.circlepath")
            case .select: Image(systemName: "record.circle")
            case .menu: Text("MENU").font(.system(size: 6.3, weight: .bold))
            case .playPause: Image(systemName: "playpause.fill")
            case .prevNext:
                HStack(spacing: 6) {
                    Image(systemName: "backward.end.fill")
                    Image(systemName: "forward.end.fill")
                }
                .font(.system(size: 10, weight: .medium))  // 25 points wide in all, as printed on the wheel
            case .shuffle: Image(systemName: "shuffle")
            }
        }
        .font(.system(size: 13.5, weight: .medium))
        .foregroundStyle(Color(hex: 0x1f6fd1))
        .accessibilityHidden(true)
    }

    /// A key cap like a real Mac key: 22 points tall, corner 5, white with a hairline edge and
    /// a 1 point soft shadow under it.
    private func keyCap(_ key: Key) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5)
        return Group {
            switch key {
            case .word(let word): Text(word).font(.system(size: 10.5, weight: .medium)).tracking(0.2).padding(.horizontal, 7)
            case .letter(let letter): Text(letter).font(.system(size: 11, weight: .medium))
            case .arrow(let name): Image(systemName: name).font(.system(size: 9, weight: .light))
            }
        }
        .foregroundStyle(Color(hex: 0x3d454e))
        .frame(minWidth: 22, minHeight: 22, maxHeight: 22)
        .background {
            shape.fill(LinearGradient(colors: [.white, Color(hex: 0xf7f8f9)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.14), radius: 0, y: 1)
                .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
        }
        .overlay { shape.strokeBorder(Color.black.opacity(0.16), lineWidth: 0.5) }
    }
}
