import CoreGraphics
import SwiftUI

/// SPIKE (CLA-101): the 2D device's drop shadow, drawn under the 3D body while it turns or
/// rests on the back (card BL v3, shadow option 1, Jason 17:30 JST 11-14). It has the same
/// values and the same hidden shape as `PocketSkin`'s own shadow: a black copy of the body that
/// starts 20 pt lower, with a shadow of radius 20 that falls 20 pt. Here that copy is the 3D
/// body's outline at the pose, so the shadow gets narrow with the body. At angle 0 and no lift
/// the outline is the 2D body's own shape, so the shadow is the same as the 2D one.
///
/// The black copy itself never shows: everything inside the body's outline is cut away. The
/// body covers that area anyway.
struct K3DShadow: View {
    let angle: Double, lift: Double
    let black: Bool

    /// Room round the device, so the shadow and its cut have the whole area to draw on.
    static let room: CGFloat = 120

    var body: some View {
        let size = PocketSkin.size, r = Self.room
        let copy = Self.outline(angle: angle, lift: lift, drop: PocketSkin.shadowDrop)
        let cut = Self.outline(angle: angle, lift: lift, drop: 0)
        copy.offsetBy(dx: r, dy: r)
            .fill(Color.black)
            .shadow(color: PocketSkin.shadowColor(black ? 1 : 0), radius: 20, y: 20)
            .mask {
                Path { p in
                    p.addRect(CGRect(x: 0, y: 0, width: size.width + 2 * r, height: size.height + 2 * r))
                    p.addPath(cut.offsetBy(dx: r, dy: r))
                }
                .fill(style: FillStyle(eoFill: true))
            }
            .frame(width: size.width + 2 * r, height: size.height + 2 * r)
            .padding(-r)
            .allowsHitTesting(false)
    }

    /// The body's outline on screen at a pose, in points in the 2D device's frame (366 x 613,
    /// from the top left), with its top `drop` points lower. It is the hull of three sections of
    /// the body: the flat front, the end of the straight aluminium wall (70% of the depth back),
    /// and the flat back, which the steel curves in to by 14 pt. Each section is the 2D body's
    /// own rounded rectangle, projected with the renderer's camera.
    static func outline(angle: Double, lift: Double, drop: CGFloat) -> Path {
        let size = PocketSkin.size
        let t = K3DMesh.depth
        let sections: [(z: Double, inset: CGFloat)] = [(t / 2, 0), (t / 2 - 0.7 * t, 0), (-t / 2, 14)]
        var points: [CGPoint] = []
        for section in sections {
            let rect = CGRect(x: section.inset, y: section.inset + drop,
                              width: size.width - 2 * section.inset, height: size.height - drop - 2 * section.inset)
            for p in Self.points(RoundedRectangle(cornerRadius: max(34 - section.inset, 0)).path(in: rect)) {
                points.append(project(p, z: section.z, angle: angle, lift: lift))
            }
        }
        return Path { path in
            let hull = Self.hull(points)
            guard let first = hull.first else { return }
            path.move(to: first)
            for p in hull.dropFirst() { path.addLine(to: p) }
            path.closeSubpath()
        }
    }

    /// A point of the 2D frame, at depth `z` in the body (the front is +34), on screen. The
    /// renderer's camera: the body turns about its vertical axis, is pushed back by `lift`, and
    /// the eye is 2600 pt from its center. The flat front at rest shows at 1 pt per pt.
    static func project(_ p: CGPoint, z: Double, angle: Double, lift: Double) -> CGPoint {
        let size = PocketSkin.size
        let x = Double(p.x) - size.width / 2, y = size.height / 2 - Double(p.y)
        let a = angle * .pi / 180
        let xe = cos(a) * x + sin(a) * z
        let ze = -sin(a) * x + cos(a) * z - Double(K3DRenderer.distance) - lift
        let s = (Double(K3DRenderer.distance) - K3DMesh.depth / 2) / -ze
        return CGPoint(x: size.width / 2 + xe * s, y: size.height / 2 - y * s)
    }

    /// The path's points, with its curves cut into lines of at most 0.01 pt error.
    static func points(_ path: Path) -> [CGPoint] {
        var out: [CGPoint] = []
        path.cgPath.flattened(threshold: 0.01).applyWithBlock { element in
            let e = element.pointee
            if e.type == .moveToPoint || e.type == .addLineToPoint { out.append(e.points[0]) }
        }
        return out
    }

    /// The convex hull, counterclockwise on screen (monotone chain).
    static func hull(_ points: [CGPoint]) -> [CGPoint] {
        let sorted = points.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
        guard sorted.count > 2 else { return sorted }
        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower: [CGPoint] = [], upper: [CGPoint] = []
        for p in sorted {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        for p in sorted.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }
}
