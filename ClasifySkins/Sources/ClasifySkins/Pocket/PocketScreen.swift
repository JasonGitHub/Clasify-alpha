import ClasifyCore
import SwiftUI

/// The Pocket colors, from the mockup's inline styles.
enum Pocket {
    static let ink = Color(hex: 0x1b1f24)
    static let gray = Color(hex: 0x3d454e)
    static let line = Color(hex: 0x8f99a3)
    static let frame = Color(hex: 0x4b5056)
    static var selection: LinearGradient { .vertical(Color(hex: 0x5aa3f0), Color(hex: 0x1f6fd1)) }
    static let offline = Color(hex: 0xa3261c)
}

/// The LCD: the header, then a list, a message or Now Playing, then the bar and the toast.
struct PocketScreen: View {
    let state: AppState

    private var top: Frame { state.top }
    /// The bar shows the playing track on every screen but Now Playing and the login wait.
    private var hasBar: Bool { state.current != nil && top.screen != .now && top.screen != .auth }

    var body: some View {
        VStack(spacing: 0) {
            header
            Pocket.line.frame(height: 1)
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            if hasBar, let now = Labels.now(in: state) {
                Pocket.line.frame(height: 1)
                bar(now)
            }
        }
        .overlay(alignment: .bottom) {
            if !state.toast.isEmpty { toast }
        }
        .frame(width: 252, height: 200)
        .background {
            // The glass and its inset shadow. As in the mockup, the header, the selected row,
            // the bar and the scroll bar paint over the shadow.
            LinearGradient.vertical(Color(hex: 0xf4f8fb), Color(hex: 0xd6e2ec))
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.black.opacity(0.25), lineWidth: 6)
                        .blur(radius: 3)
                        .offset(y: 2)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .padding(2)
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Pocket.frame, lineWidth: 2) }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .foregroundStyle(Pocket.ink)
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack(spacing: 0) {
            PlayMarkView(mark: Labels.playMark(in: state), size: 9)
                .frame(width: 24, alignment: .leading)
            Text(Labels.title(top.screen, in: state))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            Text(state.offline ? "OFF" : "")
                .font(.helvetica(9, bold: true))
                .foregroundStyle(Pocket.offline)
                .frame(width: 24, alignment: .trailing)
        }
        .font(.helvetica(11, bold: true))
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(LinearGradient.vertical(.white, Color(hex: 0xc9d2db)))
    }

    @ViewBuilder private var content: some View {
        if let message = Labels.message(for: top, in: state) {
            MessageView(message: message)
        } else if top.screen == .now {
            PocketNowPlaying(state: state)
        } else {
            PocketList(state: state)
        }
    }

    private func bar(_ now: Labels.NowText) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                PlayMarkView(mark: Labels.playMark(in: state), size: 10)
                Text("\(now.title)\(now.artist.isEmpty ? "" : " — \(now.artist)")").lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Labels.time(state.t)).monospacedDigit()
        }
        .font(.helvetica(10))
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(Color(hex: 0xe8eef3))
    }

    private var toast: some View {
        Text(state.toast)
            .font(.helvetica(11))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)  // 26 points tall, as in the mockup
            .padding(.horizontal, 8)
            .background(Color(hex: 0x1b1f24, opacity: 0.88), in: RoundedRectangle(cornerRadius: 4))
            .padding(.horizontal, 14)
            .padding(.bottom, 26)
    }
}

/// The rows of a list screen, with the selection and a scroll bar for long lists.
struct PocketList: View {
    let state: AppState

    var body: some View {
        let top = state.top
        let rows = state.rows(for: top)
        let first = top.off  // the reducer keeps the selection inside state.shownRows
        let shown = Array(rows.indices.dropFirst(first).prefix(state.shownRows))
        let scrolls = rows.count > state.shownRows
        VStack(spacing: 0) {
            ForEach(shown, id: \.self) { index in
                PocketRow(text: Labels.row(rows[index], on: top.screen, in: state),
                          selected: index == top.sel, scrolls: scrolls)
            }
            if top.screen == .login {
                Text("Opens your browser to sign in. Playlists are read-only.")
                    .font(.helvetica(11))
                    .lineSpacing(2)
                    .foregroundStyle(Pocket.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding([.horizontal, .top], 10)
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .topTrailing) {
            if scrolls { scrollBar(first: first, count: rows.count) }
        }
    }

    private func scrollBar(first: Int, count: Int) -> some View {
        GeometryReader { geo in
            let height = geo.size.height
            Capsule().fill(Color(hex: 0x5d6772))
                .frame(height: height * min(1, CGFloat(state.shownRows) / CGFloat(count)))
                .offset(y: height * CGFloat(first) / CGFloat(count))
        }
        .frame(width: 5)
        .background(Capsule().fill(Color(hex: 0xc3ccd5)))
        .padding(.vertical, 2)
        .padding(.trailing, 2)
        .accessibilityHidden(true)
    }
}

struct PocketRow: View {
    let text: Labels.RowText
    let selected: Bool
    /// A scroll bar shows, so the row leaves room for it.
    let scrolls: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(text.label)
                .font(.helvetica(13, bold: true))
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                if !text.value.isEmpty { Text(text.value).font(.helvetica(12)) }
                if let mark = text.mark { PlayMarkView(mark: mark, size: 12) }
                if text.opens { IconView(.chevron, width: 7, height: 10) }
            }
            .fixedSize()
        }
        .padding(.leading, 10)
        .padding(.trailing, scrolls ? 14 : 10)
        .frame(height: 24)
        .foregroundStyle(selected ? Color.white : Pocket.ink)
        .background { if selected { Pocket.selection } }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A screen with no list: a spinner, a title and a line of help.
struct MessageView: View {
    let message: Labels.Message

    var body: some View {
        VStack(spacing: 8) {
            if message.spinner { Spinner() }
            Text(message.title).font(.helvetica(14, bold: true))
            if !message.body.isEmpty {
                Text(message.body)
                    .font(.helvetica(11))
                    .lineSpacing(2)
                    .foregroundStyle(Pocket.gray)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 18)
    }
}

/// The mockup's spinner: a gray ring with a dark top quarter that turns every 0.8 s.
struct Spinner: View {
    var body: some View {
        TimelineView(.animation) { context in
            let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.8) / 0.8
            ZStack {
                Circle().stroke(Color(hex: 0x9aa6b2), lineWidth: 2)
                Circle().trim(from: 0.625, to: 0.875).stroke(Pocket.ink, lineWidth: 2)
            }
            .rotationEffect(.degrees(turn * 360))
        }
        .frame(width: 20, height: 20)  // with the 2 point ring: 22 points, as CSS content-box gives
        .padding(1)
        .accessibilityHidden(true)
    }
}

/// ▶ while the track plays, or two bars while it is paused. The bars are a shape, because
/// the "❚❚" glyph falls back to a font that draws one solid square on some Macs.
struct PlayMarkView: View {
    let mark: Labels.PlayMark?
    /// The text size beside it. The bars are this tall.
    let size: CGFloat

    var body: some View {
        switch mark {
        case .playing:
            Text("▶").font(.helvetica(size, bold: true))
        case .paused:
            HStack(spacing: size * 4 / 9) {
                Rectangle().frame(width: size / 3, height: size)
                Rectangle().frame(width: size / 3, height: size)
            }
            .accessibilityLabel("Paused")
        case nil:
            EmptyView()
        }
    }
}
