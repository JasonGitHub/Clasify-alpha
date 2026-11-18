import AppKit
import ClasifyCore
import Foundation
import Metal
import Testing

@testable import ClasifySkins

/// CLA-105: Take apart's parts in the mesh, checked against the mock's own geometry code
/// (`k3d_src3.js` from design-review/beta-page/v3/k3d8, lines 11 to 226; CLA-129: about/k3d11/tools,
/// the `D11` path of the drive, lines 212 to 233) run in Node. The mesh
/// puts the parts after the closed device, so the order differs from the mock's; the counts and
/// the sums of the positions do not.
struct K3DPartsTests {
    let mesh = K3DMesh()

    func value(_ i: Int, _ k: Int) -> Double { Double(mesh.vertices[i * K3DMesh.stride + k]) }

    @Test func theCountsMatchTheMock() {
        #expect(mesh.vertexCount == 35352)
        #expect(mesh.indices.count == 139746)
        #expect(mesh.indices.count % 3 == 0)
    }

    /// Each part: its vertex count and the sums of its x, y and z (Node, to 3 places).
    @Test func eachPartMatchesTheMock() {
        let want: [Int: (n: Int, x: Double, y: Double, z: Double)] = [
            0: (6435, 97297.000, 425110.000, -90769.827),
            1: (8446, -0.000, 62303.000, 247089.541),
            2: (1766, -0.000, 284767.500, 57925.100),
            3: (1576, -82716.000, -195696.000, 47231.580),
            4: (1712, 1496.000, 271799.000, 42952.820),
            5: (770, -0.000, -97790.000, 23139.150),
            6: (1766, -478.000, -51364.180, 38125.380),
            7: (5058, -3942.632, -307736.341, 55804.800),
            8: (192, 1464.000, -5784.000, 3494.400),
            9: (7631, -52018.000, -1110323.200, 154814.190),
        ]
        var got: [Int: (n: Int, x: Double, y: Double, z: Double)] = [:]
        for i in 0..<mesh.vertexCount {
            let part = Int(value(i, 12))
            let old = got[part] ?? (0, 0, 0, 0)
            got[part] = (old.n + 1, old.x + value(i, 0), old.y + value(i, 1), old.z + value(i, 2))
        }
        #expect(Set(got.keys) == Set(want.keys))
        for (part, w) in want {
            guard let g = got[part] else { continue }
            #expect(g.n == w.n, "part \(part): \(g.n) vertices")
            // Float positions: each sum may drift a little from the mock's doubles.
            #expect(abs(g.x - w.x) < 2 && abs(g.y - w.y) < 2 && abs(g.z - w.z) < 2, "part \(part): \(g)")
        }
    }

    /// Each material's vertex count, as in the mock.
    @Test func eachMaterialMatchesTheMock() {
        let want: [Int: Int] = [
            0: 844, 1: 1600, 2: 400, 3: 4973, 4: 101, 10: 831, 12: 4892, 13: 298, 14: 1452, 15: 1798, 16: 446, 17: 508,
            19: 20, 20: 80, 21: 3901, 22: 588, 23: 295, 24: 349, 25: 129, 27: 207, 28: 448, 29: 256, 30: 1650, 32: 650,
            34: 2301, 35: 402, 36: 308, 37: 3818, 38: 545, 39: 73, 40: 149, 41: 32, 42: 24, 43: 296, 44: 140, 45: 548,
        ]
        var got: [Int: Int] = [:]
        for i in 0..<mesh.vertexCount { got[Int(value(i, 11)), default: 0] += 1 }
        #expect(got == want)
    }

    /// #264 design check: the screen module's face (part 4, material 3) reads the picture at the
    /// closed front's uv (the mock's `uvOf`, and `pu = vuv`), so its LCD picture is the closed
    /// device's size. The picture's rect (the front texture's pixels 66 to 666 and 65 to 515)
    /// lies inside the module's face, so no picture pixel falls outside the module.
    @Test func theModuleShowsThePictureAtTheClosedSize() {
        var worst = 0.0, n = 0
        var lo = (x: Double.infinity, y: Double.infinity), hi = (x: -Double.infinity, y: -Double.infinity)
        for i in 0..<mesh.vertexCount where value(i, 12) == 4 && value(i, 11) == 3 {
            let x = value(i, 0), y = value(i, 1)
            let du = abs(value(i, 6) - (x / 366 + 0.5)), dv = abs(value(i, 7) - (0.5 - y / 613))
            worst = max(worst, du, dv)
            lo = (min(lo.x, x), min(lo.y, y))
            hi = (max(hi.x, x), max(hi.y, y))
            n += 1
        }
        #expect(n > 0)
        #expect(worst < 1e-4, "uv off by \(worst)")
        let picture = (x0: 66.0 / 2 - 183, x1: 666.0 / 2 - 183, y0: 306.5 - 515.0 / 2, y1: 306.5 - 65.0 / 2)
        #expect(lo.x <= picture.x0 && hi.x >= picture.x1, "module x \(lo.x)...\(hi.x), picture \(picture.x0)...\(picture.x1)")
        #expect(lo.y <= picture.y0 && hi.y >= picture.y1, "module y \(lo.y)...\(hi.y), picture \(picture.y0)...\(picture.y1)")
    }

