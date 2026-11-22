import AppKit
import ClasifyCore
import SwiftUI

/// Now Playing, laid out like the photo (round 7, card U): the shuffle and repeat icons at the top
/// right, the tilted 127 point cover on the left, the track on its right, and the progress,
/// volume or slider row at the bottom. The points are the mockup's, from the top left of the
/// 300 x 206 area under the title bar.
struct PocketNowPlaying: View {
    let state: AppState
    let input: @MainActor (Action) -> Void
    /// The cover is not drawn while Cover Flow's middle cover still flies to its place (card CI).
    var hidesCover = false
    @Environment(\.artwork) private var artwork
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The last cover that showed, by cover ID. It stays while the next track's cover loads,
    /// and while the same cover loads again, so the square does not flash.
    @State private var lastCover: CoverArt.Shown?

    /// The cover's side, and the left edge of the four bars and their width.
    static let coverSide: CGFloat = 126.6
    static let barLeft: CGFloat = 54.6, barWidth: CGFloat = 191.4

    var body: some View {
        if let now = Labels.now(in: state) {
            let art = state.showsNowPlayingArt
            ZStack(alignment: .topLeading) {
                if art { cover(now).offset(x: 9, y: 14.6).opacity(hidesCover ? 0 : 1) }
                // With no cover, the text is centered across the screen.
                let left: CGFloat = art ? 150.6 : 8
                Group {
                    // Keyed by the track, and by its text, which can arrive after the track starts.
                    NowLines(now: now, art: art)
                        .id([state.current?.playlist, state.current?.track, now.title, now.artist, now.list])
                    line(now.count, size: 11.7, color: Color(hex: 0x292929), top: 91.4)
                }
                .frame(width: Pocket.screenWidth - left - 8, alignment: art ? .leading : .center)
                .offset(x: left)
                icons
                bottom(now)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// One line of the track's text. The mockup sets each line's box to its font size, at `top`.
    private func line(_ text: String, size: CGFloat, color: Color, top: CGFloat) -> some View {
        FadeLine(Text(text)).font(.helvetica(size, bold: true)).foregroundStyle(color)
            .frame(height: size)
            .offset(y: top)
    }

    /// Shuffle and repeat, dark when on and dimmed when off, 12 points from the right and 7 under
    /// the title bar. A click changes them.
    private var icons: some View {
        HStack(spacing: 10) {
            Button { input(.toggleShuffle) } label: {
                ModeIcon(kind: .shuffle).foregroundStyle(iconColor(state.shuffle))
                    .widerHitArea()
            }
            .accessibilityLabel(state.shuffle ? "Shuffle on" : "Shuffle off")
            Button { input(.cycleRepeat) } label: {
                ModeIcon(kind: state.repeatMode == .one ? .repeatOne : .repeatAll)
                    .foregroundStyle(iconColor(state.repeatMode != .off))
                    .widerHitArea()
            }
            .accessibilityLabel("Repeat \(state.repeatMode.rawValue)")
        }
        .buttonStyle(.plain)
        .frame(height: 14)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 12)
        .offset(y: 7)
    }

    private func iconColor(_ on: Bool) -> Color { on ? Color(hex: 0x4f5965) : Color(hex: 0xb4bcc5) }

    /// The 126.6 point cover with its 22 point reflection, tilted as in the photo.
    private func cover(_ now: Labels.NowText) -> some View {
        let fresh = artwork.image(for: now.coverID)
        let shown = CoverArt.shown(
            fresh: fresh, coverID: now.coverID, pending: artwork.isPending(now.coverID), last: lastCover)
        let art = CoverArt(image: shown, notesSize: 80)
        let side = Self.coverSide
        return VStack(spacing: 0) {
            art.frame(width: side, height: side).clipped()
            art.reflection(side: side, height: 22, strength: 0.4)
        }
        .animation(.easeInOut(duration: 0.2), value: shown.map(ObjectIdentifier.init))
        .modifier(Tilt())
        .accessibilityHidden(true)
        .onChange(of: fresh.map(ObjectIdentifier.init), initial: true) {
            if let fresh, let id = now.coverID { lastCover = CoverArt.Shown(coverID: id, image: fresh) }
        }
    }

    /// The slider, the volume bar after a volume turn, or the progress bar.
    @ViewBuilder private func bottom(_ now: Labels.NowText) -> some View {
        if let slider = Labels.slider(in: state) {
            SliderView(slider: slider)
        } else if state.nowMode == .volume && state.overlayUntil > 0 {
            // The reducer sets overlayUntil when the wheel changes the volume and clears it on a later tick.
            barRow {
                IconView(.speaker, width: 13, height: 13)
            } bar: {
                SoftBar(fraction: Double(state.volume) / 100)
            } trailing: {
                IconView(.speakerLoud, width: 16, height: 14)
            }
            .foregroundStyle(.black)
            .accessibilityElement()
            .accessibilityLabel("Volume \(state.volume) percent")
        } else {
            let fraction = now.duration > 0 ? state.t / now.duration : 0
            barRow {
                Text(Labels.time(state.t))
            } bar: {
                if state.nowMode == .scrub { ScrubTrack(fraction: fraction) } else { SoftBar(fraction: fraction) }
            } trailing: {
                Text("-" + Labels.time(now.duration - state.t))
            }
            .font(.helvetica(11.7, bold: true))
            .foregroundStyle(.black)
            .monospacedDigit()
            // Card BA, change 195: a play/pause or next tip takes the time bar's place. The bar
            // fades out over 0.4 s, and comes back after the tip.
            .opacity(tipShows ? 0 : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: tipShows)
        }
    }

    private var tipShows: Bool {
        // The tour's steps 2 and 3 too (card BA.1): no bar and no times under the tip.
        // CLA-163, card CE look A: the menu bar hint's device label too.
        state.hintTip && state.toast.isEmpty
            && ([.playPause, .next, .tourNext, .tourMenu, .tourMenuBar].contains(state.hint))
    }

    /// The bottom row: a 33.6 point slot, the 191.4 point bar and a 38.4 point slot, 21 points
    /// from the left, 22 points tall and 13.6 above the bottom.
    private func barRow<L: View, B: View, T: View>(
        @ViewBuilder leading: () -> L, @ViewBuilder bar: () -> B, @ViewBuilder trailing: () -> T
    ) -> some View {
        HStack(spacing: 0) {
            leading().frame(width: Self.barLeft - 21, alignment: .leading)
            bar().frame(width: Self.barWidth)
            trailing().frame(width: 38.4, alignment: .trailing)
        }
        .padding(.leading, 21)
        .frame(height: 22)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 13.6)
    }
}

/// The shuffle or repeat slider, with its bar exactly where the progress bar is (Jason, 22:16 JST): the stops over the bar, each
/// centered on its place and black when chosen, a round knob, and the name under the bar.
struct SliderView: View {
    let slider: Labels.Slider

