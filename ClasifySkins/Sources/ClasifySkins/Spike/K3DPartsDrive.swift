import Foundation

/// CLA-129 (K.3D.11): the drive's other side, from `about/k3d11/tools/k3d_src3.js` (the `D11`
/// path, Jason's photos 11-17). The lid is the drive's flat steel face; its pressed lines are
/// drawn in the shader. On it lies a thick U of blue foam: a ring between two outlines, thin at
/// the bottom, with soft edges and a big rounded hole that follows the spindle shape.
extension K3DMesh {
    /// A rounded box's signed distance (`sdr`): its centre `c`, half sizes `h`, corner radius `r`.
    static func roundBox(_ x: Double, _ y: Double, _ c: (Double, Double), _ h: (Double, Double), _ r: Double) -> Double {
        let dx = abs(x - c.0) - h.0 + r, dy = abs(y - c.1) - h.1 + r
        return hypot(max(dx, 0), max(dy, 0)) + min(max(dx, dy), 0) - r
    }

    mutating func addDriveLidFoam() {
        // The foam's outer outline, its top-right corner cut round; and its hole.
        func fo(_ x: Double, _ y: Double) -> Double {
            max(Self.roundBox(x, y, (0, -80), (140, 192), 22), x > 50 && y > 22 ? hypot(x - 50, y - 22) - 90 : -1e9)
        }
        func fi(_ x: Double, _ y: Double) -> Double {
            min(Self.roundBox(x, y, (0, -130), (77, 90), 14), Self.roundBox(x, y, (0, -60), (77, 111), 66))
        }
        let cx = 0.0, cy = -80.0, rays = 180, z0 = 14.0, z1 = 19.0, ch = 1.6
        // Where a ray from the centre at angle `a` leaves the shape (bisection, as the mock).
        func hit(_ f: (Double, Double) -> Double, _ a: Double) -> Double {
            var lo = 0.0, hi = 500.0
            for _ in 0..<40 {
                let md = (lo + hi) / 2
                if f(cx + md * cos(a), cy + md * sin(a)) < 0 { lo = md } else { hi = md }
            }
            return lo
        }
        func grad(_ f: (Double, Double) -> Double, _ p: (Double, Double)) -> (Double, Double) {
            let e = 0.5, gx = f(p.0 + e, p.1) - f(p.0 - e, p.1), gy = f(p.0, p.1 + e) - f(p.0, p.1 - e)
            let l = hypot(gx, gy)
            return l == 0 ? (gx, gy) : (gx / l, gy / l)
        }
        typealias P = (Double, Double)
        // Per ray: the outer edge, its chamfer's top, the hole's edge, its chamfer's top, and the
        // outward normals of the outline and of the hole.
        var rs: [(o: P, oi: P, i: P, io: P, no: P, ni: P)] = []
        for k in 0..<rays {
            let a = Double(k) / Double(rays) * 2 * .pi, c = cos(a), s = sin(a)
            let jo = 0.6 * sin(a * 37) + 0.45 * sin(a * 91 + 1.3), ji = 0.6 * sin(a * 43 + 0.7) + 0.45 * sin(a * 97)
            let ro = hit(fo, a) + jo, ri = hit(fi, a) + ji
            func at(_ r: Double) -> P { (cx + r * c, cy + r * s) }
            rs.append((o: at(ro), oi: at(ro - ch), i: at(ri), io: at(ri + ch), no: grad(fo, at(ro)), ni: grad(fi, at(ri))))
        }
        func v(_ p: P, _ z: Double, _ n: (Double, Double, Double)) -> UInt32 { vertex((p.0, p.1, z), n, uvOf(p.0, p.1), 37) }
        func quad(_ a: UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32) { triangles([a, b, c, a, c, d]) }
        for k in 0..<rays {
            let a = rs[k], b = rs[(k + 1) % rays], up = (0.0, 0.0, 1.0)
            let ca = (a.no.0 * 0.7, a.no.1 * 0.7, 0.7), cb = (b.no.0 * 0.7, b.no.1 * 0.7, 0.7)
            let da = (-a.ni.0 * 0.7, -a.ni.1 * 0.7, 0.7), db = (-b.ni.0 * 0.7, -b.ni.1 * 0.7, 0.7)
            quad(v(a.oi, z1, up), v(b.oi, z1, up), v(b.io, z1, up), v(a.io, z1, up))
            quad(v(a.o, z1 - ch, ca), v(b.o, z1 - ch, cb), v(b.oi, z1, cb), v(a.oi, z1, ca))
            let ao = (a.no.0, a.no.1, 0.0), bo = (b.no.0, b.no.1, 0.0)
            quad(v(a.o, z0, ao), v(b.o, z0, bo), v(b.o, z1 - ch, bo), v(a.o, z1 - ch, ao))
            quad(v(b.i, z1 - ch, db), v(a.i, z1 - ch, da), v(a.io, z1, da), v(b.io, z1, db))
            let ai = (-a.ni.0, -a.ni.1, 0.0), bi = (-b.ni.0, -b.ni.1, 0.0)
            quad(v(b.i, z0, bi), v(a.i, z0, ai), v(a.i, z1 - ch, ai), v(b.i, z1 - ch, bi))
        }
    }
}
