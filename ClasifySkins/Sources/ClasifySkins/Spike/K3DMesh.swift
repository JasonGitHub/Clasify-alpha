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
/// CLA-105: Take apart's parts are in the mesh too (`K3DParts.swift`): the screen module (part 4),
/// the frame (6), the drive (7), the foam pad (8), the logic board (9), the inner skins and the
/// inside of the shell. They come after the closed device's vertices and indices, so the closed
/// device draws the first `closedIndexCount` indices, exactly as before.
struct K3DMesh {
    static let width = 366.0, height = 613.0, depth = 68.0, radius = 34.0
    /// Floats per vertex.
    static let stride = 13
    /// The wheel's and the center button's center.
    static let wheelCenter = SIMD2<Double>(0, -127)

    private(set) var vertices: [Float] = []
    private(set) var indices: [UInt32] = []
    /// The part new vertices belong to.
    var part = 0
    /// The closed device: its vertices and indices come first. The rest only Take apart shows
    /// (in the mock: materials above 10.5, hidden while assembled, and the screen module).
    private(set) var closedVertexCount = 0, closedIndexCount = 0

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
        // CLA-105: the triangles so far, and the plate's last ring and the shell's first: the
        // inner skins are made from them.
        let capped = indices.count
        let plateRim = rings[ringParts.lastIndex(of: 1) ?? 0], shellRim = rings[ringParts.firstIndex(of: 0) ?? 0]

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

