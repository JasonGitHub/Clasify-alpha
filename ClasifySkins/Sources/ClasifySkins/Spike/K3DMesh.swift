import CoreGraphics
import Foundation

/// SPIKE (CLA-101): the K.3D.1 body as a triangle mesh, ported from the About mock's frozen
/// `k3d_src.js` with `vr = 1` (design-review/about/k3d1-spike). Units are points. The body is
/// 366 x 613 x 62 with a corner radius of 34, centered on the origin, y up, the front at z = +31.
///
/// Each vertex is 12 floats: position (3), normal (3), uv (2), uv2 (2), weight (1), material (1).
/// Materials: 0 aluminium wall, 1 mirror steel, 2 seam, 3 front, 4 back.
struct K3DMesh {
    static let width = 366.0, height = 613.0, depth = 62.0, radius = 34.0
    /// Floats per vertex.
    static let stride = 12

    private(set) var vertices: [Float] = []
    private(set) var indices: [UInt32] = []

    var vertexCount: Int { vertices.count / Self.stride }

    init() {
        let w = Self.width, h = Self.height, t = Self.depth, r = Self.radius
        let corners = 24, keep = 0.45  // inner rings keep 45% of the corner radius change

        // The outline: corner centers and directions, clockwise from the top right (y up).
        var outline: [(cx: Double, cy: Double, ox: Double, oy: Double)] = []
        let centers = [(w / 2 - r, h / 2 - r, 0.0), (w / 2 - r, -(h / 2 - r), -90.0),
                       (-(w / 2 - r), -(h / 2 - r), -180.0), (-(w / 2 - r), h / 2 - r, -270.0)]
        for (cx, cy, a0) in centers {
            for i in 0...corners {
                let a = (a0 + 90 - 90 * Double(i) / Double(corners)) * .pi / 180
                outline.append((cx, cy, cos(a), sin(a)))
            }
        }

        // Profile rings, front to back: inset, z, normal angle (degrees: 90 faces the front, 0
        // out, -90 the back), material. K.3D.1: the front rolls into the side on a soft
        // elliptical edge, then the polished steel wraps the side and curves onto the back.
        var profile: [(inset: Double, z: Double, angle: Double, material: Int)] = []
        let a = 16.0, b = 6.5
        for i in 0...8 {
            let g = Double(i) / 8 * .pi / 2, sn = sin(g), c = cos(g)
            profile.append((a - a * sn, t / 2 - b + b * c, atan2(c / b, sn / a) * 180 / .pi, 3))
        }
        profile += [(0, t / 2 - b, 0, 0), (0, t / 2 - b - 2, 0, 0), (0, t / 2 - b - 2, 0, 2),
                    (0, t / 2 - b - 2.6, 0, 2), (0, t / 2 - b - 2.6, 0, 1), (0, -6.2, 0, 1)]
        for i in 1...14 {
            let s = Double(i) / 14 * .pi / 2
            let inset = 22 * (1 - cos(s)), z = -6.2 - 24.8 * sin(s)
            let nx = 24.8 * cos(s), nz = -22 * sin(s), l = hypot(nx, nz)
            profile.append((inset, z, atan2(nz / l, nx / l) * 180 / .pi, 1))
        }

        var rings: [[UInt32]] = []
        for (inset, z, angle, material) in profile {
            let na = angle * .pi / 180, ca = cos(na), sa = sin(na)
            var row: [UInt32] = []
            for (cx, cy, ox, oy) in outline {
                // The rings are not concentric: an inner ring keeps a larger corner, so the steel
                // turns the corner smoothly. The front roll is concentric.
                let sx: Double = cx < 0 ? -1 : 1, sy: Double = cy < 0 ? -1 : 1
                let kc = material == 3 ? 1 : keep, rr = r - kc * inset
                let x = sx * (w / 2 - r - (1 - kc) * inset) + ox * rr
                let y = sy * (h / 2 - r - (1 - kc) * inset) + oy * rr
                var uv = ((x + w / 2) / w, (h / 2 - y) / h), uv2 = uv, weight = 1.0
                if material == 1 || material == 2 {
                    // Steel never reads the texture's own mitred corners: it reads the finish at
                    // the same depth on the nearest side and top or bottom, blended by angle.
                    let rp = 39.0
                    func mu(_ v: Double) -> Double { (w / 2 - v) / w }
                    func mv(_ v: Double) -> Double { (h / 2 - v) / h }
                    let yc = max(-(h / 2 - rp), min(h / 2 - rp, y)), xc = max(-(w / 2 - rp), min(w / 2 - rp, x))
                    uv = (mu(sx * (w / 2 - inset)), mv(yc))
                    uv2 = (mu(xc), mv(sy * (h / 2 - inset)))
                    weight = ox * ox
                }
                row.append(vertex((x, y, z), (ox * ca, oy * ca, sa), uv, uv2, weight, material))
            }
            rings.append(row)
        }
        for k in 0..<(rings.count - 1) {
            let a = rings[k], b = rings[k + 1], n = a.count
            for i in 0..<n {
                let j = (i + 1) % n
                indices += [a[i], a[j], b[i], a[j], b[j], b[i]]
            }
        }
        cap(rings[0], z: t / 2, nz: 1, material: 3, mirror: false)  // the front face
        cap(rings[rings.count - 1], z: -t / 2, nz: -1, material: 4, mirror: true)  // the back face
    }

