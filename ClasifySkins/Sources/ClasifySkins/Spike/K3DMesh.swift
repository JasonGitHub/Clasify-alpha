import CoreGraphics
import Foundation

/// SPIKE (CLA-101): the K.3D.7 device, assembled, as a triangle mesh. Ported from the About
/// thread's frozen `k3d_src3.js` (design-review/about/k3d7-spike), the `data-edge="parts"` path.
/// Units are points. The body is 366 x 613 x 68 with a corner radius of 34, centered on the
/// origin, y up, the front at z = +34.
///
/// Each vertex is 13 floats: position (3), normal (3), uv (2), uv2 (2), weight (1), material (1),
/// part (1). Materials: 0 hole wall, 1 steel, 2 seam, 3 front, 4 back face, 10 dark. Parts: 0 shell,
/// 1 front plate, 2 window, 3 wheel, 5 center button.
///
/// Not ported: everything only Take apart shows (materials above 10 and parts 6 to 8, which the
/// mock hides when assembled), and the screen module (part 4), which the opaque window hides.
struct K3DMesh {
    static let width = 366.0, height = 613.0, depth = 68.0, radius = 34.0
    /// Floats per vertex.
    static let stride = 13
    /// The wheel's and the center button's center.
    static let wheelCenter = SIMD2<Double>(0, -127)

    private(set) var vertices: [Float] = []
    private(set) var indices: [UInt32] = []
    /// The part new vertices belong to.
    private var part = 0

    var vertexCount: Int { vertices.count / Self.stride }