        closedVertexCount = vertexCount
        closedIndexCount = indices.count
        addParts(capped: capped, plateRim: plateRim, shellRim: shellRim)
    }

    /// Adds triangles by their vertex indices.
    mutating func triangles(_ ids: [UInt32]) { indices += ids }

    mutating func vertex(
        _ p: (Double, Double, Double), _ n: (Double, Double, Double), _ uv: (Double, Double), _ material: Int,
        uv2: (Double, Double)? = nil, weight: Double = 1
    ) -> UInt32 {
        let index = UInt32(vertexCount)
        let u2 = uv2 ?? uv
        vertices += [p.0, p.1, p.2, n.0, n.1, n.2, uv.0, uv.1, u2.0, u2.1, weight, Double(material), Double(part)].map { Float($0) }
        return index
    }

    func uvOf(_ x: Double, _ y: Double) -> (Double, Double) {
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
    mutating func disc(_ outline: [SIMD4<Double>], z: Double, material: Int, center: (Double, Double)) {
        let c = vertex((center.0, center.1, z), (0, 0, 1), uvOf(center.0, center.1), material)
        let ids = outline.map { vertex(($0.x, $0.y, z), (0, 0, 1), uvOf($0.x, $0.y), material) }
        for i in ids.indices { indices += [c, ids[i], ids[(i + 1) % ids.count]] }
    }

    /// A straight wall along an outline, drawn with both windings so it shows from either side.
    mutating func band(
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

/// Which arrival a new device window plays (card BR, changes 288 and 303; CLA-117).
public enum K3DArrival: Equatable, Sendable {
    /// The first launch ever: change 288 with Hello. The skin sends `.arrived` from it.
    case first
    /// A later launch, as `arrive.cold` says: change 303, or change 288 with no Hello.
    case short, full
    /// No turn: the 2D device shows at once.
    case still

    /// The UserDefaults string `arrive.cold`, read at launch: missing or "short" is change 303,
    /// "full" is change 288, any other value is no arrival.
    public enum Cold: Equatable, Sendable {
        case short, full, off

        public init(_ value: String?) {
            switch value {
            case nil, "short": self = .short
            case "full": self = .full
            default: self = .off
            }
        }
    }

    /// The arrival for a window: `arrived` is the saved first-launch flag, `launched` that this
    /// launch already had its arrival, `canTurn` that motion is on and Metal can draw.
    public static func pick(arrived: Bool, launched: Bool, cold: Cold, canTurn: Bool) -> K3DArrival {
        if !arrived { return canTurn ? .first : .still }  // the skin still sends `.arrived` at once
        guard !launched, canTurn else { return .still }
        switch cold {
        case .short: return .short
        case .full: return .full
        case .off: return .still
        }
    }
}

/// A turn of the 3D device, as a script. `flip` is the mock's `flip()` (CLA-101): the device
/// turns 180° in 0.82 s with a 2.5% overshoot, settles by 1.0 s, and is pushed back by up to
/// 70 pt while it turns; the 3D body and the flat 2D device crossfade in 0.1 s. `arrive` is
/// card BR's first launch (change 288): from -120° and 55% size, one ease-out turn to the front
/// in 1.6 s, fading in over the first 0.8 s; then the 2D device fades in over 0.35 s while
/// Hello writes (Jason, 23:05 JST 11-15: no rest, so Hello comes sooner). `spin` is card BR's color change (changes 289 and 290): the device crossfades to 3D
/// in 0.15 s, turns 360° with a quad in-out, and crossfades back in 0.15 s. It shows the old
/// color until 180°, then the color the device has now. `arriveShort` is change 303, the
/// cold-start trial (CLA-117): from -60° and 80% size, one ease-out turn to the front in 1.0 s,
/// fading in over the first 0.25 s, with the 2D device fading in over the turn's last 0.15 s.
/// Input during it hurries the rest of the turn 4 times.
public struct K3DFlip {
    static let turn = 0.82, duration = 1.0, lift = 70.0
    /// The crossfade between the 3D body and the flat 2D device.
    static let fade = 0.1
    /// CLA-119: past `restAngle`, the degrees over which the flip's push back comes in.
    static let liftIn = 18.0
    /// Card BR, change 288: the arrival's turn and its crossfade to the 2D device.
    public static let arriveTurn = 1.6, arriveFade = 0.35, arriveFrom = -120.0, arriveScale = 0.55
    /// When the skin sends `.arrived`, before the turn ends: Hello's wait before its first
    /// stroke, so the first stroke lands on the turn's last frame.
    public static let arriveHelloLead = Hello.lead

    /// Changes 289 and 290: the color spin's crossfades, and its turn on Pick Your Color and in
    /// Settings.
    static let spinFade = 0.15
    public static let spinPick = 1.4, spinSettings = 0.8

    /// Change 303 (cold.py `arr`): the short arrival's turn, start angle, start size, fade-in,
    /// its crossfade to the 2D device at the end of the turn, and how much faster input runs the rest.
    static let shortTurn = 1.0, shortFrom = -60.0, shortScale = 0.8, shortFadeIn = 0.25, shortFade = 0.15
    static let shortHurry = 4.0

    /// Card BT row 2 (CLA-118): the About showroom. `held` is a drag in progress, `go` a turn
    /// of `go` seconds (`soft`: the turn-over landing, 306), `nudge` the first-time nudge (297),
    /// `swap` the Reduce Motion side change (302).
    enum Script: Equatable { case flip, arrive, arriveShort, spin(Double), held, go(Double, soft: Bool), nudge, swap, apart }
    /// Card BT row 2: a turn-over, the return of a short drag, the nudge, the Reduce Motion swap.
    public static let turnOver = 0.8, dragReturn = 0.4, nudgeTime = 0.9, swapTime = 0.2
    static let overshoot = 3.0, nudgeAngle = 16.0
    /// CLA-105 Take apart (change 308; the showroom trial Jason approved, bt/show/index.html
    /// `open` and `close`): opening, the device turns to 305° and tilts to 20° in 0.7 s on a
    /// quad in-out, then the parts move apart in 1.6 s on a cubic in-out (mock K.3D.8
    /// `explode`). Closing, the parts move together in 1.6 s where the device is, then it turns
    /// to the front by the short way and levels out in 0.6 s. CLA-130 (354, 355): the Cmd turn's
    /// close (`staysTurned`) keeps the angle and the tilt: only Cmd up turns it to the front.
    public static let apartTurn = 0.7, apartTime = 1.6, closeTurn = 0.6
    static let apartAngle = 305.0, apartTilt = 20.0

    /// The angle the last turn started from and goes to, in degrees: 0 is the front, 180 the back.
    private(set) var from = 0.0, to = 0.0
    /// When the last turn started.
    private(set) var start = Date.distantPast
    private(set) var script = Script.flip
    /// The spin's old color (changes 289 and 290).
    private(set) var fromBlack = false
    /// A live picture of the device for the 3D front's screen, taken when the turn started.
    public private(set) var screen: CGImage?
    /// CLA-119: in a color spin, the picture in the old color, which the 3D front shows to 180°.
    public private(set) var oldScreen: CGImage?
    /// Card BT row 2: the tilt (pitch, degrees) the script starts from, which levels out; and
    /// whether it starts from the front at rest, where the 2D device shows.
    private(set) var tilt0 = 0.0
    private(set) var fromRest = false
    /// Change 303: when input hurried the short arrival, and the script time it had then.
    private(set) var hurriedAt: Date?
    private(set) var hurriedFrom = 0.0
    /// CLA-105: how far apart the parts are at the start of `apart` and where they go (0 closed,
    /// 1 apart), and the tilt the apart script goes to. Other scripts keep `exTo`, so a turn of
    /// the open device stays open.
    private(set) var ex0 = 0.0, exTo = 0.0, tiltTo = 0.0

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

    /// Change 303, the cold-start trial: the short arrival. As for `arrive`, the clock starts
    /// after the screen picture is made.
    @MainActor public static func arriveShort(at now: Date? = nil, screen make: () -> CGImage?) -> K3DFlip {
        var flip = K3DFlip()
        flip.show(screen: make())
        flip.script = .arriveShort
        (flip.from, flip.to, flip.start) = (shortFrom, 0, now ?? .now)
        return flip
    }

    /// Change 303: input during the short arrival runs the rest of it 4 times faster, so the
    /// device lands in 0.25 s at most. Once only; other scripts do not change.
    public mutating func hurry(at now: Date) {
        guard script == .arriveShort, hurriedAt == nil, !isResting(at: now) else { return }
        hurriedFrom = max(0, now.timeIntervalSince(start))
        hurriedAt = now
    }

    /// The script's time at `now`, in seconds from its start: the clock, or 4 times faster after
    /// a hurry (change 303).
    func elapsed(at now: Date) -> Double {
        guard let hurriedAt, now > hurriedAt else { return now.timeIntervalSince(start) }
        return hurriedFrom + Self.shortHurry * now.timeIntervalSince(hurriedAt)
    }

    /// When the script ends, with the 2D device at full opacity.
    public var ends: Date {
        guard let hurriedAt else { return start.addingTimeInterval(length) }
        return hurriedAt.addingTimeInterval((length - hurriedFrom) / Self.shortHurry)
    }

    /// The short arrival runs: the 2D device, hidden, still takes the wheel and the keys, and
    /// the 3D screen stays live (change 303).
    public func takesInput(at now: Date) -> Bool {
        script == .arriveShort ? !isResting(at: now) : isSpinning(at: now)
    }

    /// Input waits: the full arrival (change 288, and the cold-start "full" trial) has not landed.
    public func holdsInput(at now: Date) -> Bool {
        script == .arrive && elapsed(at: now) < Self.arriveTurn
    }

    /// Changes 289 and 290: a color spin with a turn of `turn` seconds. The device was black
    /// before the change when `fromBlack`. The clock starts after the screen pictures are made:
    /// `make` in the new color, `old` in the old color, as the 2D device shows to 180° (CLA-119).
    @MainActor public static func spin(
        turn: Double, fromBlack: Bool, at now: Date? = nil, screen make: () -> CGImage?, old: () -> CGImage? = { nil }
    ) -> K3DFlip {
        var flip = K3DFlip()
        flip.show(screen: make())
        flip.show(old: old())
        flip.script = .spin(turn)
        (flip.fromBlack, flip.start) = (fromBlack, now ?? .now)
        return flip
    }

    /// Card BT row 2: a drag in progress holds the device at `angle` and `tilt` (change 307),
    /// with no clock. The screen picture stays.
    public func held(angle: Double, tilt: Double) -> K3DFlip {
        var flip = self
        flip.script = .held
        (flip.from, flip.to, flip.start, flip.tilt0, flip.hurriedAt) = (angle, angle, .now, tilt, nil)
        flip.oldScreen = nil
        flip.fromRest = false
        return flip
    }

    /// Card BT row 2: a turn from where the device is now to the side `to` (a multiple of 180°)
    /// in `time` seconds. `soft` is the turn-over's landing (306): ease-out to 3° past the side
    /// over 75 % of the time, then back with a quad in-out. Otherwise one ease-out (the return
    /// of a short drag). The tilt levels out in the first half. Both angles shift by whole turns
    /// so the device ends at 0 or 180.
    public func go(to side: Double, time: Double, soft: Bool, at now: Date) -> K3DFlip {
        var flip = self
        let current = pose(at: now).angle, tilt = self.tilt(at: now)
        let shift = 360 * (side / 360).rounded(.down)
        flip.fromRest = restsOnFront(at: now)
        flip.script = .go(time, soft: soft)
        (flip.from, flip.to, flip.start, flip.tilt0, flip.hurriedAt) = (current - shift, side - shift, now, tilt, nil)
        flip.oldScreen = nil
        return flip
    }

    /// Change 297: the first-time nudge, 16° and back on a quad in-out in 0.9 s, from the side the
    /// device rests on.
    public func nudge(at now: Date) -> K3DFlip {
        var flip = self
        let side = flip.toBack ? 180.0 : 0
        flip.fromRest = restsOnFront(at: now)
        flip.script = .nudge
        (flip.from, flip.to, flip.start, flip.tilt0, flip.hurriedAt) = (side, side, now, 0, nil)
        flip.oldScreen = nil
        return flip
    }

    /// Change 302, Reduce Motion: no turn. The 3D body fades out in 0.1 s and fades in on the
    /// other side `to` in 0.1 s.
    public func swap(to side: Double, at now: Date) -> K3DFlip {
        var flip = self
        let current = pose(at: now).angle
        let shift = 360 * (side / 360).rounded(.down)
        flip.fromRest = restsOnFront(at: now)
        flip.script = .swap
        (flip.from, flip.to, flip.start, flip.tilt0, flip.hurriedAt) = (current - shift, side - shift, now, 0, nil)
        flip.oldScreen = nil
        return flip
    }

    /// CLA-105: takes the device apart if it is closed, or puts it together if it is apart.
    /// Nothing happens while the apart script runs (the trial's `busy`). Opening starts from the
    /// angle now, as 0° to 360°; closing turns from the angle now, as -180° to 180°, so the turn
    /// to the front is the short way.
    public func apart(at now: Date, staysTurned: Bool = false) -> K3DFlip {
        if script == .apart && !isResting(at: now) { return self }
        var flip = self
        let current = pose(at: now).angle, tilt = self.tilt(at: now)
        let opens = exTo == 0
        let turn = (current.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        flip.fromRest = restsOnFront(at: now)
        flip.script = .apart
        (flip.start, flip.tilt0, flip.hurriedAt) = (now, tilt, nil)
        let short = turn > 180 ? turn - 360 : turn
        (flip.from, flip.to) = opens ? (turn, Self.apartAngle) : (short, staysTurned ? short : 0)
        flip.tiltTo = opens ? Self.apartTilt : staysTurned ? tilt : 0
        (flip.ex0, flip.exTo) = opens ? (0, 1) : (1, 0)
        flip.oldScreen = nil
        return flip
    }

    /// CLA-105: the apart script runs: input waits (the trial's `busy`).
    public func apartRuns(at now: Date) -> Bool { script == .apart && !isResting(at: now) }

    /// CLA-105: the parts are apart, or the apart script runs.
    public func isApart(at now: Date) -> Bool { exTo > 0 || apartRuns(at: now) }

    /// CLA-105 D: the press-and-hold on the back started: the prints are drawn now and the
    /// parts' first frame is drawn off screen, so the device opens with no wait.
    @MainActor public static func prepareApart() {
        guard let renderer = K3DRenderer.shared else { return }
        renderer.preparePrints()
        renderer.warmApart()
    }

    /// CLA-105 D: the hold was let go before it opened the device, or About was left.
    @MainActor public static func releaseApart() { K3DRenderer.shared?.releasePrints() }

    /// The apart script opens the device (else it closes it).
    var opens: Bool { exTo > ex0 }

    /// CLA-105: how far apart the parts are at `now`: 0 closed, 1 apart.
    public func ex(at now: Date) -> Double {
        guard script == .apart else { return exTo }
        let t = elapsed(at: now) - (opens ? Self.apartTurn : 0)
        return ex0 + (exTo - ex0) * Self.ease(min(1, max(0, t / Self.apartTime)))
    }

    /// The share of the apart script's turn and tilt done at `now`: before the parts move when
    /// it opens, after they close when it closes.
    func apartTurn(at now: Date) -> Double {
        let t = elapsed(at: now)
        let u = opens ? t / Self.apartTurn : (t - Self.apartTime) / Self.closeTurn
        return Self.quad(min(1, max(0, u)))
    }

    /// The angle the device shows at `now`, in degrees.
    public func angle(at now: Date) -> Double { pose(at: now).angle }

    /// Change 307: the tilt (pitch, degrees) at `now`. A drag holds it; a turn from a drag
    /// levels it out in the first half of the turn (trial: `tl0 (1 − eo(2u))`).
    public func tilt(at now: Date) -> Double {
        switch script {
        case .held: return tilt0
        case .apart: return tilt0 + (tiltTo - tilt0) * apartTurn(at: now)
        case .go(let time, _):
            let u = time > 0 ? min(1, max(0, elapsed(at: now) / time)) : 1
            return tilt0 * (1 - Self.easeOut(min(1, 2 * u)))
        default: return 0
        }
    }

    /// Puts a new picture in the 3D front's screen: during a spin the screen stays live.
    @MainActor public mutating func show(screen: CGImage?) {
        if let screen { K3DRenderer.shared?.prepare(screen: screen) }
        self.screen = screen
    }

    /// CLA-119: puts a new old-color picture in the 3D front during a spin, as `show(screen:)`.
    @MainActor public mutating func show(old: CGImage?) {
        K3DRenderer.shared?.show(old: old)
        oldScreen = old
    }

    /// CLA-119: the old color while a spin still shows it (to 180°), or nil. A change on the
    /// screen then needs a new picture in that color too (`show(old:)`).
    public func oldColor(at now: Date) -> Bool? {
        guard case .spin(let turn) = script, now.timeIntervalSince(start) - Self.spinFade < turn / 2 else { return nil }
        return fromBlack
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
        case .arriveShort: Self.shortTurn
        case .spin(let turn): turn + 2 * Self.spinFade
        case .held: 0
        case .go(let time, _): time
        case .nudge: Self.nudgeTime
        case .swap: Self.swapTime
        case .apart: Self.apartTime + (opens ? Self.apartTurn : Self.closeTurn)
        }
    }

    /// The back shows, or the device turns to it.
    public var toBack: Bool {
        let a = to.truncatingRemainder(dividingBy: 360), n = a < 0 ? a + 360 : a
        return n > 90 && n < 270
    }

    /// Starts a turn to the other side, from where the device is now.
    public mutating func toggle(at now: Date, screen: CGImage?) {
        let current = pose(at: now).angle
        from = current
        to = toBack ? 0 : 180
        start = now
        script = .flip
        hurriedAt = nil
        oldScreen = nil
        tilt0 = 0
        fromRest = false
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
    public func isResting(at now: Date) -> Bool { elapsed(at: now) >= length }

    /// CLA-138 (build 327: one empty frame as a Cmd turn starts): the 3D body is on screen (its
    /// Metal view at full opacity) when the 2D device shows at `shown` below 1, and also while a
    /// Cmd turn holds the device (`K3DTurn.settle` at the front, and every held pose). A spin
    /// and a timed turn cross the 2° fade over several frames, so the body is on screen under
    /// an almost opaque 2D device first. A Cmd turn jumps past 2° in one frame after the settle:
    /// without this, the Metal view became visible in the same frame as the 2D device went, and
    /// its layer came one frame late.
    public func bodyShows(shown: Double) -> Bool { shown < 1 || script == .held }

    /// The front shows flat, with no turn running: the 2D skin can show.
    /// CLA-105: closed again after a take-apart, it rests on the front only at 0° with no tilt.
    public func restsOnFront(at now: Date) -> Bool {
        guard script != .held, !toBack, isResting(at: now), exTo == 0 else { return false }
        return script != .apart || Self.nearRest(angle: pose(at: now).angle, tilt: tilt(at: now)) >= 1
    }

    /// An arrival runs: the 2D device must not show before the 3D body has drawn.
    public var arriving: Bool { script == .arrive || script == .arriveShort }

    /// How much the flat 2D device shows over the 3D body: 1 at rest on the front, 0 while the 3D
    /// body turns or rests on the back. CLA-119: the 3D front at rest is the 2D device, so the two
    /// hand over by angle: the 2D device fades out from rest to `restAngle` (2°) off it, as the
    /// shader's `nearRest`. Its outline line and its size fade with it. Where a turn passes 0° on
    /// its way to land (the flip's swing past the front, the turn-over's 3°), the 2D device waits
    /// for the landing. The arrivals and the Reduce Motion swap keep their fades in time:
    /// the arrival in its last 0.35 s, the short arrival in its turn's last 0.15 s.
    public func flatOpacity(at now: Date) -> Double {
        let t = elapsed(at: now)
        if ex(at: now) > 0 { return 0 }  // CLA-105: apart, only the 3D parts show
        switch script {
        case .arrive: return min(1, max(0, (t - Self.arriveTurn) / Self.arriveFade))
        case .arriveShort: return min(1, max(0, (t - (Self.shortTurn - Self.shortFade)) / Self.shortFade))
        case .swap:
            // Card BT row 2: out in the first 0.1 s from the resting front, in at the end on the front.
            let gap = Self.swapTime / 2
            let fadeIn = toBack ? 0 : (t - gap - (length - gap - Self.fade)) / Self.fade
            let out = fromRest ? 1 - t / Self.fade : 0
            return min(1, max(0, max(fadeIn, out)))
        case .flip:
            if !toBack && t < Self.turn { return 0 }  // swings past the front first
        case .go(let time, let soft):
            if soft && !toBack && t < 0.75 * time { return 0 }  // swings 3° past the front first
        case .held, .nudge, .spin, .apart: break
        }
        return Self.nearRest(angle: pose(at: now).angle, tilt: tilt(at: now))
    }

    /// CLA-119: 1 at rest on the front, 0 from `restAngle` off it, smooth in degrees, for a turn
    /// of `angle` and a tilt of `tilt` (degrees): the shader's `nearRest`, from the same angle
    /// between the body's z and the eye.
    static func nearRest(angle: Double, tilt: Double) -> Double {
        1 - K3DRenderer.smooth(offRest(angle: angle, tilt: tilt) / K3DShader.restAngle)
    }

    /// The angle between the body's z and the eye, in degrees, for a turn and a tilt.
    static func offRest(angle: Double, tilt: Double) -> Double {
        let c = cos(angle * .pi / 180) * cos(tilt * .pi / 180)
        return acos(min(1, c)) * 180 / .pi
    }

    /// The 3D body's size and opacity: 1 and 1, except while it arrives (gen.py `g1`: scale
    /// 0.55 + 0.45 e, alpha min(1, 2u), with e the ease-out of u over 1.6 s). The short arrival
    /// (cold.py `arr`): scale 0.8 + 0.2 e over 1.0 s, alpha min(1, t / 0.25 s).
    func look(at now: Date) -> (scale: Double, opacity: Double) {
        if script == .swap {
            let t = min(Self.swapTime, max(0, elapsed(at: now)))
            return (1, min(1, abs(1 - 2 * t / Self.swapTime)))
        }
        if script == .arriveShort {
            let t = elapsed(at: now), e = Self.easeOut(min(1, max(0, t / Self.shortTurn)))
            return (Self.shortScale + (1 - Self.shortScale) * e, min(1, max(0, t / Self.shortFadeIn)))
        }
        guard script == .arrive else { return (1, 1) }
        let u = min(1, max(0, now.timeIntervalSince(start) / Self.arriveTurn))
        return (Self.arriveScale + (1 - Self.arriveScale) * Self.easeOut(u), min(1, 2 * u))
    }

    func pose(at now: Date) -> (angle: Double, lift: Double) {
        let t = elapsed(at: now)
        if script == .arrive {
            return (from + (to - from) * Self.easeOut(min(1, max(0, t / Self.arriveTurn))), 0)
        }
        if script == .arriveShort {
            return (from + (to - from) * Self.easeOut(min(1, max(0, t / Self.shortTurn))), 0)
        }
        switch script {
        case .held: return (from, 0)
        case .go(let time, let soft):
            let u = time > 0 ? min(1, max(0, t / time)) : 1
            guard soft else { return (from + (to - from) * Self.easeOut(u), 0) }
            let over = Self.overshoot * (to < from ? -1 : 1)
            if u < 0.75 { return (from + (to + over - from) * Self.easeOut(u / 0.75), 0) }
            return (to + over * (1 - Self.quad((u - 0.75) / 0.25)), 0)
        case .nudge:
            // At rest exactly on the side, so a later flip starts from the resting front.
            guard t < Self.nudgeTime else { return (to, 0) }
            return (to + Self.nudgeAngle * sin(.pi * Self.quad(max(0, t / Self.nudgeTime))), 0)
        case .swap: return (t < Self.swapTime / 2 ? from : to, 0)
        case .apart: return (from + (to - from) * apartTurn(at: now), 0)
        default: break
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
        // CLA-119: no push back while the 2D device shows (within `restAngle` of the front), so
        // the 3D body under it is the 2D device's size. It comes in smoothly from 2° to 20°.
        let off = Self.offRest(angle: angle, tilt: 0) - K3DShader.restAngle
        let away = K3DRenderer.smooth(off / Self.liftIn)
        return (angle, Self.lift * sin(.pi * p) * away)
    }

    static func ease(_ p: Double) -> Double { p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2 }
    /// gen.py `ez`: quad in-out.
    static func quad(_ p: Double) -> Double { p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2 }
    /// gen.py `eo`: 1 − (1 − p)³.
    static func easeOut(_ p: Double) -> Double { 1 - pow(1 - p, 3) }
}
