import AppKit
import Foundation
import Metal
import Testing

@testable import ClasifySkins

/// CLA-105: Take apart's parts in the mesh, checked against the mock's own geometry code
/// (`k3d_src3.js` from design-review/beta-page/v3/k3d8, lines 11 to 226) run in Node. The mesh
/// puts the parts after the closed device, so the order differs from the mock's; the counts and
/// the sums of the positions do not.
struct K3DPartsTests {
    let mesh = K3DMesh()

    func value(_ i: Int, _ k: Int) -> Double { Double(mesh.vertices[i * K3DMesh.stride + k]) }

    @Test func theCountsMatchTheMock() {
        #expect(mesh.vertexCount == 32935)
        #expect(mesh.indices.count == 137856)
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
            7: (2641, 12719.667, -134373.797, 10989.020),
            8: (192, 1716.000, -5592.000, 3283.200),
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
            0: 844, 1: 1600, 2: 400, 3: 4973, 4: 101, 10: 831, 12: 5647, 13: 318, 14: 1712, 15: 1798, 16: 466, 17: 508,
            19: 20, 20: 80, 21: 3901, 22: 588, 23: 295, 24: 349, 25: 129, 27: 207, 28: 448, 29: 256, 30: 1650, 32: 650,
            34: 2301, 35: 402, 36: 308, 37: 218, 38: 545, 39: 73, 40: 149, 41: 40, 42: 24, 43: 296, 44: 140, 45: 668,
        ]
        var got: [Int: Int] = [:]
        for i in 0..<mesh.vertexCount { got[Int(value(i, 11)), default: 0] += 1 }
        #expect(got == want)
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
    var size: CGSize { PocketSkin.size }

    /// The mock's vertex shader: each part's move along z at `ex` 1, then all back 172 pt.
    @Test func thePartsMoveAsInTheMock() {
        #expect(K3DShader.apart == [0, 240, 285, 277, 196, 313, 130, 62, 127.5, 140.5])
        #expect(K3DShader.apartBack == 172)
        #expect(K3DShader.source.contains("constant float apart[10] = { 0.0, 240.0, 285.0, 277.0, 196.0, 313.0, 130.0, 62.0, 127.5, 140.5 };"))
        #expect(K3DShader.source.contains("pp.z -= u.ex * 172.0;"))
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
        let bytes = try #require(renderer.image(pose, screen: nil, size: size, scale: 2))
        save(bytes, name)
        return bytes
    }

    /// Opaque pixels in one row, at 2x.
    func width(_ bytes: [UInt8], row: Int) -> Int {
        let w = Int(size.width) * 2
        return (0..<w).filter { bytes[(row * 2 * w + $0) * 4 + 3] == 255 }.count
    }

    /// The parts' own geometry is hidden at the start of the move: a frame a hair apart draws
    /// every part, and looks as the closed device.
    @Test(.enabled(if: Self.hasMetal, "no Metal device")) func theStartLooksClosed() throws {
        let closed = try frame(K3DPose(), "k3d-apart-0")
        let hair = try frame(K3DPose(ex: 1e-9), "k3d-apart-hair")
        let worst = zip(closed, hair).map { abs(Int($0) - Int($1)) }.max() ?? 0
        #expect(worst <= 1, "largest difference \(worst)")
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
}
