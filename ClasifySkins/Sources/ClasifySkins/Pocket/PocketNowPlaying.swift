import ClasifyCore
import SwiftUI

/// Now Playing: the place in the list, the cover, the track, and the progress or volume bar.
struct PocketNowPlaying: View {
    let state: AppState
    @Environment(\.artwork) private var artwork
    /// The last cover that showed. It stays while the next track's cover loads, so the
    /// square does not flash between two covers.
    @State private var lastCover: CGImage?

    var body: some View {
        if let now = Labels.now(in: state) {
            VStack(spacing: 0) {
                HStack {
                    Text(now.count)
                    Spacer()
                    Text(Labels.flags(in: state))
                }
                .font(.helvetica(10))
                .foregroundStyle(Pocket.gray)
                HStack(spacing: 10) {
                    if state.showArt {
                        let fresh = artwork.image(for: now.coverID)
                        let shown = Cover.shown(fresh: fresh, pending: artwork.isPending(now.coverID), last: lastCover)
                        Cover(artist: now.artist, image: shown)
                            .onChange(of: fresh.map(ObjectIdentifier.init), initial: true) {
                                if let fresh { lastCover = fresh }
                            }
                    }
                    VStack(alignment: state.showArt ? .leading : .center, spacing: 3) {
                        Text(now.title).font(.helvetica(14, bold: true))
                        Text(now.artist).font(.helvetica(12))
                        Text(now.list).font(.helvetica(11)).foregroundStyle(Pocket.gray)
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: state.showArt ? .leading : .center)
                }
                .frame(maxHeight: .infinity)
                // The reducer sets overlayUntil when the wheel changes the volume and clears it on a later tick.
                if let slider = Labels.slider(in: state) {
                    SliderView(slider: slider)
                } else if state.nowMode == .volume && state.overlayUntil > 0 {
                    volume
                } else {
                    progress(now)
                }
            }
            .padding(EdgeInsets(top: 8, leading: 12, bottom: 10, trailing: 12))
        }
    }

    private var volume: some View {
        HStack(spacing: 6) {
            IconView(.speaker, width: 10, height: 10)
            Meter(fraction: Double(state.volume) / 100, fill: AnyShapeStyle(Pocket.selection))
            IconView(.speakerLoud, width: 12, height: 10)
        }
        .frame(height: 22)
        .accessibilityElement()
        .accessibilityLabel("Volume \(state.volume) percent")
    }

    private func progress(_ now: Labels.NowText) -> some View {
        let scrub = state.nowMode == .scrub
        let fraction = now.duration > 0 ? state.t / now.duration : 0
        return VStack(spacing: 3) {
            Meter(fraction: fraction, fill: scrub ? AnyShapeStyle(Color(hex: 0x9aa6b2)) : AnyShapeStyle(Pocket.selection),
                  marker: scrub)
            HStack {
                Text(Labels.time(state.t))
                Spacer()
                if scrub { Text("SCRUB") }
                Spacer()
                Text("-" + Labels.time(now.duration - state.t))
            }
            .font(.helvetica(10))
            .monospacedDigit()
        }
        .frame(height: 22)
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
            GeometryReader { geo in
                let fraction = slider.stops.count > 1 ? CGFloat(slider.index) / CGFloat(slider.stops.count - 1) : 0
                Capsule().fill(LinearGradient.vertical(.white, Color(hex: 0xe3e8ed)))
                    .overlay { Capsule().strokeBorder(Color(hex: 0xb7c0c9), lineWidth: 1) }
                    .overlay(alignment: .leading) {
                        Circle().fill(Pocket.gloss)
                            .overlay { Circle().strokeBorder(Color(hex: 0x1f5fb8), lineWidth: 1) }
                            .frame(width: 14, height: 14)
                            .offset(x: geo.size.width * fraction - 7)
                    }
            }
            .frame(height: 6)
            .padding(.horizontal, 6)
            Text(slider.name).font(.helvetica(10)).foregroundStyle(Pocket.gray)
        }
        .frame(height: 42)
        .accessibilityElement()
        .accessibilityLabel("\(slider.name): \(slider.stops[slider.index])")
    }
}

/// An 8 px bar with a fill, and a diamond at the fill's end while scrubbing.
struct Meter: View {
    let fraction: Double
    let fill: AnyShapeStyle
    var marker = false

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width * min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Rectangle().fill(.white)
                Rectangle().fill(fill).frame(width: width)
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .overlay { RoundedRectangle(cornerRadius: 2).strokeBorder(Pocket.frame, lineWidth: 1) }
            .overlay(alignment: .leading) {
                if marker {
                    Diamond().fill(Pocket.ink).frame(width: 10, height: 12).offset(x: width - 5)
                }
            }
        }
        .frame(height: 8)
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

/// The album cover. Until it has loaded, or when it cannot load, the mockup's square shows:
/// a color from the artist’s name with a music note on it.
struct Cover: View {
    let artist: String
    var image: CGImage?

    /// The image to draw: the track's cover, or while it loads the last cover that showed.
    /// A track with no cover, or whose cover failed, gets the square at once.
    static func shown(fresh: CGImage?, pending: Bool, last: CGImage?) -> CGImage? {
        fresh ?? (pending ? last : nil)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color(hex: Labels.cover(for: artist)))
            .overlay {
                if let image {
                    // A new image fades in over 0.2 s instead of a hard cut.
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                        .id(ObjectIdentifier(image))
                        .transition(.opacity)
                } else {
                    IconView(.note, width: 26, height: 26).foregroundStyle(.white.opacity(0.85))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: image.map(ObjectIdentifier.init))
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .overlay { RoundedRectangle(cornerRadius: 2).strokeBorder(Pocket.frame, lineWidth: 1) }
            .frame(width: 76, height: 76)
            .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
            .accessibilityHidden(true)
    }
}
