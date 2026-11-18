import Foundation

/// CLA-105: the parts deepest inside, from `k3d_src3.js` lines 179 to 223: 9 the logic board,
/// 7 the drive, 8 the foam pad, and 0 the battery, flex cables and the jack and hold block in
/// the shell. Drawn from Jason's photos of the real inside, with no pictures and no brand marks.
extension K3DMesh {
    /// 9 the logic board, 4.5 pt thick with a layered edge. Front: five gold switches in a cross
    /// inside a pale ring, cans and small parts. Back: chips with labels, connectors, the dock connector.
    mutating func addBoard(zb: Double) {
        let circle = Self.circle
        part = 9
        slab(Self.rr(0, -148, 162, 142, 5, 10), 0, -148, zb - 2.7, zb + 1.8, 13, 13, 43)
        for (sx, sy) in [(0.0, 0.0), (78, 0), (-78, 0), (0, 78), (0, -78)] {
            let cy = -127 + sy
            bx(sx - 17, sx + 17, cy - 17, cy + 17, zb + 1.8, zb + 4.2, 44)
            for ax in [-1.0, 1] {
                for ay in [-1.0, 1] {
                    let bc = circle(sx + ax * 13.4, cy + ay * 13.4, 4.2, 14)
                    d(bc, zb + 4.7, 12, sx + ax * 13.4, cy + ay * 13.4)
                    bd(bc, zb + 4.7, zb + 4.2, 12)
                }
            }
            d(circle(sx, cy, 14, 36), zb + 6.4, 38, sx, cy)
            bd(circle(sx, cy, 14, 36), zb + 6.4, zb + 4.2, 38)
        }
        d(circle(0, -127, 52.6, 72), zb + 1.95, 39, 0, -127)
        for ax in [-1.0, 1] {
            d(circle(ax * 27.7, -127, 4.2, 20), zb + 2.05, 12, ax * 27.7, -127)
            d(circle(ax * 27.7, -127, 2.4, 16), zb + 2.1, 14, ax * 27.7, -127)
        }
        for (hx, hy) in [(-72.0, -39.5), (68, -39.5)] {
            d(circle(hx, hy, 3.8, 20), zb + 1.9, 15, hx, hy)
            d(circle(hx, hy, 2, 16), zb + 1.95, 14, hx, hy)
        }
        for (x, y) in [(-142.0, -42.0), (-126, -56), (-114, -40)] {  // small 3-leg parts
            bx(x, x + 8, y, y + 5, zb + 1.8, zb + 3.6, 14)
            for dx in [0.6, 5.6] { bx(x + dx, x + dx + 1.8, y - 2.2, y, zb + 1.8, zb + 2.4, 12) }
            bx(x + 3.1, x + 4.9, y + 5, y + 7.2, zb + 1.8, zb + 2.4, 12)
        }
        bx(-150, -146, -58, -56, zb + 1.8, zb + 2.8, 45)
        bx(-108, -104, -58, -56, zb + 1.8, zb + 2.8, 45)
        for i in 0..<17 {
            let x = -82 + Double(i) * 7.8
            bx(x, x + 1.6, -264, -260, zb + 1.8, zb + 2.6, 12)
            bx(x + 1.6, x + 3.8, -264, -260, zb + 1.8, zb + 2.9, 14)
            bx(x + 3.8, x + 5.4, -264, -260, zb + 1.8, zb + 2.6, 12)
        }
        for (ox, oy) in [(-72.0, -273.0), (-63, -268), (-63, -280), (61, -268), (61, -280), (70, -273)] {
            let oc = circle(ox, oy, 2.6, 12).map { SIMD4($0.x, oy + ($0.y - oy) * 1.5, $0.z, $0.w) }
            d(oc, zb + 2.5, 12, ox, oy)
            bd(oc, zb + 2.5, zb + 1.8, 12)
        }
        bx(122, 148, -42, -20, zb + 1.8, zb + 4.4, 14)
        lab(122, 148, -42, -20, zb + 4.42, back: false, 2)
        for i in 0..<5 {
            let f = Double(i) * 4.4
            bx(118, 122, -40 + f, -38 + f, zb + 1.8, zb + 2.6, 12)
            bx(148, 152, -40 + f, -38 + f, zb + 1.8, zb + 2.6, 12)
            bx(125.2 + f, 127.2 + f, -20, -16, zb + 1.8, zb + 2.6, 12)
            bx(125.2 + f, 127.2 + f, -46, -42, zb + 1.8, zb + 2.6, 12)
        }
        for (fx, fy) in [(48.0, -65.0), (-96, -270)] {
            bx(fx - 6, fx + 6, fy - 6, fy + 6, zb + 1.8, zb + 2.1, 45)
            bx(fx - 1.3, fx + 1.3, fy - 1.3, fy + 1.3, zb + 2.1, zb + 2.2, 12)
        }
        bx(-150, -118, -262, -230, zb + 1.8, zb + 5, 14)
        lab(-150, -118, -262, -230, zb + 5.02, back: false, 2)
        bx(-166, -146, -96, -58, zb + 1.8, zb + 9, 14)
        bx(114, 134, -204, -197, zb + 1.8, zb + 3, 12)
        bx(114, 134, -240, -233, zb + 1.8, zb + 3, 12)
        for i in 0..<14 { bx(-45 + Double(i) * 6.6, -41 + Double(i) * 6.6, -285, -277, zb + 1.8, zb + 2.3, 12) }  // dock pads
        addBoardBack(zc: zb - 2.7)
    }