    var body: some View {
        let count = slider.stops.count
        let fraction = count > 1 ? Double(slider.index) / Double(count - 1) : 0
        let left = PocketNowPlaying.barLeft, width = PocketNowPlaying.barWidth
        ZStack(alignment: .topLeading) {
            ForEach(Array(slider.stops.enumerated()), id: \.offset) { i, stop in
                let x = left + width * (count > 1 ? CGFloat(i) / CGFloat(count - 1) : 0)
                Text(stop)
                    .font(.helvetica(11.7, bold: true))
                    .foregroundStyle(i == slider.index ? Color.black : Color(hex: 0x8a9099))
                    .fixedSize()
                    .frame(width: 0, height: 11.7)  // centered on x
                    .offset(x: x, y: 159.3)
            }
            Pocket.barTrack
                .frame(width: width, height: Pocket.softBarHeight)
                .overlay(alignment: .leading) {
                    Circle().fill(Pocket.soft)
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                        .frame(width: 16, height: 16)
                        .frame(width: 0)
                        .offset(x: width * fraction)
                }
                .offset(x: left, y: 174.8)
            Text(slider.name)
                .font(.helvetica(11.7, bold: true))
                .foregroundStyle(Color(hex: 0x1e1e1e))
                .frame(width: Pocket.screenWidth, height: 11.7)
                .offset(y: 191.5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement()
        .accessibilityLabel("\(slider.name): \(slider.stops[slider.index])")
    }
}

/// The 13.2 point progress and volume bar: white, with no border, and a soft blue fill.
struct SoftBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            Pocket.barTrack
                .overlay(alignment: .leading) {
                    Pocket.soft.frame(width: geo.size.width * min(max(fraction, 0), 1))
                }
        }
        .frame(height: Pocket.softBarHeight)
    }
}

