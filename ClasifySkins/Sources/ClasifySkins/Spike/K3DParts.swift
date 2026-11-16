import Foundation

/// CLA-105 (card BT, change 308): the parts that only Take apart shows, ported from the
/// `k3d_src3.js` that Jason tried (design-review/beta-page/v3/k3d8, the `data-edge="parts"` path,
/// lines 103 to 224). Units are points, as in `K3DMesh`. Nothing here draws while the device is
/// closed: the renderer draws only the first `closedIndexCount` indices.
///
/// Parts: 0 the shell's inside (its inner skin, the battery, the flex cables, the jack and hold
/// block), 1 the plate's inner skin, 2 the window's back, 3 the wheel's back, 4 the screen module
/// and its shield plate, 5 the button's back, 6 the frame, 7 the drive, 8 the foam pad, 9 the logic
/// board. The materials are the mock's (above 10.5); the shader colors them in a later PR.
extension K3DMesh {
    // The mock's short helpers, with its argument order.

    /// A flat face that looks to the front (`disc`).
    mutating func d(_ o: [SIMD4<Double>], _ z: Double, _ m: Int, _ cx: Double, _ cy: Double) {
        disc(o, z: z, material: m, center: (cx, cy))
    }

    /// A flat face that looks to the back (`discB`).
    mutating func dB(_ o: [SIMD4<Double>], _ z: Double, _ m: Int, _ cx: Double, _ cy: Double) {
        let c = vertex((cx, cy, z), (0, 0, -1), uvOf(cx, cy), m)
        let ids = o.map { vertex(($0.x, $0.y, z), (0, 0, -1), uvOf($0.x, $0.y), m) }
        for i in ids.indices { triangles([c, ids[(i + 1) % ids.count], ids[i]]) }
    }

    /// A wall along an outline (`band`), from `top` down to `bottom`.
    mutating func bd(_ o: [SIMD4<Double>], _ top: Double, _ bottom: Double, _ m: Int, inward: Bool = false) {
        band(o, top: { _, _ in top }, bottom: bottom, material: m, inward: inward)
    }

