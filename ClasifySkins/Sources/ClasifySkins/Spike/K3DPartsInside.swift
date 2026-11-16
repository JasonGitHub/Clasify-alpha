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

    /// 7 the drive: a metal box with grey rubber rails, its board side to the front and its label
    /// side to the back. 8 the foam pad on it.
    mutating func addDrive() {
        let circle = Self.circle
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
        bx(-140, 140, -272, -66, 14, 14.5, 13)
        bx(-60, 40, -200, -120, 14.5, 15.6, 14)
        bx(64, 124, -150, -90, 14.5, 15.4, 14)
        lab(-60, 40, -200, -120, 15.62, back: false)
        lab(64, 124, -150, -90, 15.42, back: false, 1)
        bx6(-128, 128, 101, 128, -12.7, -12, 14)  // the connector, on the label side
        bx6(-70, 70, 106, 125, -15.2, -12.7, 20)
        bx6(-60, 60, 112, 120, -15.3, -15.2, 14)
        for i in 0..<20 { bx6(-58.5 + Double(i) * 6, -55.5 + Double(i) * 6, 101.5, 106, -13.4, -12.7, 15) }
        bx6(-118, -104, 106, 120, -13.3, -12.7, 45)
        let mb = circle(0, 34, 58, 56), mi = circle(0, 34, 16, 28)  // the motor
        d(mb, 14.9, 12, 0, 34)
        bd(mb, 14.9, 14, 12)
        d(mi, 15.7, 12, 0, 34)
        bd(mi, 15.7, 14.9, 12)
        for k in 0..<3 {
            let a = Double(k) * 2.094 + 0.5, hx = 38 * cos(a), hy = 34 + 38 * sin(a)
            d(circle(hx, hy, 2.8, 14), 14.95, 14, hx, hy)
        }
        d(circle(-112, 96, 5, 20), 14.05, 12, -112, 96)
        d(circle(-112, 96, 2.2, 14), 14.1, 14, -112, 96)
        for (hx, hy) in [(-130.0, -76.0), (130, -76), (-130, -262), (130, -262)] {
            let sc = circle(hx, hy, 4.2, 18)
            d(sc, 15.1, 12, hx, hy)
            bd(sc, 15.1, 14.5, 12)
            bx(hx - 2.8, hx + 2.8, hy - 0.55, hy + 0.55, 15.1, 15.16, 14)
            bx(hx - 0.55, hx + 0.55, hy - 2.8, hy + 2.8, 15.1, 15.16, 14)
        }
        for i in 0..<6 {
            let y = -196 + Double(i) * 12
            bx(50, 52, y, y + 5, 14.5, 15.3, 12)
            bx(52, 57, y, y + 5, 14.5, 15.5, 45)
            bx(57, 59, y, y + 5, 14.5, 15.3, 12)
        }
        bx(-122, -100, -112, -98, 14.5, 16.2, 12)
        bx(-13, 13, -66, -20, 14.2, 14.6, 16)

        part = 8  // a step-shaped cut-out and a cut top corner
        let pads: [(Double, Double, Double, Double)] = [
            (-140, -72, 86, 110), (75, 140, 86, 110), (-140, 140, -9, 86), (-140, 23, -65, -9), (96, 140, -65, -9),
            (-140, -75, -129, -65), (96, 140, -129, -65), (-140, 140, -270, -129),
        ]
        for (x0, x1, y0, y1) in pads { bx6(x0, x1, y0, y1, 15.8, 18.4, 37) }
    }

    /// A screw head with a cross slot (the mock's `scr`), on a surface at `z`.
    private mutating func screw(_ hx: Double, _ hy: Double, _ z: Double, r: Double, h: Double, slot: Double, width: Double) {
        let sc = Self.circle(hx, hy, r, 16)
        d(sc, z + h, 12, hx, hy)
        bd(sc, z + h, z, 12)
        bx(hx - slot, hx + slot, hy - width, hy + width, z + h, z + h + 0.06, 14)
        bx(hx - width, hx + width, hy - slot, hy + slot, z + h, z + h + 0.06, 14)
    }

    /// 0 inside the shell: the battery, the flex cables on the back wall, and the jack and hold
    /// switch block at the top.
    mutating func addShellInside() {
        let circle = Self.circle
        part = 0
        let z0 = -Self.depth / 2 + 1
        slab(Self.rr(-38, 210, 118, 46, 13, 8), -38, 210, z0, z0 + 30, 35)
        bx(-140, 64, 176, 244, z0 + 30, z0 + 30.15, 19)
        bx(-148, -14, 262, 284, z0, z0 + 8, 12)
        bx(104, 146, 180, 214, z0, z0 + 3, 36)
        bx(80, 93, 196, 205, z0, z0 + 0.6, 16)
        bx(86, 93, 205, 214, z0, z0 + 0.6, 16)
        let zb = z0 + 1.4
        bx(84, 150, 214, 284, z0, zb, 16)
        bx(84, 150, 264, 284, zb, zb + 1.6, 12)
        bx(84, 90, 236, 264, zb, zb + 1.6, 12)
        screw(93, 275, zb + 1.6, r: 3.4, h: 0.7, slot: 2.2, width: 0.45)
        screw(143, 275, zb + 1.6, r: 3.4, h: 0.7, slot: 2.2, width: 0.45)
        bx(108, 146, 218, 264, zb, z0 + 12, 44)
        bx(111, 143, 221, 247, z0 + 12, z0 + 12.5, 14)
        bx(113, 141, 250, 261, z0 + 12, z0 + 12.3, 14)
        bx(118, 136, 264, 284, zb + 1.6, z0 + 11.4, 12)
        bx(121, 133, 266, 284, z0 + 11.4, z0 + 11.9, 12)
        bx(126.4, 127.6, 264, 284, z0 + 11.9, z0 + 11.96, 14)
        let jb = circle(127, 234, 6.2, 24)
        d(jb, z0 + 13.1, 12, 127, 234)
        bd(jb, z0 + 13.1, z0 + 12.5, 12)
        d(circle(127, 234, 3, 18), z0 + 13.15, 14, 127, 234)
        for i in 0..<3 {
            let y = 221 + Double(i) * 9
            bx(146, 149, y, y + 5, zb, zb + 4.5, 12)
            bx(149, 150, y + 0.6, y + 4.4, zb, zb + 0.5, 15)
            bx(105, 108, y, y + 5, zb, zb + 4.5, 12)
        }
        bx(91, 105, 240, 260, zb, zb + 5.6, 12)
        bx(93, 103, 247, 253, zb + 5.6, zb + 5.68, 44)
        bx(98, 103, 246.4, 253.6, zb + 5.68, zb + 7.6, 14)
        for i in 0..<3 { bx(89.4, 91, 242 + Double(i) * 6.5, 244.6 + Double(i) * 6.5, zb, zb + 0.5, 15) }
        bx(92, 104, 220, 232, zb, zb + 2.2, 14)
        for i in 0..<4 {
            let x = 93.2 + Double(i) * 2.8
            bx(x, x + 1.4, 218.6, 220, zb, zb + 0.4, 15)
            bx(x, x + 1.4, 232, 233.4, zb, zb + 0.4, 15)
        }
        for cy in [219.0, 225, 231] {
            bx(85.5, 90, cy, cy + 3, zb, zb + 1.6, 45)
            bx(85.5, 86.6, cy, cy + 3, zb + 1.6, zb + 1.66, 12)
            bx(88.9, 90, cy, cy + 3, zb + 1.6, zb + 1.66, 12)
        }
        for (hx, hy) in [(-138.0, 273.0), (-24, 273)] {
            let sc = circle(hx, hy, 3.6, 16)
            d(sc, z0 + 8.6, 12, hx, hy)
            bd(sc, z0 + 8.6, z0 + 8, 12)
            bx(hx - 2.4, hx + 2.4, hy - 0.5, hy + 0.5, z0 + 8.6, z0 + 8.66, 14)
            bx(hx - 0.5, hx + 0.5, hy - 2.4, hy + 2.4, z0 + 8.6, z0 + 8.66, 14)
        }
    }
}