    init() {
        let w = Self.width, h = Self.height, t = Self.depth, r = Self.radius
        let corners = 24, keep = 0.45  // the steel's inner rings keep 45% of the corner radius change

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

        // The plate's edge: one curve whose bend radius falls from 184.4 pt to 4.4 pt as it turns
        // 90°, r = 4.4 + 180 (1 - turn / 90°)^9. A point every 3 pt of curve or every 3° of turn.
        var curve: [(x: Double, z: Double, turn: Double)] = [(0, 0, 0)]
        do {
            let steps = 6000
            var x = 0.0, z = 0.0, length = 0.0, lastTurn = 0.0
            for i in 0..<steps {
                let a = (Double(i) + 0.5) / Double(steps) * .pi / 2
                let bend = 4.4 + 180 * pow(1 - a / (.pi / 2), 9), ds = bend * .pi / 2 / Double(steps)
                x += cos(a) * ds
                z += sin(a) * ds
                length += ds
                let end = Double(i + 1) / Double(steps) * .pi / 2
                if length >= 3 || end - lastTurn >= .pi / 60 || i == steps - 1 {
                    curve.append((x, z, end))
                    length = 0
                    lastTurn = end
                }
            }
        }
        let edgeWidth = min(curve[curve.count - 1].x, 148), edgeDepth = curve[curve.count - 1].z

        // Profile rings, front to back: inset, z, normal angle (degrees: 90 faces the front, 0
        // out, -90 the back), material. The plate's curve, its 0.5 pt wall, the seam, then the
        // steel shell: a straight wall and a 22 pt in x 24.8 pt down curve onto the back.
        var profile: [(inset: Double, z: Double, angle: Double, material: Int)] = curve.map {
            (max(0, edgeWidth - $0.x), t / 2 - $0.z, 90 - $0.turn * 180 / .pi, 3)
        }
        let zt = t / 2 - edgeDepth
        profile += [(0, zt - 0.5, 0, 3), (0, zt - 0.5, -90, 2), (1.5, zt - 0.5, -90, 2), (1.5, zt - 0.5, 0, 2),
                    (1.5, zt - 1.1, 0, 2), (1.5, zt - 1.1, 0, 1), (1.5, -t / 2 + 24.8, 0, 1)]
        for i in 1...14 {
            let s = Double(i) / 14 * .pi / 2
            let nx = 24.8 * cos(s), nz = -22 * sin(s), l = hypot(nx, nz)
            profile.append((1.5 + 22 * (1 - cos(s)), -t / 2 + 24.8 - 24.8 * sin(s), atan2(nz / l, nx / l) * 180 / .pi, 1))
        }
        // The shell is flush with the plate.
        for i in profile.indices where profile[i].material == 1 || profile[i].material == 2 {
            profile[i].inset = max(0, profile[i].inset - 1.5)
        }

        var rings: [[UInt32]] = [], ringParts: [Int] = []
        for (inset, z, angle, material) in profile {
            part = material == 3 || material == 0 ? 1 : 0
            let na = angle * .pi / 180, ca = cos(na), sa = sin(na)
            var row: [UInt32] = []
            for (cx, cy, ox, oy) in outline {
                // The plate's rings keep the 34 pt corner. The steel's inner rings keep a larger
                // corner, so the shell turns the corner smoothly.
                let sx: Double = cx < 0 ? -1 : 1, sy: Double = cy < 0 ? -1 : 1
                let kc = material == 3 ? 0 : keep, rr = r - kc * inset
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
                row.append(vertex((x, y, z), (ox * ca, oy * ca, sa), uv, material, uv2: uv2, weight: weight))
            }
            rings.append(row)
            ringParts.append(part)
        }
        // No strip joins two parts.
        for k in 0..<(rings.count - 1) where ringParts[k] == ringParts[k + 1] {
            let a = rings[k], b = rings[k + 1], n = a.count
            for i in 0..<n {
                let j = (i + 1) % n
                indices += [a[i], a[j], b[i], a[j], b[j], b[i]]
            }
        }
        part = 1
        cap(rings[0], z: t / 2, nz: 1, material: 3, mirror: false)  // the front face
        part = 0
        cap(rings[rings.count - 1], z: -t / 2, nz: -1, material: 4, mirror: true)  // the back face

        // The parts. The face's height at a point, for the top of the plate's hole walls.
        func drop(_ inset: Double) -> Double {
            if inset >= edgeWidth { return 0 }
            let px = edgeWidth - inset
            var lo = 0, hi = curve.count - 1
            while hi - lo > 1 {
                let mid = (lo + hi) >> 1
                if curve[mid].x < px { lo = mid } else { hi = mid }
            }
            let a = curve[lo], b = curve[hi], f = (px - a.x) / max(1e-6, b.x - a.x)
            return a.z + (b.z - a.z) * f
        }
        func sdr(_ x: Double, _ y: Double, _ hx: Double, _ hy: Double, _ r: Double) -> Double {
            let qx = abs(x) - hx + r, qy = abs(y) - hy + r
            return hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - r
        }
        func insetOf(_ x: Double, _ y: Double) -> Double {
            var lo = 0.0, hi = min(w, h) / 2
            for _ in 0..<40 {
                let mid = (lo + hi) / 2
                if sdr(x, y, w / 2 - mid, h / 2 - mid, r) <= 0 { lo = mid } else { hi = mid }
            }
            return lo
        }
        func height(_ x: Double, _ y: Double) -> Double { t / 2 - drop(insetOf(x, y)) }

        let zl = t / 2 - 0.3, zw = t / 2 - 1.6, wheel = Self.wheelCenter
        // The screen hole's outline: center (0, 161.25), half size 156.5 x 119.25, radius 7.
        let window = Self.roundedRect(0, 161.25, 156.5, 119.25, 7, step: 4)
        part = 1  // the plate's hole walls
        band(window, top: { height($0, $1) + 0.15 }, bottom: zl - 0.6, material: 0, inward: true)
        band(Self.circle(wheel.x, wheel.y, 112.65, 128), top: { height($0, $1) - 0.05 }, bottom: t / 2 - 14, material: 0, inward: true)
        part = 2  // the window: flat, flush with the face, with a dark cut edge
        disc(window, z: zl, material: 3, center: (0, 161.25))
        band(window, top: { _, _ in zl }, bottom: zl - 1.2, material: 10, inward: false)
        part = 3  // the wheel, 1.6 pt under the face, 0.15 pt larger than its hole
        let rim = Self.circle(wheel.x, wheel.y, 112.8, 128)
        disc(rim, z: zw, material: 3, center: (wheel.x, wheel.y))
        band(rim, top: { _, _ in zw }, bottom: zw - 2.5, material: 3, inward: false)
        part = 5  // the center button
        let button = Self.circle(wheel.x, wheel.y, 41.8, 128)
        disc(button, z: zw - 0.05, material: 3, center: (wheel.x, wheel.y))
        band(button, top: { _, _ in zw - 0.05 }, bottom: zw - 3, material: 3, inward: false)
        part = 0  // the dark board inside, seen through no gap at rest
        disc(Self.roundedRect(0, 0, w / 2 - 6, h / 2 - 6, 30, step: 8), z: t / 2 - 14, material: 10, center: (0, 0))
    }

