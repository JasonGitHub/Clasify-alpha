import ClasifyCore
import SwiftUI

/// Now Playing: the shuffle and repeat icons, the tilted cover, the track, and the progress,
/// volume or slider row.
struct PocketNowPlaying: View {
    let state: AppState
    let input: @MainActor (Action) -> Void
    @Environment(\.artwork) private var artwork
    /// The last cover that showed, by cover ID. It stays while the next track's cover loads,
    /// and while the same cover loads again, so the square does not flash.
    @State private var lastCover: CoverArt.Shown?

    var body: some View {
        if let now = Labels.now(in: state) {
            VStack(spacing: 2) {
                icons
                HStack(alignment: .top, spacing: 12) {
                    if state.showArt { cover(now) }
                    VStack(alignment: state.showArt ? .leading : .center, spacing: 3) {
                        Text(now.title).font(.helvetica(14, bold: true))
                        Text(now.artist).font(.helvetica(12)).foregroundStyle(Pocket.gray)
                        Text(now.list).font(.helvetica(12)).foregroundStyle(Pocket.gray)
                        Text(now.count).font(.helvetica(11)).foregroundStyle(Color(hex: 0x4b535c)).padding(.top, 6)
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: state.showArt ? .leading : .center)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                bottom(now)
            }
            .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        }
    }

    /// Shuffle and repeat, dark when on and dimmed when off. A click changes them.
    private var icons: some View {
        HStack(spacing: 10) {
            Button { input(.toggleShuffle) } label: {
                IconView(.shuffle, width: 14, height: 12).foregroundStyle(iconColor(state.shuffle))
                    .widerHitArea()
            }
            .accessibilityLabel(state.shuffle ? "Shuffle on" : "Shuffle off")
            Button { input(.cycleRepeat) } label: {
                IconView(.repeatMode, width: 14, height: 12)
                    .foregroundStyle(iconColor(state.repeatMode != .off))
                    .overlay(alignment: .topTrailing) {
                        if state.repeatMode == .one {
                            Text("1").font(.helvetica(8, bold: true)).foregroundStyle(Pocket.ink).offset(x: 4, y: -4)
                        }
                    }
                    .widerHitArea()
            }
            .accessibilityLabel("Repeat \(state.repeatMode.rawValue)")
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 14, maxHeight: 14, alignment: .trailing)
    }

    private func iconColor(_ on: Bool) -> Color { on ? Pocket.ink : Color(hex: 0x9aa3ad) }

    /// The 84 point cover with its reflection, turned in 3D as in the mockup.
    private func cover(_ now: Labels.NowText) -> some View {
        let fresh = artwork.image(for: now.coverID)
        let shown = CoverArt.shown(
            fresh: fresh, coverID: now.coverID, pending: artwork.isPending(now.coverID), last: lastCover)
        let art = CoverArt(image: shown)
        return VStack(spacing: 1) {
            art.frame(width: 84, height: 84).clipped()
            art.reflection(side: 84, height: 24)
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
            HStack(spacing: 6) {
                IconView(.speaker, width: 10, height: 10)
                Meter(fraction: Double(state.volume) / 100)
                IconView(.speakerLoud, width: 12, height: 10)
            }
            .frame(height: 24)
            .accessibilityElement()
            .accessibilityLabel("Volume \(state.volume) percent")
        } else {
            let fraction = now.duration > 0 ? state.t / now.duration : 0
            HStack(spacing: 6) {
                Text(Labels.time(state.t)).frame(width: 28, alignment: .leading)
                if state.nowMode == .scrub { ScrubTrack(fraction: fraction) } else { Meter(fraction: fraction) }
                Text("-" + Labels.time(now.duration - state.t)).frame(width: 32, alignment: .trailing)
            }
            .font(.helvetica(10, bold: true))
            .monospacedDigit()
            .frame(height: 24)
        }
    }
}

/// The shuffle or repeat slider: the stops over a thin track with a round knob, and the name under it.
struct SliderView: View {
    let slider: Labels.Slider

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                ForEach(Array(slider.stops.enumerated()), id: \.offset) { i, stop in
                    if i > 0 { Spacer(minLength: 0) }
                    Text(stop)
                }
            }
            .font(.helvetica(10, bold: true))
            let fraction = slider.stops.count > 1 ? Double(slider.index) / Double(slider.stops.count - 1) : 0
            Track(fraction: fraction) {
                Circle().fill(Pocket.gloss)
                    .overlay { Circle().strokeBorder(Color(hex: 0x1f5fb8), lineWidth: 1) }
                    .frame(width: 14, height: 14)
            }
            .padding(.horizontal, 6)
            Text(slider.name).font(.helvetica(10)).foregroundStyle(Pocket.gray)
        }
        .frame(height: 42)
        .accessibilityElement()
        .accessibilityLabel("\(slider.name): \(slider.stops[slider.index])")
    }
}

/// The 8 point progress and volume bar: a light groove with a glossy blue fill.
struct Meter: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            LinearGradient.vertical(Color(hex: 0xf6f8fa), Color(hex: 0xdfe5ea))
                .overlay(alignment: .leading) {
                    Pocket.gloss.frame(width: geo.size.width * min(max(fraction, 0), 1))
                }
                .overlay { Rectangle().strokeBorder(Color(hex: 0xaab4be), lineWidth: 1) }
        }
        .frame(height: 8)
    }
}

/// The scrub bar: a blue diamond on a thin light track.
struct ScrubTrack: View {
    let fraction: Double

    var body: some View {
        Track(fraction: fraction) {
            Diamond().fill(Pocket.gloss).frame(width: 12, height: 14)
        }
        .accessibilityLabel("Scrubbing")
    }
}

/// A 6 point rounded track with a marker centered at `fraction` of its width.
struct Track<Marker: View>: View {
    let fraction: Double
    @ViewBuilder let marker: () -> Marker

    var body: some View {
        GeometryReader { geo in
            Capsule().fill(LinearGradient.vertical(.white, Color(hex: 0xe3e8ed)))
                .overlay { Capsule().strokeBorder(Color(hex: 0xb7c0c9), lineWidth: 1) }
                .overlay(alignment: .leading) {
                    marker().fixedSize().frame(width: 0).offset(x: geo.size.width * min(max(fraction, 0), 1))
                }
        }
        .frame(height: 6)
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