    /// The board's back: a block `h` pt deep under the board (`D`).
    private mutating func boardBack(_ zc: Double, _ x0: Double, _ x1: Double, _ y0: Double, _ y1: Double, _ h: Double, _ m: Int) {
        bx6(x0, x1, y0, y1, zc - h, zc, m)
    }

    private mutating func addBoardBack(zc: Double) {
        let circle = Self.circle
        func D(_ x0: Double, _ x1: Double, _ y0: Double, _ y1: Double, _ h: Double, _ m: Int) {
            boardBack(zc, x0, x1, y0, y1, h, m)
        }
        let chips: [(Double, Double, Double, Double, Double, Double)] = [
            (-135, -99, -202, -164, 4, 1), (5, 56, -202, -142, 5, 0), (93, 148, -202, -145, 4.6, 1), (17, 46, -105, -74, 3.4, 2),
            (-63, -36, -198, -173, 3, 2),
        ]
        for (x0, x1, y0, y1, h, k) in chips {
            D(x0, x1, y0, y1, h, 14)
            lab(x0, x1, y0, y1, zc - h - 0.02, back: true, k)
        }
        D(-69, -21, -85, -36, 0.3, 42)
        D(-85, -15, -115, -88, 4, 20)
        D(-80, -20, -109, -96, 4.1, 45)
        D(-158, -135, -61, -22, 4.4, 20)
        D(-154, -139, -55, -28, 4.5, 15)
        D(105, 123, -66, -34, 4.4, 14)
        D(109, 119, -60, -40, 4.5, 15)
        for i in 0..<16 { D(-82 + Double(i) * 4.2, -80 + Double(i) * 4.2, -88, -85.4, 0.7, 15) }
        for i in 0..<9 {
            D(-135, -132.6, -59 + Double(i) * 4, -57.2 + Double(i) * 4, 0.7, 15)
            D(102.6, 105, -64 + Double(i) * 3.4, -62.4 + Double(i) * 3.4, 0.7, 15)
        }
        D(-58, -42, -246, -225, 3.6, 15)
        D(-31, 31, -243, -227, 2.6, 14)
        D(-28, 28, -241.6, -239.4, 2.7, 15)
        D(-28, 28, -230.6, -228.4, 2.7, 15)
        D(-150, -118, -281, -236, 5.5, 12)
        D(126, 140, -257, -244, 3, 12)
        D(118, 138, -232, -217, 3, 12)
        let ic = circle(-130, -222, 10, 28)
        dB(ic, zc - 5, 14, -130, -222)
        bd(ic, zc, zc - 5, 14)
        for cx in [124.0, 139] {
            for r in 0..<3 {
                let y0 = -110 + Double(r) * 9
                D(cx, cx + 2.5, y0, y0 + 6, 2, 12)
                D(cx + 2.5, cx + 9.5, y0, y0 + 6, 2.2, 45)
                D(cx + 9.5, cx + 12, y0, y0 + 6, 2, 12)
            }
        }
        for i in 0..<4 {
            let y = -200 + Double(i) * 7.5
            D(-150, -148, y, y + 5, 1.8, 12)
            D(-148, -142, y, y + 5, 2, 45)
            D(-142, -140, y, y + 5, 1.8, 12)
        }
        for x in [102.0, 116, 130] {
            D(-x - 8, -x, -140, -135, 1.8, 14)
            D(-x - 7.4, -x - 5.6, -142.2, -140, 0.6, 12)
            D(-x - 2.4, -x - 0.6, -142.2, -140, 0.6, 12)
            D(-x - 4.9, -x - 3.1, -135, -132.8, 0.6, 12)
        }
        for (hx, hy) in [(30.0, -131.0), (-10, -134)] {
            dB(circle(hx, hy, 3.2, 20), zc - 0.06, 12, hx, hy)
            dB(circle(hx, hy, 1.8, 16), zc - 0.1, 14, hx, hy)
        }
        for i in 0..<5 {  // resistors: a dark body with metal ends
            let y = -100 + Double(i) * 8
            D(1, 9, y, y + 5, 2, 45)
            D(-2, 1, y, y + 5, 2, 12)
            D(9, 12, y, y + 5, 2, 12)
        }
        D(-52, 52, -296, -268, 7.5, 12)  // the dock connector
        D(-46, 46, -268, -252, 6.5, 14)
        for ax in [-1.0, 1] { D(ax * 44 - 3, ax * 44 + 3, -285, -279, 7.6, 14) }
    }