    private mutating func vertex(
        _ p: (Double, Double, Double), _ n: (Double, Double, Double), _ uv: (Double, Double), _ material: Int,
        uv2: (Double, Double)? = nil, weight: Double = 1
    ) -> UInt32 {
        let index = UInt32(vertexCount)
        let u2 = uv2 ?? uv
        vertices += [p.0, p.1, p.2, n.0, n.1, n.2, uv.0, uv.1, u2.0, u2.1, weight, Double(material), Double(part)].map { Float($0) }
        return index
    }

    private func uvOf(_ x: Double, _ y: Double) -> (Double, Double) {
        ((x + Self.width / 2) / Self.width, (Self.height / 2 - y) / Self.height)
    }

    private mutating func cap(_ row: [UInt32], z: Double, nz: Double, material: Int, mirror: Bool) {
        let w = Self.width, h = Self.height
        let center = vertex((0, 0, z), (0, 0, nz), (0.5, 0.5), material)
        var points: [UInt32] = []
        for i in row {
            let x = Double(vertices[Int(i) * Self.stride]), y = Double(vertices[Int(i) * Self.stride + 1])
            let uv = (mirror ? (w / 2 - x) / w : (x + w / 2) / w, (h / 2 - y) / h)
            points.append(vertex((x, y, z), (0, 0, nz), uv, material))
        }
        for i in points.indices {
            let j = (i + 1) % points.count
            indices += nz > 0 ? [center, points[j], points[i]] : [center, points[i], points[j]]
        }
    }

    /// A flat face that looks to the front, a fan from its center.
    private mutating func disc(_ outline: [SIMD4<Double>], z: Double, material: Int, center: (Double, Double)) {
        let c = vertex((center.0, center.1, z), (0, 0, 1), uvOf(center.0, center.1), material)
        let ids = outline.map { vertex(($0.x, $0.y, z), (0, 0, 1), uvOf($0.x, $0.y), material) }
        for i in ids.indices { indices += [c, ids[i], ids[(i + 1) % ids.count]] }
    }

    /// A straight wall along an outline, drawn with both windings so it shows from either side.
    private mutating func band(
        _ outline: [SIMD4<Double>], top: (Double, Double) -> Double, bottom: Double, material: Int, inward: Bool
    ) {
        let s = inward ? -1.0 : 1.0
        var pairs: [(UInt32, UInt32)] = []
        for o in outline {
            let n = (s * o.z, s * o.w, 0.0)
            let a = vertex((o.x, o.y, top(o.x, o.y)), n, uvOf(o.x, o.y), material)
            let b = vertex((o.x, o.y, bottom), n, uvOf(o.x, o.y), material)
            pairs.append((a, b))
        }
        for i in pairs.indices {
            let (t0, b0) = pairs[i], (t1, b1) = pairs[(i + 1) % pairs.count]
            indices += [t0, b0, t1, t1, b0, b1, t0, t1, b0, t1, b1, b0]
        }
    }

    /// Points around a circle: x, y, and the outward direction.
    static func circle(_ cx: Double, _ cy: Double, _ r: Double, _ n: Int) -> [SIMD4<Double>] {
        (0..<n).map { i in
            let a = Double(i) / Double(n) * 2 * .pi
            return SIMD4(cx + r * cos(a), cy + r * sin(a), cos(a), sin(a))
        }
    }

    /// Points around a rounded rectangle, counterclockwise from the top right corner: 9 on each
    /// corner, and one about every `step` pt along each side.
    static func roundedRect(_ cx: Double, _ cy: Double, _ hx: Double, _ hy: Double, _ r: Double, step: Double) -> [SIMD4<Double>] {
        var o: [SIMD4<Double>] = []
        let corners = [(hx - r, hy - r, 0.0), (-(hx - r), hy - r, 90.0), (-(hx - r), -(hy - r), 180.0), (hx - r, -(hy - r), 270.0)]
        for c in 0..<4 {
            let (ax, ay, a0) = corners[c]
            for i in 0...8 {
                let a = (a0 + 90 * Double(i) / 8) * .pi / 180
                o.append(SIMD4(cx + ax + r * cos(a), cy + ay + r * sin(a), cos(a), sin(a)))
            }
            let e = o[o.count - 1], (bx, by, b0) = corners[(c + 1) % 4]
            let sa = b0 * .pi / 180, sx = cx + bx + r * cos(sa), sy = cy + by + r * sin(sa)
            let k = max(1, Int((hypot(sx - e.x, sy - e.y) / step).rounded()))
            for j in 1..<k {
                let f = Double(j) / Double(k)
                o.append(SIMD4(e.x + (sx - e.x) * f, e.y + (sy - e.y) * f, e.z, e.w))
            }
        }
        return o
    }
}

