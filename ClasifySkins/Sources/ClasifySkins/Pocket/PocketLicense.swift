import ClasifyCore
import SwiftUI

/// The text of one license (card BF, change 213): its name, the license text, then the names
/// of the parts under it. The lines come wrapped from scripts/licenses.py. The wheel moves the
/// page one 14 pt line a step, as a list moves (`Frame.off`).
struct PocketLicense: View {
    let state: AppState
    let index: Int

    static let line: CGFloat = 14, top: CGFloat = 5

    var body: some View {
        let off = state.top.off, steps = AppState.licenseSteps(index)
        let license = License.all.indices.contains(index) ? License.all[index] : nil
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                Text(license?.name ?? "").font(.helvetica(14, bold: true)).foregroundStyle(Pocket.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.line * CGFloat(AppState.licenseNameLines))
                ForEach(Array((license?.lines ?? []).enumerated()), id: \.offset) { _, text in
                    Text(text).font(.helvetica(11)).foregroundStyle(Pocket.gray)
                        .lineLimit(1)
                        .frame(height: Self.line)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, Self.top)
            .frame(width: Pocket.screenWidth, alignment: .leading)
            .offset(y: -CGFloat(off) * Self.line)
            .animation(.easeOut(duration: 0.15), value: off)
            if steps > 0 { scrollBar(off, steps: steps, lines: license?.lines.count ?? 0) }
        }
        .frame(width: Pocket.screenWidth, height: Pocket.listHeight, alignment: .topLeading)
        .clipped()
        .accessibilityElement(children: .combine)
    }

    /// The list scroll bar: 3 pt on the right, its thumb as long as the share of lines shown.
    private func scrollBar(_ off: Int, steps: Int, lines: Int) -> some View {
        GeometryReader { geo in
            let track = geo.size.height
            let all = CGFloat(lines + AppState.licenseNameLines)
            let thumb = track * CGFloat(AppState.licenseShownLines) / all
            Capsule().fill(Color(hex: 0x5d6772))
                .frame(height: thumb)
                .offset(y: (track - thumb) * CGFloat(off) / CGFloat(steps))
                .animation(.easeOut(duration: 0.15), value: off)
        }
        .frame(width: 3)
        .padding(.vertical, 2)
        .padding(.trailing, 1.5)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .opacity(state.scrollUntil > 0 ? 1 : 0)
        .animation(.easeInOut(duration: 0.4), value: state.scrollUntil > 0)
        .accessibilityHidden(true)
    }
}
