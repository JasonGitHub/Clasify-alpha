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
                    .foregroundColor(Color(red: 0.36, green: 0.39, blue: 0.42)))
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

    @Test func whichWaysMoveByAFractionOfAPoint() {
        let names = ["offset", "transformEffect", "offset+drawingGroup", "transformEffect+drawingGroup",
                     "drawingGroup+offset", "geometryEffect", "visualEffect", "canvas"]
        for name in names {
            let ys = (0...30).map { Self.labelY(Self.variant(name, 4 * Double($0) / 30)) }
            let moved = zip(ys, ys.dropFirst()).filter { $1 > $0 + 0.01 }.count
            print("subpixel-motion \(name): moved \(moved) of 30 steps; y:", ys.map { String(format: "%.3f", $0) }.joined(separator: " "))
        }
        #expect(Bool(true))
    }
}