    /// A block: its top and four sides (`box`).
    mutating func bx(_ x0: Double, _ x1: Double, _ y0: Double, _ y1: Double, _ z0: Double, _ z1: Double, _ m: Int) {
        func q(_ p: [(Double, Double, Double)], _ n: (Double, Double, Double)) {
            let i = p.map { vertex($0, n, uvOf($0.0, $0.1), m) }
            triangles([i[0], i[1], i[2], i[0], i[2], i[3]])
        }
        q([(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], (0, 0, 1))
        q([(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)], (1, 0, 0))
        q([(x0, y1, z0), (x0, y0, z0), (x0, y0, z1), (x0, y1, z1)], (-1, 0, 0))
        q([(x1, y1, z0), (x0, y1, z0), (x0, y1, z1), (x1, y1, z1)], (0, 1, 0))
        q([(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)], (0, -1, 0))
    }

    /// A block with its back face too (`box6`), the back in `mb` when given.
    mutating func bx6(
        _ x0: Double, _ x1: Double, _ y0: Double, _ y1: Double, _ z0: Double, _ z1: Double, _ m: Int, _ mb: Int? = nil
    ) {
        bx(x0, x1, y0, y1, z0, z1, m)
        let q = [(x0, y1, z0), (x1, y1, z0), (x1, y0, z0), (x0, y0, z0)].map { vertex($0, (0, 0, -1), uvOf($0.0, $0.1), mb ?? m) }
        triangles([q[0], q[1], q[2], q[0], q[2], q[3]])
    }

    /// A printed label on a chip (`lab`, material 41): its text is cell `k` of the label texture.
    mutating func lab(_ x0: Double, _ x1: Double, _ y0: Double, _ y1: Double, _ z: Double, back: Bool, _ k: Double = 0) {
        let corners: [(Double, Double, Double, Double)] = back
            ? [(x0, y1, 1, 0), (x1, y1, 0, 0), (x1, y0, 0, 1), (x0, y0, 1, 1)]
            : [(x0, y0, 0, 1), (x1, y0, 1, 1), (x1, y1, 1, 0), (x0, y1, 0, 0)]
        let q = corners.map { vertex(($0.0, $0.1, z), (0, 0, back ? -1 : 1), uvOf($0.0, $0.1), 41, uv2: ($0.2 + 2 * k, $0.3)) }
        triangles([q[0], q[1], q[2], q[0], q[2], q[3]])
    }

    /// A flat piece with a real outline (`slab`): its front, its wall and its back.
    mutating func slab(
        _ o: [SIMD4<Double>], _ cx: Double, _ cy: Double, _ z0: Double, _ z1: Double, _ m: Int, _ mb: Int? = nil, _ ms: Int? = nil
    ) {
        d(o, z1, m, cx, cy)
        bd(o, z1, z0, ms ?? m)
        dB(o, z0, mb ?? m, cx, cy)
    }

    static func rr(_ cx: Double, _ cy: Double, _ hx: Double, _ hy: Double, _ r: Double, _ step: Double) -> [SIMD4<Double>] {
        roundedRect(cx, cy, hx, hy, r, step: step)
    }

    /// A rounded rectangle about the origin with points on its corners only (`rrN`).
    static func rrN(_ hx: Double, _ hy: Double, _ r: Double) -> [SIMD4<Double>] {
        var o: [SIMD4<Double>] = []
        for (ax, ay, a0) in [(hx - r, hy - r, 0.0), (-(hx - r), hy - r, 90.0), (-(hx - r), -(hy - r), 180.0), (hx - r, -(hy - r), 270.0)] {
            for i in 0...8 {
                let a = (a0 + 90 * Double(i) / 8) * .pi / 180
                o.append(SIMD4(ax + r * cos(a), ay + r * sin(a), cos(a), sin(a)))
            }
        }
        return o
    }

    private func float(_ i: UInt32, _ k: Int) -> Double { Double(vertices[Int(i) * Self.stride + k]) }

    /// A copy of each vertex of `part`'s triangles in the first `capped` indices, `depth` pt in
    /// along its normal and facing the other way, in `material`; then the same triangles wound
    /// the other way. The mock's inner skins of the plate (1.2 pt, material 21) and the shell
    /// (1 pt, material 34).
    private mutating func skin(part skinPart: Int, capped: Int, depth: Double, material: Int) -> [UInt32: UInt32] {
        var twin: [UInt32: UInt32] = [:]
        for t in Swift.stride(from: 0, to: capped, by: 3) {
            let tri = [indices[t], indices[t + 1], indices[t + 2]]
            guard tri.allSatisfy({ Int(float($0, 12)) == skinPart }) else { continue }
            for i in tri where twin[i] == nil {
                let n = (float(i, 3), float(i, 4), float(i, 5))
                twin[i] = vertex(
                    (float(i, 0) - depth * n.0, float(i, 1) - depth * n.1, float(i, 2) - depth * n.2), (-n.0, -n.1, -n.2),
                    (float(i, 6), float(i, 7)), material)
            }
            triangles([twin[tri[0]]!, twin[tri[2]]!, twin[tri[1]]!])
        }
        return twin
    }

    /// The flat rim that closes a sheet at its edge ring, between the ring and its twins.
    private mutating func rim(_ row: [UInt32], twin: [UInt32: UInt32], nz: Double, material: Int) {
        let o = row.map { vertex((float($0, 0), float($0, 1), float($0, 2)), (0, 0, nz), (float($0, 6), float($0, 7)), material) }
        let q = row.map { i -> UInt32 in
            let j = twin[i] ?? i
            return vertex((float(j, 0), float(j, 1), float(i, 2)), (0, 0, nz), (float(i, 6), float(i, 7)), material)
        }
        for i in row.indices {
            let j = (i + 1) % row.count
            triangles([o[i], o[j], q[i], o[j], q[j], q[i], o[i], q[i], o[j], o[j], q[i], q[j]])
        }
    }

    mutating func addParts(capped: Int, plateRim: [UInt32], shellRim: [UInt32]) {
        let t = Self.depth, zl = t / 2 - 0.3, zw = t / 2 - 1.6, zb = t / 2 - 14
        let wx = Self.wheelCenter.x, wy = Self.wheelCenter.y
        let circle = Self.circle, rr = Self.rr

        // The inner skins: the plate is a 1.2 pt sheet, the shell a 1 pt sheet.
        part = 1
        let plate = skin(part: 1, capped: capped, depth: 1.2, material: 21)
        rim(plateRim, twin: plate, nz: -1, material: 21)
        part = 0
        let shell = skin(part: 0, capped: capped, depth: 1, material: 34)
        rim(shellRim, twin: shell, nz: 1, material: 34)

        // 2 the window: its clear edge and the ink border on its back.
        part = 2
        let wo = rr(0, 161.25, 156.5, 119.25, 7, 4)
        bd(wo, zl - 1.2, zl - 1.5, 22)
        dB(wo, zl - 1.5, 23, 0, 161.25)

        // 4 the screen module: the LCD panel in a thin steel frame, a metal back, and the ribbon.
        part = 4
        let so = rr(0, 161.5, 154, 116, 4, 6)
        d(so, zl - 5, 3, 0, 161.5)
        bd(so, zl - 5, zl - 9, 17)
        dB(so, zl - 9, 27, 0, 161.5)
        for sx in [-1.0, 1] {
            for y in [66.0, 250] {
                let a = sx < 0 ? -163.0 : 154
                bx6(a, a + 9, y, y + 16, zl - 8.5, zl - 6.5, 17)
            }
        }
        let ribbon = (0...10).map { i -> (Double, Double) in
            let s = Double(i) / 10
            return (45.5 - 70 * s, zl - 8.6 - 9 * s * s)
        }
        for i in 0..<10 {
            let (y0, z0) = ribbon[i], (y1, z1) = ribbon[i + 1], l = hypot(y1 - y0, z1 - z0)
            let n = (0.0, (z1 - z0) / l, -(y1 - y0) / l), m = i > 7 ? 20 : 16
            let xa = i > 5 ? -63.0 : -66, xb = i > 5 ? -5.0 : 84
            let a = vertex((xa, y0, z0), n, (0, 0), m), b = vertex((xb, y0, z0), n, (1, 0), m)
            let c = vertex((xb, y1, z1), n, (1, 1), m), e = vertex((xa, y1, z1), n, (0, 1), m)
            triangles([a, b, c, a, c, e, a, c, b, a, e, c])
        }

        // 3 the wheel's back: the flex sheet with the button domes, four pegs, the small parts.
        part = 3
        let wh = circle(wx, wy, 112.8, 128)
        bd(wh, zw - 2.5, zw - 3, 28)
        bd(circle(wx, wy, 41.7, 96), zw, zw - 3, 28, inward: true)
        dB(wh, zw - 3, 24, wx, wy)
        for (ax, ay) in [(78.0, 0.0), (-78, 0), (0, 78), (0, -78)] {
            let nb = circle(ax, -127 + ay, 5, 18)
            dB(nb, zw - 4.4, 24, ax, -127 + ay)
            bd(nb, zw - 3, zw - 4.4, 24)
        }
        bx6(-185, -106, -112, -88, zw - 3.5, zw - 3.2, 16)
        let wp = rr(-208, -132, 26, 30, 8, 6)
        d(wp, zw - 3.2, 16, -208, -132)
        bd(wp, zw - 3.2, zw - 3.5, 16)
        dB(wp, zw - 3.5, 16, -208, -132)
        bx6(-244, -204, -104, -66, zw - 3.5, zw - 3.2, 16)
        bx6(-226, -204, -66, -58, zw - 3.5, zw - 3.2, 16)
        bx6(-222, -192, -149, -115, zw - 3.2, zw - 1.7, 14)
        let label = [(-222.0, -149.0, 0.0, 1.0), (-192, -149, 1, 1), (-192, -115, 1, 0), (-222, -115, 0, 0)]
            .map { vertex(($0.0, $0.1, zw - 1.68), (0, 0, 1), uvOf($0.0, $0.1), 41, uv2: ($0.2, $0.3)) }
        triangles([label[0], label[1], label[2], label[0], label[2], label[3]])
        for i in 0..<3 { bx(-240, -234, -78 - Double(i) * 9, -73 - Double(i) * 9, zw - 3.2, zw - 2.7, 15) }

        // 5 the button's back.
        part = 5
        let bt = circle(wx, wy, 41.8, 128)
        bd(bt, zw - 3, zw - 4, 29)
        dB(bt, zw - 4, 25, wx, wy)

        addFrame(zb: zb, zl: zl)
        addBoard(zb: zb)
        addDrive()
        addShellInside()
    }

    /// 6 the frame, an open lattice; and 4 the shield plate on the back of the screen.
    private mutating func addFrame(zb: Double, zl: Double) {
        let circle = Self.circle
        part = 6
        let ro = Self.rrN(171, 295, 24), ri = Self.rrN(166, 290, 19)
        bd(ro, zb + 7, zb - 5, 30)
        bd(ri, zb + 7, zb - 5, 30, inward: true)
        for (z, nz) in [(zb + 7, 1.0), (zb - 5, -1.0)] {
            let a = ro.map { vertex(($0.x, $0.y, z), (0, 0, nz), uvOf($0.x, $0.y), 30) }
            let b = ri.map { vertex(($0.x, $0.y, z), (0, 0, nz), uvOf($0.x, $0.y), 30) }
            for i in a.indices {
                let j = (i + 1) % a.count
                triangles(nz > 0 ? [a[i], a[j], b[i], a[j], b[j], b[i]] : [a[i], b[i], a[j], a[j], b[i], b[j]])
            }
        }
        let bars: [(Double, Double, Double, Double)] = [
            (-166, -48, 22, 34), (48, 166, 22, 34), (-166, 166, -105, -99), (-100, -94, -99, 22), (94, 100, -99, 22),
            (-79, -73, -290, -105), (68, 74, -290, -105), (-73, 68, -203, -197), (-50, 50, -290, -283),
        ]
        for (x0, x1, y0, y1) in bars { bx6(x0, x1, y0, y1, zb - 5, zb + 5, 30) }
        for i in 0..<24 {  // an arc cut upward into the cross bar
            let x = -48 + Double(i) * 4
            bx6(x, x + 4, 22 + 8 * sin(.pi * (Double(i) + 0.5) / 24), 34, zb - 5, zb + 5, 30)
        }
        for sx in [-1.0, 1] {
            for y in [-232.0, -150, -40, 120, 222] {
                bx6(sx > 0 ? 165 : -169.5, sx > 0 ? 169.5 : -165, y - 7, y + 7, zb - 3, zb + 3, 30)
            }
        }
        for (hx, hy) in [(-97.0, -102.0), (97, -102), (-76, -200), (71, -200), (-40, 28), (40, 28)] {  // screw bosses
            let bc = circle(hx, hy, 5.4, 18)
            d(bc, zb + 5.9, 30, hx, hy)
            bd(bc, zb + 5.9, zb + 5, 30)
            d(circle(hx, hy, 2.3, 14), zb + 5.95, 14, hx, hy)
        }
        for hx in [-22.0, 26] { d(circle(hx, -102, 1.9, 12), zb + 5.08, 37, hx, -102) }

        part = 4  // the shield plate with two tabs each side, on the back of the screen
        let zs = zl - 11.2
        slab(Self.rr(0, 162, 158, 122, 7, 10), 0, 162, zs, zs + 1.9, 32)
        for sx in [-1.0, 1] {
            for y in [70.0, 250] {
                bx6(sx < 0 ? -166 : 158, sx < 0 ? -158 : 166, y, y + 12, zs + 0.3, zs + 1.6, 32)
                dB(circle(sx * 162, y + 6, 2.1, 12), zs + 0.26, 14, sx * 162, y + 6)
            }
        }
        bx6(-34, 30, 36, 50, zs - 0.25, zs, 16)
        bx6(60, 96, 270, 288, zs - 0.25, zs, 16)
    }
}