    private mutating func vertex(
        _ p: (Double, Double, Double), _ n: (Double, Double, Double), _ uv: (Double, Double),
        _ uv2: (Double, Double), _ weight: Double, _ material: Int
    ) -> UInt32 {
        let index = UInt32(vertexCount)
        vertices += [p.0, p.1, p.2, n.0, n.1, n.2, uv.0, uv.1, uv2.0, uv2.1, weight, Double(material)].map { Float($0) }
        return index
    }

    private mutating func cap(_ row: [UInt32], z: Double, nz: Double, material: Int, mirror: Bool) {
        let w = Self.width, h = Self.height
        let center = vertex((0, 0, z), (0, 0, nz), (0.5, 0.5), (0.5, 0.5), 1, material)
        var points: [UInt32] = []
        for i in row {
            let x = Double(vertices[Int(i) * Self.stride]), y = Double(vertices[Int(i) * Self.stride + 1])
            let uv = (mirror ? (w / 2 - x) / w : (x + w / 2) / w, (h / 2 - y) / h)
            points.append(vertex((x, y, z), (0, 0, nz), uv, uv, 1, material))
        }
        for i in points.indices {
            let j = (i + 1) % points.count
            indices += nz > 0 ? [center, points[j], points[i]] : [center, points[i], points[j]]
        }
    }
}

/// SPIKE (CLA-101): the mock's `flip()`. The device turns 180° in 0.82 s with a 2.5%
/// overshoot, settles by 1.0 s, and is pushed back by up to 70 pt while it turns.
public struct K3DFlip {
    static let turn = 0.82, duration = 1.0, lift = 70.0

    /// The angle the last turn started from and goes to, in degrees: 0 is the front, 180 the back.
    private(set) var from = 0.0, to = 0.0
    /// When the last turn started.
    private(set) var start = Date.distantPast
    /// A live picture of the device for the 3D front's screen, taken when the turn started.
    public private(set) var screen: CGImage?

    public init() {}

    /// The back shows, or the device turns to it.
    public var toBack: Bool { to > 90 }

    /// Starts a turn to the other side, from where the device is now.
    public mutating func toggle(at now: Date, screen: CGImage?) {
        let current = pose(at: now).angle
        from = current
        to = toBack ? 0 : 180
        start = now
        if toBack { self.screen = screen }
    }

    /// No turn runs: the device rests on one side.
    func isResting(at now: Date) -> Bool { now.timeIntervalSince(start) >= Self.duration }

    /// The front shows flat, with no turn running: the 2D skin can show.
    public func restsOnFront(at now: Date) -> Bool { !toBack && now.timeIntervalSince(start) >= Self.duration }

    func pose(at now: Date) -> (angle: Double, lift: Double) {
        let t = now.timeIntervalSince(start)
        if t >= Self.duration { return (to, 0) }
        let angle: Double
        if t < Self.turn {
            angle = from + (to - from) * Self.ease(t / Self.turn) * 1.025
        } else {
            let q = min(1, (t - Self.turn) / (Self.duration - Self.turn))
            angle = to + (to - from) * 0.025 * (1 - q) * (1 - q)
        }
        let p = min(1, max(0, t / Self.turn))
        return (angle, Self.lift * sin(.pi * p))
    }

    static func ease(_ p: Double) -> Double { p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2 }
}
