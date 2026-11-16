import AppKit
import ClasifyCore
import Foundation
import Metal
import Testing
import simd

@testable import ClasifySkins

/// CLA-119: the 3D is drawn at 2x over the body's rect only, then filtered 2:1 (mock K.3D.8's
/// canvas). The rect must hold the body at every pose, or the body is cut.
@Suite @MainActor struct K3DSupersampleTests {
    nonisolated static var hasMetal: Bool { MTLCreateSystemDefaultDevice() != nil }
    /// The window's room round the device on About (`K3DFlipView`'s margins are about this).
    static let room = 120.0
    var size: CGSize { CGSize(width: PocketSkin.size.width + 2 * Self.room, height: PocketSkin.size.height + 2 * Self.room) }
    var center: CGPoint { CGPoint(x: size.width / 2, y: size.height / 2) }

    /// The poses the app draws: turns, the arrival (lift, scale, from −120°), the showroom's
    /// tilt, and Take apart at its open pose.
    nonisolated static let poses: [K3DPose] = [
        K3DPose(), K3DPose(angle: 30), K3DPose(angle: 90, lift: 70), K3DPose(angle: 180), K3DPose(angle: 270, lift: 70),
        K3DPose(angle: -120, lift: 70, scale: 0.55), K3DPose(angle: -60, scale: 0.8), K3DPose(angle: 8, tilt: 6),
        K3DPose(angle: 200, tilt: -6), K3DPose(angle: 305, tilt: 20, ex: 1), K3DPose(angle: 305, tilt: 20, ex: 0.15),
        K3DPose(angle: 90, tilt: 20, ex: 1), K3DPose(angle: 180, tilt: -20, ex: 0.5),
        K3DPose(angle: 30, ex: 0.002), K3DPose(angle: 30, ex: 0.0021),
    ]

    /// Every point of the mesh, moved as the vertex shader moves it, falls inside the rect.
    @Test(arguments: poses) func theRectHoldsTheBody(_ pose: K3DPose) throws {
        let mesh = K3DMesh()
        let box = K3DRenderer.box(mesh, apart: K3DRenderer.apartRect(ex: pose.ex))
        let rect = try #require(K3DRenderer.bodyRect(box, pose: pose, size: size, center: center, pixelScale: 2))
        let m = K3DRenderer.projection(size: size, center: center, scale: pose.scale)
            * K3DRenderer.modelView(angle: pose.angle, lift: pose.lift, tilt: pose.tilt)
        let ex = Float(pose.ex), cg = Float(1 - smooth(0.16, 0.6, pose.ex))
        var outside = 0
        for i in 0..<(pose.ex > 0 ? mesh.vertexCount : mesh.closedVertexCount) {
            let e = i * K3DMesh.stride
            var p = SIMD3(mesh.vertices[e], mesh.vertices[e + 1], mesh.vertices[e + 2])
            let mat = mesh.vertices[e + 11], pt = mesh.vertices[e + 12]
            p.z += ex * (K3DShader.apart[Int(min(max(pt + 0.5, 0), 9))] - K3DShader.apartBack)
            let cable = pt > 2.5 && pt < 3.5 && ((mat > 13.5 && mat < 16.5) || (mat > 40.5 && mat < 41.5))
            if (ex < 0.06 && mat > 10.5) || (cable && ex < 0.14) { continue }  // hidden, as the vertex shader hides them
            if cable { p.x += 160 * cg; p.z -= 2 * cg }
            let q = m * SIMD4(p, 1)
            let x = (Double(q.x / q.w) + 1) / 2 * size.width * 2, y = (1 - Double(q.y / q.w)) / 2 * size.height * 2
            if x < Double(rect.x) || x > Double(rect.x + rect.w) || y < Double(rect.y) || y > Double(rect.y + rect.h) { outside += 1 }
        }
        #expect(outside == 0, "\(pose): \(outside) points outside \(rect)")
    }

    func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    /// Drawn, the body never touches the rect's edge: the rect's outermost pixels stay clear.
    @Test(.enabled(if: Self.hasMetal, "no Metal device"), arguments: poses)
    func theBodyIsNotCut(_ pose: K3DPose) throws {
        let renderer = try #require(K3DRenderer.shared)
        let bytes = try #require(renderer.image(pose, screen: nil, size: size, scale: 2))
        let w = Int(size.width) * 2
        let box = K3DRenderer.box(K3DMesh(), apart: K3DRenderer.apartRect(ex: pose.ex))
        let rect = try #require(K3DRenderer.bodyRect(box, pose: pose, size: size, center: center, pixelScale: 2))
        var touching = 0
        for y in rect.y..<(rect.y + rect.h) {
            for x in rect.x..<(rect.x + rect.w) where x == rect.x || y == rect.y || x == rect.x + rect.w - 1 || y == rect.y + rect.h - 1 {
                if bytes[(y * w + x) * 4 + 3] > 0 { touching += 1 }
            }
        }
        #expect(touching == 0, "\(pose): \(touching) edge pixels drawn")
    }

    /// For the compare with mock K.3D.8 (Designer 1): the device alone at 2x, 520 x 720 points
    /// like the mock's canvas, at the reference poses, Silver and Black.
    @Test(.enabled(if: Self.hasMetal, "no Metal device")) func theComparePictures() throws {
        let renderer = try #require(K3DRenderer.shared)
        let canvas = CGSize(width: 520, height: 720)
        for (pose, name) in [(K3DPose(), "0"), (K3DPose(angle: 30), "30"), (K3DPose(angle: 90), "90"), (K3DPose(angle: 180), "180"),
                             (K3DPose(angle: 305, tilt: 20), "305-tilt20")] {
            for black in [false, true] {
                var p = pose
                p.black = black
                let bytes = try #require(renderer.image(p, screen: nil, size: canvas, scale: 2))
                #expect(bytes.contains { $0 != 0 })
                save(bytes, canvas, "k3d-app-\(black ? "black" : "silver")-\(name)")
            }
        }
    }

    /// CLA-123, K.3D.10 design check (About thread): Silver and Black at back 180, 150 and 205,
    /// side 110 and front 35 and 55, and the 2D-3D handover at 0, 1, 2 and 3° with the live
    /// screen and the 2D layer, as the mock's canvas, 520 x 720 points at 2x.
    @Test(.enabled(if: Self.hasMetal, "no Metal device")) func theK3D10Pictures() throws {
        let renderer = try #require(K3DRenderer.shared)
        let canvas = CGSize(width: 520, height: 720)
        for black in [false, true] {
            var state = AppState()
            state.deviceColor = black ? .black : .silver
            let shot = try #require(K3DSpike.snapshot(state))
            for angle in [180.0, 150, 205, 110, 35, 55, 0, 1, 2, 3] {
                let bytes = try #require(renderer.image(K3DPose(angle: angle, black: black), screen: shot, size: canvas, scale: 2))
                #expect(bytes.contains { $0 != 0 })
                save(bytes, canvas, "k3d10-\(black ? "black" : "silver")-\(Int(angle))")
            }
        }
    }

    func save(_ bytes: [UInt8], _ size: CGSize, _ name: String) {
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