/// A turn of the 3D device, as a script. `flip` is the mock's `flip()` (CLA-101): the device
/// turns 180° in 0.82 s with a 2.5% overshoot, settles by 1.0 s, and is pushed back by up to
/// 70 pt while it turns; the 3D body and the flat 2D device crossfade in 0.1 s. `arrive` is
/// card BR's first launch (change 288): from -120° and 55% size, one ease-out turn to the front
/// in 1.6 s, fading in over the first 0.8 s; then the 2D device fades in over 0.35 s while
/// Hello writes (Jason, 23:05 JST 11-15: no rest, so Hello comes sooner). `spin` is card BR's color change (changes 289 and 290): the device crossfades to 3D
/// in 0.15 s, turns 360° with a quad in-out, and crossfades back in 0.15 s. It shows the old
/// color until 180°, then the color the device has now.
public struct K3DFlip {
    static let turn = 0.82, duration = 1.0, lift = 70.0
    /// The crossfade between the 3D body and the flat 2D device.
    static let fade = 0.1
    /// Card BR, change 288: the arrival's turn and its crossfade to the 2D device.
    public static let arriveTurn = 1.6, arriveFade = 0.35, arriveFrom = -120.0, arriveScale = 0.55
    /// When the skin sends `.arrived`, before the turn ends: Hello's wait before its first
    /// stroke, so the first stroke lands on the turn's last frame.
    public static let arriveHelloLead = Hello.lead

    /// Changes 289 and 290: the color spin's crossfades, and its turn on Pick Your Color and in
    /// Settings.
    static let spinFade = 0.15
    public static let spinPick = 1.4, spinSettings = 0.8

    enum Script: Equatable { case flip, arrive, spin(Double) }

    /// The angle the last turn started from and goes to, in degrees: 0 is the front, 180 the back.
    private(set) var from = 0.0, to = 0.0
    /// When the last turn started.
    private(set) var start = Date.distantPast
    private(set) var script = Script.flip
    /// The spin's old color (changes 289 and 290).
    private(set) var fromBlack = false
    /// A live picture of the device for the 3D front's screen, taken when the turn started.
    public private(set) var screen: CGImage?

    public init() {}

    /// Change 288: the first frames before the arrival starts. Nothing shows, neither the 2D
    /// device nor the 3D body: its clock has not started, so it sits before the turn.
    public static var waiting: K3DFlip {
        var flip = K3DFlip()
        flip.script = .arrive
        (flip.from, flip.to, flip.start) = (arriveFrom, 0, .distantFuture)
        return flip
    }

    /// Card BR, change 288: the first launch's arrival. The screen picture is made first and put
    /// in the 3D front, as for a flip; the clock starts after it, or at `now` in tests.
    @MainActor public static func arrive(at now: Date? = nil, screen make: () -> CGImage?) -> K3DFlip {
        var flip = K3DFlip()
        flip.show(screen: make())
        flip.script = .arrive
        (flip.from, flip.to, flip.start) = (arriveFrom, 0, now ?? .now)
        return flip
    }

    /// Changes 289 and 290: a color spin with a turn of `turn` seconds. The device was black
    /// before the change when `fromBlack`. The clock starts after the screen picture is made.
    @MainActor public static func spin(turn: Double, fromBlack: Bool, at now: Date? = nil, screen make: () -> CGImage?) -> K3DFlip {
        var flip = K3DFlip()
        flip.show(screen: make())
        flip.script = .spin(turn)
        (flip.fromBlack, flip.start) = (fromBlack, now ?? .now)
        return flip
    }

    /// Puts a new picture in the 3D front's screen: during a spin the screen stays live.
    @MainActor public mutating func show(screen: CGImage?) {
        if let screen { K3DRenderer.shared?.prepare(screen: screen) }
        self.screen = screen
    }

    /// A color spin runs now. A color change during it lands at its end, with no second spin.
    public func isSpinning(at now: Date) -> Bool {
        if case .spin = script { return !isResting(at: now) }
        return false
    }

    /// The 3D body is black: during a spin, the old color until 180°, then `live`.
    func black(at now: Date, live: Bool) -> Bool {
        guard case .spin(let turn) = script else { return live }
        return now.timeIntervalSince(start) - Self.spinFade < turn / 2 ? fromBlack : live
    }