    /// 7 the drive: a metal box with grey rubber rails. K.3D.11: the vertex shader turns it 180°
    /// about y, so its label side, with the connector, faces the board under 8 the foam pad. Its
    /// other side is a closed steel lid under a U of blue foam (`addDriveLidFoam`).
    mutating func addDrive() {
        part = 7
        slab(Self.rr(0, -80, 156, 208, 9, 12), 0, -80, -12, 14, 12, 40)
        for sx in [-1.0, 1] {
            func X(_ a: Double, _ b: Double) -> (Double, Double) { sx > 0 ? (a, b) : (-b, -a) }
            for (y0, y1) in [(-288.0, -172.0), (-160, -44), (-32, 128)] {
                let x = X(152, 168)
                bx6(x.0, x.1, y0, y1, -14.5, 16.5, 36)
            }
            let r = X(155, 162), top = X(126, 168)
            bx6(r.0, r.1, -288, 128, -11, 13, 36)
            bx6(top.0, top.1, 124, 133, -14.5, 16.5, 36)
            bx6(top.0, top.1, -293, -284, -14.5, 16.5, 36)
        }
        bx6(-128, 128, 101, 128, -12.7, -12, 14)  // the connector, on the label side
        bx6(-70, 70, 106, 125, -15.2, -12.7, 20)
        bx6(-60, 60, 112, 120, -15.3, -15.2, 14)
        for i in 0..<20 { bx6(-58.5 + Double(i) * 6, -55.5 + Double(i) * 6, 101.5, 106, -13.4, -12.7, 15) }
        bx6(-118, -104, 106, 120, -13.3, -12.7, 45)
        addDriveLidFoam()

        // K.3D.11 (CLA-129): a step cut-out over the label's model, S/N and barcode lines, a wide
        // lower part and a narrow upper part on the right, and a cut top corner.
        part = 8
        let pads: [(Double, Double, Double, Double)] = [
            (-140, -72, 86, 110), (75, 140, 86, 110), (-140, 140, 0, 86), (-140, 18, -60, 0), (88, 140, -60, 0),
            (-140, -75, -150, -60), (88, 140, -150, -60), (-140, 140, -270, -150),
        ]
        for (x0, x1, y0, y1) in pads { bx6(x0, x1, y0, y1, 15.8, 20.6, 37) }
    }