/// The scrub bar: a soft blue 14 x 18 diamond on the empty bar.
struct ScrubTrack: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            Pocket.barTrack
                .overlay(alignment: .leading) {
                    Diamond().fill(Pocket.soft).frame(width: 14, height: 18)
                        .frame(width: 0)
                        .offset(x: geo.size.width * min(max(fraction, 0), 1))
                }
        }
        .frame(height: Pocket.softBarHeight)
        .accessibilityLabel("Scrubbing")
    }
}

struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.addLines([
                CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.midY),
                CGPoint(x: rect.midX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.midY),
            ])
            p.closeSubpath()
        }
    }
}

extension View {
    /// A plain button takes a click only on the drawn pixels of its label. This makes the whole
    /// box around the label, plus `inset` points on each side, take the click, with no change
    /// to the layout. The shuffle and repeat icons are 10 points apart, so 5 points on each side
    /// keep their targets apart: each is 24 x 22 points.
    func widerHitArea(_ inset: CGFloat = 5) -> some View {
        padding(inset).contentShape(Rectangle()).padding(-inset)
    }
}

/// The title, artist and playlist lines (round 8, card AA). A line wider than its room has no
/// "…": it is cut, and its last 22 points fade out. A line that fits has no fade. The long
/// lines scroll once each, in turn, with a rest between, as `Labels.nowScroll` says; the fade
/// stays at the right edge while the text moves. A new track makes a new view, so the turns
/// start again.
/// One measured width per line decides both the fade and the turns, so they always agree.
struct NowLines: View {
    let now: Labels.NowText
    let art: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.animationTime) private var fixedTime
    @State private var start = Date.timeIntervalSinceReferenceDate

    private var lines: [(text: String, size: Double, color: Color, top: CGFloat)] {
        [(now.title, 15.1, .black, 36.3), (now.artist, 11.7, Color(hex: 0x1e1e1e), 57.2), (now.list, 11.7, Color(hex: 0x1e1e1e), 74)]
    }

    /// A line's width in bold Helvetica Neue, the font `Font.helvetica` draws it in.
    static func width(_ text: String, size: Double) -> Double {
        let font = NSFont(name: "HelveticaNeue-Bold", size: size) ?? .boldSystemFont(ofSize: size)
        return Double(ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width))
    }

    var body: some View {
        let room = Labels.nowRoom(art: art)
        let widths = lines.map { Self.width($0.text, size: $0.size) }
        let still = Labels.nowScroll(widths: widths, room: room, at: 0) == nil
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: still || reduceMotion || fixedTime != nil)) { context in
            let t = reduceMotion ? 0 : fixedTime ?? context.date.timeIntervalSinceReferenceDate - start
            let scroll = reduceMotion ? nil : Labels.nowScroll(widths: widths, room: room, at: t)
            ZStack(alignment: .topLeading) {
                ForEach(0..<3, id: \.self) { i in
                    let l = lines[i]
                    let shift = scroll.map { $0.line == i ? $0.shift : 0 } ?? 0
                    line(l.text, size: l.size, color: l.color, top: l.top, long: widths[i] > room, shift: shift)
                }
            }
        }
    }

    @ViewBuilder
    private func line(_ text: String, size: Double, color: Color, top: CGFloat, long: Bool, shift: Double) -> some View {
        let label = Text(text).font(.helvetica(size, bold: true)).foregroundStyle(color)
        Group {
            if long {
                // Cut, not truncated, and it starts at the left even when the lines are centered.
                Marquee.copies(label, shift: shift)
                    .clipped()
                    .mask { FadeMask() }
            } else {
                label.lineLimit(1).frame(maxWidth: .infinity, alignment: art ? .leading : .center)
            }
        }
        .frame(height: size)
        .offset(y: top)
    }
}
