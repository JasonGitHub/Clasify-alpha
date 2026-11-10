import ClasifyCore
import SwiftUI

/// The bar for the playing song (Round 7 card W): a music note, the song and its artist, and
/// the time, 22.9 points tall with its line, like a row. With the Now Playing Bar setting on, it
/// shows under every list and inside Cover Flow's song panel (Round 11 card AK).
struct NowBar: View {
    let now: Labels.NowText
    let t: Double

    var body: some View {
        HStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // A music note, the same when paused: play and pause show only in the title bar.
                // Its middle sits on the middle of the text's x-height, as in the mockup.
                IconView(.barNote, width: 11, height: 11).accessibilityHidden(true)
                    .alignmentGuide(.firstTextBaseline) { _ in Pocket.barNoteBaseline }
                OnceLine(text: "\(now.title)\(now.artist.isEmpty ? "" : " — \(now.artist)")", size: 10.5)
                    .id("\(now.title)\u{1F}\(now.artist)")  // a new song starts its turns again
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Labels.time(t)).monospacedDigit()
        }
        // The note, the song, " — artist" and the time all share one style: 10.5 bold gray.
        .font(.helvetica(10.5, bold: true))
        .foregroundStyle(Color(hex: 0x5d6772))
        .padding(.leading, 9)
        .padding(.trailing, 8)
        .frame(height: Pocket.barHeight)  // 22.9 with the line over it, like a row
        .background(Color(hex: 0xe8eef3))
    }
}

/// One bold line that scrolls once in turn, like Now Playing's lines (card AA, change 115): no
/// "…", the last 22 points fade, it waits 1.5 s, scrolls once, then rests 8 s. Text that fits
/// stays still with no fade. It keeps the text's baseline, so the bar's note lines up with it.
struct OnceLine: View {
    let text: String
    let size: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.animationTime) private var fixedTime
    @State private var start = Date.timeIntervalSinceReferenceDate

    var body: some View {
        let width = NowLines.width(text, size: size)
        // A space gives the line its height and baseline; the text draws over it at its room's width.
        Text(" ")
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    let room = Double(geo.size.width)
                    let long = width > room
                    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !long || reduceMotion || fixedTime != nil)) { context in
                        let t = reduceMotion ? 0 : fixedTime ?? context.date.timeIntervalSinceReferenceDate - start
                        let shift = long && !reduceMotion ? Labels.nowScroll(widths: [width], room: room, at: t)?.shift ?? 0 : 0
                        if long {
                            Marquee.copies(Text(text), shift: shift).clipped().mask { FadeMask() }
                        } else {
                            Text(text).lineLimit(1)
                        }
                    }
                }
            }
            .accessibilityElement()
            .accessibilityLabel(text)
    }
}