    /// 0 inside the shell (K.3D.11, CLA-129, Jason's 4 shell photos): the battery in blue shrink
    /// film, the flex cables on the back wall, the jack corner (a tall steel can at the top wall,
    /// the jack body, a small flex board with a chip), the hold switch on its bracket, a rolled
    /// bead along the top wall, and a clip rail inside each long wall.
    mutating func addShellInside() {
        let circle = Self.circle
        part = 0
        let z0 = -Self.depth / 2 + 1, bH = 40.0
        slab(Self.rr(-40, 212, 120, 48, 13, 8), -40, 212, z0 + 1.5, z0 + bH, 35)
        bx(-140, 64, 176, 244, z0 + bH, z0 + bH + 0.15, 19)
        let zq = z0 + 1.5
        bx(80, 93, 196, 205, zq, zq + 0.6, 16)
        bx(86, 93, 205, 214, zq, zq + 0.6, 16)
        // The jack corner: flex board, gold contacts, chip, jack body, steel can.
        bx(96, 134, 184, 216, z0 + 1.5, z0 + 2.7, 16)
        for i in 0..<7 { bx(97, 99.6, 188 + Double(i) * 4, 190.4 + Double(i) * 4, z0 + 2.7, z0 + 3.3, 15) }
        bx6(104, 126, 189, 210, z0 + 2.7, z0 + 6.5, 44)
        bx6(100, 130, 218, 244, z0 + 1.5, z0 + 16, 45)
        bx6(92, 138, 244, 290, z0 + 1.5, z0 + 18, 12)
        cylinder(x0: -156, x1: 96, yc: 288, zc: z0 + 9, r: 7, material: 12)  // the rolled bead along the top wall
        // The hold switch: a dark steel bracket, its small flex strip and the slider on top.
        bx6(-160, -40, 274, 296, z0 + 8, z0 + 17, 44)
        bx(-136, -98, 290, 296, z0 + 17, z0 + 18.2, 44)
        bx6(-118, -104, 292, 296, z0 + 18.2, z0 + 21, 12)
        let gs = circle(-52, 290, 3.6, 16)
        d(gs, z0 + 17.6, 15, -52, 290)
        bd(gs, z0 + 17.6, z0 + 17, 15)
        d(circle(-70, 290, 2, 12), z0 + 17.05, 10, -70, 290)  // material 10 as in the mock
        bx6(-34, 40, 286, 291, z0 + 2, z0 + 12, 44)  // the dark top opening
        bx6(52, 70, 284, 290, z0 + 1.5, z0 + 14, 44)  // a knurled band
        for (hx, hy) in [(82.0, 284.0), (146, 250)] {  // screw posts
            let sp = circle(hx, hy, 6.5, 20)
            d(sp, z0 + 12, 12, hx, hy)
            bd(sp, z0 + 12, z0 + 1.5, 12)
            d(circle(hx, hy, 3, 16), z0 + 12.05, 44, hx, hy)
        }
        for kx in [72.0, 148] { bx6(kx - 6, kx + 6, 282, 290, z0 + 1.5, z0 + 9, 12) }
        // A thin steel clip rail inside each long wall: a rolled lip on top, 8 clips bent inward,
        // a raised tab at the rail's top end.
        for sx in [-1.0, 1] {
            func X(_ a: Double, _ b: Double) -> (Double, Double) { (min(a, b), max(a, b)) }
            func rail(_ x: (Double, Double), _ y0: Double, _ y1: Double, _ z0: Double, _ z1: Double, _ m: Int) {
                bx6(x.0, x.1, y0, y1, z0, z1, m)
            }
            let xo = sx * 180.4, xi = sx * 177.6
            rail(X(xo, xi), -252, 256, 2, 13.2, 34)
            rail(X(xo, sx * 175.4), -252, 256, 13.2, 15.4, 34)
            for k in 0..<8 {
                let y = -226 + Double(k) * 62
                rail(X(xi, sx * 173.2), y - 6, y + 6, 5.2, 10.8, 34)
                rail(X(xi, sx * (177.6 - 0.12)), y - 6, y + 6, 10.8, 12.8, 44)
                rail(X(sx * 173.2, sx * 172.2), y - 6, y + 6, 9.6, 10.8, 34)
            }
            rail(X(xo, sx * 176.4), 256, 263, 2, 19, 34)
            rail(X(sx * 176.4, sx * 172.6), 256, 263, 17.6, 19, 34)
        }
    }

    /// A round bar along x (the mock's `cyl`): 12 faces round its axis at `yc`, `zc`.
    private mutating func cylinder(x0: Double, x1: Double, yc: Double, zc: Double, r: Double, material m: Int) {
        let k = 12
        for i in 0..<k {
            let a0 = Double(i) / Double(k) * 2 * .pi, a1 = Double(i + 1) / Double(k) * 2 * .pi
            let p0 = (yc + r * cos(a0), zc + r * sin(a0)), p1 = (yc + r * cos(a1), zc + r * sin(a1))
            let n0 = (0.0, cos(a0), sin(a0)), n1 = (0.0, cos(a1), sin(a1))
            let q = [
                vertex((x0, p0.0, p0.1), n0, uvOf(x0, p0.0), m), vertex((x1, p0.0, p0.1), n0, uvOf(x1, p0.0), m),
                vertex((x1, p1.0, p1.1), n1, uvOf(x1, p1.0), m), vertex((x0, p1.0, p1.1), n1, uvOf(x0, p1.0), m),
            ]
            triangles([q[0], q[1], q[2], q[0], q[2], q[3]])
        }
    }
}