    /// Nothing new draws on the closed device: everything after it is a Take apart material (above
    /// 10.5), or the screen module, which the opaque window hides.
    @Test func thePartsComeAfterTheClosedDevice() {
        #expect(mesh.closedVertexCount < mesh.vertexCount && mesh.closedIndexCount < mesh.indices.count)
        for i in mesh.closedVertexCount..<mesh.vertexCount {
            let material = value(i, 11), part = value(i, 12)
            if !(material > 10.5 || part == 4) {
                Issue.record("vertex \(i): material \(material), part \(part)")
                break
            }
        }
        #expect(mesh.indices[..<mesh.closedIndexCount].allSatisfy { Int($0) < mesh.closedVertexCount })
    }
}

/// CLA-105 PR B: the renderer draws the parts apart, and the closed device as before.
@Suite @MainActor struct K3DApartRenderTests {
    nonisolated static var hasMetal: Bool { MTLCreateSystemDefaultDevice() != nil }
    /// The device's size with 100 points round it, so a part that comes toward the eye is not
    /// cut off at the frame's edge.
    static let pad = 100
    var size: CGSize { CGSize(width: PocketSkin.size.width + 2 * Double(Self.pad), height: PocketSkin.size.height + 2 * Double(Self.pad)) }

    /// The mock's vertex shader (K.3D.11): each part's move along z at `ex` 1, then all back 152 pt.
    @Test func thePartsMoveAsInTheMock() {
        #expect(K3DShader.apart == [-40, 240, 285, 277, 196, 313, 130, 62, 62, 140.5])
        #expect(K3DShader.apartBack == 152)
        #expect(K3DShader.source.contains("constant float apart[10] = { -40.0, 240.0, 285.0, 277.0, 196.0, 313.0, 130.0, 62.0, 62.0, 140.5 };"))
        #expect(K3DShader.source.contains("pp.z -= u.ex * 152.0;"))
        #expect(K3DShader.source.contains("if (pt > 6.5 && pt < 7.5) { pp.x = -pp.x; pp.z = 2.0 - pp.z; nn.x = -nn.x; nn.z = -nn.z; }"))
    }