    /// The color the 2D device must show while a spin runs, or nil to show its own (with its
    /// fade). The 2D device shows only in the crossfades, so it changes with the 3D body.
    func blackOverride(at now: Date, live: Bool) -> Bool? {
        isSpinning(at: now) ? black(at: now, live: live) : nil
    }

    /// The 3D view can draw on this Mac. Without it there is no arrival (change 288).
    @MainActor public static var canDraw: Bool { K3DRenderer.shared != nil }

    /// How long the script runs, from its start to the 2D device at full opacity.
    public var length: Double {
        switch script {
        case .flip: Self.duration
        case .arrive: Self.arriveTurn + Self.arriveFade
        case .spin(let turn): turn + 2 * Self.spinFade
        }
    }

    /// The back shows, or the device turns to it.
    public var toBack: Bool { to > 90 }

    /// Starts a turn to the other side, from where the device is now.
    public mutating func toggle(at now: Date, screen: CGImage?) {
        let current = pose(at: now).angle
        from = current
        to = toBack ? 0 : 180
        start = now
        script = .flip
        if toBack { self.screen = screen }
    }

    /// Starts a turn to the other side, as `toggle` does. A turn to the back first makes the
    /// screen picture and puts it in the 3D front, and only then starts the turn's clock: in
    /// build 194 the snapshot and the texture took time from the turn, and its first frames jumped.
    @MainActor public mutating func turn(screen make: () -> CGImage?) {
        let screen = toBack ? nil : make()
        if let screen { K3DRenderer.shared?.prepare(screen: screen) }
        toggle(at: .now, screen: screen)
    }

    /// No turn runs: the device rests on one side.
    func isResting(at now: Date) -> Bool { now.timeIntervalSince(start) >= length }

    /// The front shows flat, with no turn running: the 2D skin can show.
    public func restsOnFront(at now: Date) -> Bool { !toBack && isResting(at: now) }

    /// The arrival runs: the 2D device must not show before the 3D body has drawn.
    public var arriving: Bool { script == .arrive }

    /// How much the flat 2D device shows over the 3D body: 1 at rest on the front, 0 while the 3D
    /// body turns or rests on the back. They crossfade in the last 0.1 s of a turn that ends on
    /// the front, and in the first 0.1 s of a turn that starts from the resting front. The
    /// arrival crossfades in its last 0.35 s.
    public func flatOpacity(at now: Date) -> Double {
        let t = now.timeIntervalSince(start)
        if script == .arrive { return min(1, max(0, (t - Self.arriveTurn) / Self.arriveFade)) }
        if case .spin(let turn) = script {
            return t < Self.spinFade ? 1 - max(0, t) / Self.spinFade : min(1, max(0, (t - Self.spinFade - turn) / Self.spinFade))
        }
        if !toBack { return min(1, max(0, (t - (Self.duration - Self.fade)) / Self.fade)) }
        return from == 0 ? min(1, max(0, 1 - t / Self.fade)) : 0
    }

    /// The 3D body's size and opacity: 1 and 1, except while it arrives (gen.py `g1`: scale
    /// 0.55 + 0.45 e, alpha min(1, 2u), with e the ease-out of u over 1.6 s).
    func look(at now: Date) -> (scale: Double, opacity: Double) {
        guard script == .arrive else { return (1, 1) }
        let u = min(1, max(0, now.timeIntervalSince(start) / Self.arriveTurn))
        return (Self.arriveScale + (1 - Self.arriveScale) * Self.easeOut(u), min(1, 2 * u))
    }

    func pose(at now: Date) -> (angle: Double, lift: Double) {
        let t = now.timeIntervalSince(start)
        if script == .arrive {
            return (from + (to - from) * Self.easeOut(min(1, max(0, t / Self.arriveTurn))), 0)
        }
        if case .spin(let turn) = script {
            // 360° is the front again: the pose at rest is 0, so a later flip starts from 0.
            let u = min(1, max(0, (t - Self.spinFade) / turn))
            return ((360 * Self.quad(u)).truncatingRemainder(dividingBy: 360), 0)
        }
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
    /// gen.py `ez`: quad in-out.
    static func quad(_ p: Double) -> Double { p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2 }
    /// gen.py `eo`: 1 − (1 − p)³.
    static func easeOut(_ p: Double) -> Double { 1 - pow(1 - p, 3) }
}
