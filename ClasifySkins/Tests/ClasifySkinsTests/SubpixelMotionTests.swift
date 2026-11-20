import AppKit
import SwiftUI
import Testing

/// Jason (build 390): the turn hint's key moved in whole-pixel steps. This compares ways to
/// move a small key (a white face with a gray label) by a fraction of a point, drawn with
/// ImageRenderer at 2x as in `TurnHintMotionTests`. It prints, for each way, how many of 30
/// steps of 4/30 pt moved the drawn label. A way that does not snap moves it every step.
@Suite @MainActor struct SubpixelMotionTests {
    private static func face() -> some View {
        Text("command").font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color(red: 0.36, green: 0.39, blue: 0.42))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(EdgeInsets(top: 0, leading: 10, bottom: 8, trailing: 0))
            .frame(width: 78, height: 60)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white))
    }

    private struct Shift: GeometryEffect {
        var y: Double
        var animatableData: Double { get { y } set { y = newValue } }
        func effectValue(size: CGSize) -> ProjectionTransform { ProjectionTransform(CGAffineTransform(translationX: 0, y: y)) }
    }

    private static func variant(_ name: String, _ y: Double) -> AnyView {
        switch name {
        case "offset": AnyView(face().offset(y: y))
        case "transformEffect": AnyView(face().transformEffect(CGAffineTransform(translationX: 0, y: y)))
        case "offset+drawingGroup": AnyView(face().offset(y: y).frame(width: 100, height: 100).drawingGroup())
        case "transformEffect+drawingGroup": AnyView(face().transformEffect(CGAffineTransform(translationX: 0, y: y)).frame(width: 100, height: 100).drawingGroup())
        case "drawingGroup+offset": AnyView(face().drawingGroup().offset(y: y))
        case "geometryEffect": AnyView(face().modifier(Shift(y: y)))
        case "visualEffect": AnyView(face().visualEffect { content, _ in content.offset(y: y) })
        case "canvas":
            AnyView(Canvas { context, _ in
                context.translateBy(x: 0, y: y)
                context.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: 78, height: 60), cornerRadius: 12), with: .color(.white))
                let text = context.resolve(Text("command").font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(red: 0.36, green: 0.39, blue: 0.42)))
                context.draw(text, at: CGPoint(x: 10, y: 52), anchor: .bottomLeading)
            }.frame(width: 78, height: 64))
        default: AnyView(EmptyView())
        }
    }

    /// The label's centre of ink, in points from the top of the 100 x 100 pt picture.
    private static func labelY(_ view: some View) -> Double {
        let renderer = ImageRenderer(content: view.frame(width: 78, height: 64, alignment: .top)
            .padding(.top, 10).padding(.leading, 10)
            .frame(width: 100, height: 100, alignment: .topLeading)
            .background(Color(red: 0.16, green: 0.2, blue: 0.28)))
        renderer.scale = 2
        guard let image = renderer.cgImage else { return .nan }
        let bitmap = NSBitmapImageRep(cgImage: image)
        var weight = 0.0, sum = 0.0
        for py in 88..<136 {
            for px in 28..<120 {
                guard let c = bitmap.colorAt(x: px, y: py)?.usingColorSpace(.sRGB) else { continue }
                let ink = max(0, 0.8 - (c.redComponent + c.greenComponent + c.blueComponent) / 3)
                weight += ink
                sum += ink * (Double(py) + 0.5)
            }
        }
        return weight > 0 ? sum / weight / 2 : .nan
    }

    /// The label's centre of ink in a 2x bitmap of a 100 x 100 pt picture.
    private static func ink(_ bitmap: NSBitmapImageRep) -> Double {
        var weight = 0.0, sum = 0.0
        for py in 88..<136 {
            for px in 28..<120 {
                guard let c = bitmap.colorAt(x: px, y: py)?.usingColorSpace(.sRGB) else { continue }
                let ink = max(0, 0.8 - (c.redComponent + c.greenComponent + c.blueComponent) / 3)
                weight += ink
                sum += ink * (Double(py) + 0.5)
            }
        }
        return weight > 0 ? sum / weight / 2 : .nan
    }

    /// A 2x bitmap, 100 x 100 pt, filled dark, for AppKit drawing.
    private static func bitmap() -> (NSBitmapImageRep, NSGraphicsContext) {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 200, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: 100, height: 100)
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        context.cgContext.setFillColor(CGColor(red: 0.16, green: 0.2, blue: 0.28, alpha: 1))
        context.cgContext.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        return (rep, context)
    }

    /// The face in a real clear panel, 100 x 100 pt: in a container view whose layer moves it
    /// down by `y` (a Core Animation transform), or by `.offset` when `layer` is false.
    private static func panel(_ y: Double, layer: Bool) -> Double {
        let content = face().offset(y: layer ? 0 : y).frame(width: 78, height: 64, alignment: .top)
            .padding(.top, 10).padding(.leading, 10).frame(width: 100, height: 100, alignment: .topLeading)
        let host = NSHostingView(rootView: content)
        host.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        let box = NSView(frame: host.frame)
        box.wantsLayer = true
        box.addSubview(host)
        let panel = NSPanel(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.contentView = box
        defer { panel.close() }
        box.layoutSubtreeIfNeeded()
        host.layer?.setAffineTransform(CGAffineTransform(translationX: 0, y: layer ? -y : 0))  // the layer's y goes up
        let (rep, context) = bitmap()
        if layer {
            // `render(in:)` draws the layer tree with its transforms. The container is not
            // flipped: its y goes up, as in the bitmap.
            let cg = context.cgContext
            cg.saveGState()
            cg.scaleBy(x: 2, y: 2)
            box.layer?.render(in: cg)
            cg.restoreGState()
        } else {
            box.cacheDisplay(in: box.bounds, to: rep)
        }
        return ink(rep)
    }

    /// The face rendered once to an image, then drawn by a Canvas at `y`.
    private static func canvasImage(_ y: Double, _ image: CGImage) -> Double {
        labelY(Canvas { context, _ in
            context.draw(Image(decorative: image, scale: 2), in: CGRect(x: 0, y: y, width: 78, height: 60))
        }.frame(width: 78, height: 64))
    }

    @Test func whichWaysMoveByAFractionOfAPoint() {
        let renderer = ImageRenderer(content: Self.face())
        renderer.scale = 2
        let still = renderer.cgImage
        let ways: [(String, (Double) -> Double)] = [
            ("offset", { Self.labelY(Self.variant("offset", $0)) }),
            ("canvas-image", { y in still.map { Self.canvasImage(y, $0) } ?? .nan }),
            ("panel-offset", { Self.panel($0, layer: false) }),
            ("panel-layer", { Self.panel($0, layer: true) }),
        ]
        for (name, measure) in ways {
            let ys = (0...30).map { measure(4 * Double($0) / 30) }
            let moved = zip(ys, ys.dropFirst()).filter { $1 > $0 + 0.01 }.count
            print("subpixel-motion \(name): moved \(moved) of 30 steps; y:", ys.map { String(format: "%.3f", $0) }.joined(separator: " "))
        }
        #expect(Bool(true))
    }
}