    /// K.3D.11: the drive is turned 180° about y; nothing else is.
    @Test func onlyTheDriveIsTurned() {
        let p = SIMD3<Float>(10, 20, 5)
        #expect(K3DShader.turnsDrive(p, part: 7) == SIMD3(-10, 20, -3))
        for part in [0, 6, 8, 9] { #expect(K3DShader.turnsDrive(p, part: Float(part)) == p) }
        #expect(K3DShader.source.contains("in.vo.z < 31.8"))  // the wheel hole's collar, T/2 − 2.2
    }

    /// The mock's `draw`: closed, one pass of the closed device with back faces culled.
    @Test func closedDrawsOnePassCulled() {
        #expect(K3DRenderer.passes(ex: 0) == (all: false, cull: true, glass: false))
        #expect(K3DRenderer.passes(ex: 0.0004) == (all: true, cull: true, glass: false))
        #expect(K3DRenderer.passes(ex: 0.0008) == (all: true, cull: true, glass: true))
        #expect(K3DRenderer.passes(ex: 0.5) == (all: true, cull: false, glass: true))
    }

    func frame(_ pose: K3DPose, _ name: String) throws -> [UInt8] {
        let renderer = try #require(K3DRenderer.shared)
        if pose.ex > 0 { renderer.makePrintsNow() }  // the design frames show the prints
        let bytes = try #require(renderer.image(pose, screen: nil, size: size, scale: 2))
        save(bytes, name)
        return bytes
    }

    /// Opaque pixels at 2x in one row, `row` in device points from the device's top.
    func width(_ bytes: [UInt8], row: Int) -> Int {
        let w = Int(size.width) * 2, y = (row + Self.pad) * 2
        return (0..<w).filter { bytes[(y * w + $0) * 4 + 3] == 255 }.count
    }

    /// The parts' own geometry is hidden at the start of the move: a frame a hair apart draws
    /// every part, and looks as the closed device.
    @Test(.enabled(if: Self.hasMetal, "no Metal device")) func theStartLooksClosed() throws {
        let closed = try frame(K3DPose(), "k3d-apart-0")
        let hair = try frame(K3DPose(ex: 1e-9), "k3d-apart-hair")
        let worst = zip(closed, hair).map { abs(Int($0) - Int($1)) }.max() ?? 0
        #expect(worst <= 1, "largest difference \(worst)")
    }

    /// CLA-129: the closed device does not change with the K.3D.11 parts. From 12 back, side and
    /// edge views, a closed frame equals a frame a hair apart, which draws every part's index:
    /// no inside part shows through the shell. The PNGs are for the design check.
    @Test(.enabled(if: Self.hasMetal, "no Metal device")) func noPartShowsThroughTheClosedShell() throws {
        let views: [(Double, Double)] = [(180, 0), (150, 0), (210, 0), (180, 20), (180, -20), (90, 0), (270, 0), (110, 15), (250, -15), (135, 30), (225, -30), (30, 10)]
        for (angle, tilt) in views {
            let name = "k3d-closed-\(Int(angle))-\(Int(tilt))"
            let closed = try frame(K3DPose(angle: angle, tilt: tilt), name)
            let hair = try frame(K3DPose(angle: angle, tilt: tilt, ex: 1e-9), name + "-hair")
            let worst = zip(closed, hair).map { abs(Int($0) - Int($1)) }.max() ?? 0
            #expect(worst <= 1, "\(name): largest difference \(worst)")
        }
    }

    /// Apart, the plate comes 68 pt toward the eye, so the device is wider on screen. The PNGs
    /// show the open pose of PR C (305°, tilt 20°) for the design check.
    @Test(.enabled(if: Self.hasMetal, "no Metal device")) func apartThePlateComesForward() throws {
        let closed = try frame(K3DPose(), "k3d-closed-front")
        let apart = try frame(K3DPose(ex: 1), "k3d-apart-front")
        #expect(width(apart, row: 450) > width(closed, row: 450) + 8, "\(width(apart, row: 450)) vs \(width(closed, row: 450))")
        for (ex, name) in [(0.5, "half"), (1.0, "full")] {
            for black in [false, true] {
                let bytes = try frame(K3DPose(angle: 305, tilt: 20, ex: ex, black: black), "k3d-apart-305-\(name)-\(black ? "black" : "silver")")
                #expect(width(bytes, row: 300) > 100)
            }
        }
        _ = try frame(K3DPose(angle: 180, ex: 1), "k3d-apart-back")
    }

    /// The open pose with the About screen, as the mock's frames show it, for a 1:1 design check:
    /// `pocket-k3d-apart-305-{half,full}-{silver,black}-about.png`.
    @Test(.enabled(if: Self.hasMetal, "no Metal device")) func apartWithTheAboutScreen() throws {
        let renderer = try #require(K3DRenderer.shared)
        for black in [false, true] {
            var state = AppState()
            state.deviceColor = black ? .black : .silver
            state.stack = [Frame(screen: .main), Frame(screen: .settings), Frame(screen: .about)]
            let shot = try #require(K3DSpike.snapshot(state))
            for (ex, name) in [(0.5, "half"), (1.0, "full")] {
                let pose = K3DPose(angle: 305, tilt: 20, ex: ex, black: black)
                renderer.makePrintsNow()
                let bytes = try #require(renderer.image(pose, screen: shot, size: size, scale: 2))
                save(bytes, "k3d-apart-305-\(name)-\(black ? "black" : "silver")-about")
                #expect(width(bytes, row: 300) > 100)
            }
        }
    }

    func save(_ bytes: [UInt8], _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else { return }
        let w = Int(size.width) * 2, h = Int(size.height) * 2
        var copy = bytes
        let image = copy.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)?.makeImage()
        }
        guard let image, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("pocket-\(name).png"))
    }

    /// CLA-105 B3: the first apart frame does not wait for the prints. They are drawn off the
    /// main actor, bound when ready, and released when the device is closed again. Its own
    /// renderer, so other tests' frames do not close it in between.
    @Test(.enabled(if: Self.hasMetal, "no Metal device")) func theFirstApartFrameDoesNotWaitForThePrints() async throws {
        let renderer = try #require(K3DRenderer())
        let clock = ContinuousClock()
        let start = clock.now
        _ = try #require(renderer.image(K3DPose(angle: 305, tilt: 20, ex: 0.1), screen: nil, size: size, scale: 2))
        let first = clock.now - start
        #expect(!renderer.printsReady, "the first frame does not draw the prints itself")
        await renderer.preparePrints().value
        let ready = clock.now - start
        #expect(renderer.printsReady)
        _ = try #require(renderer.image(K3DPose(angle: 305, tilt: 20, ex: 0.2), screen: nil, size: size, scale: 2))
        #expect(renderer.printsReady)
        _ = try #require(renderer.image(K3DPose(), screen: nil, size: size, scale: 2))
        #expect(!renderer.printsReady, "closed again: the prints are released")
        print("CLA-105 B3: first apart frame \(first), prints ready after \(ready)")
    }
}
