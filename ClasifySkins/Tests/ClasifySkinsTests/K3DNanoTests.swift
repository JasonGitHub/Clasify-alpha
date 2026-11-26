import AppKit
import Foundation
import Metal
import Testing

@testable import ClasifySkins

/// CLA-196: the nano (N.3D.1) is a second body of the same 3D engine. Only these tests draw it.
@Suite @MainActor struct K3DNanoTests {
    nonisolated static var hasMetal: Bool { MTLCreateSystemDefaultDevice() != nil }

    /// The classic's shader is the source as it was, byte for byte; each number piece is in it.
    @Test func theClassicShaderIsTheSameAndEveryBodyNumberIsInIt() {
        #expect(K3DShader.shader(for: .classic) == K3DShader.source)
        for piece in K3DShader.numbers(.classic) { #expect(K3DShader.source.contains(piece), "\(piece)") }
        let nano = K3DShader.shader(for: .nano(.pink))
        #expect(!nano.contains("161.25") && !nano.contains("float2(0.0, -127.0)") && !nano.contains("732.0"))
        #expect(nano.contains("float2(0.0, 107.0)") && nano.contains("float3 uTint = float3(0.986, 0.516, 0.744)"))
    }

    /// Closed only: no Take apart parts. The body is 388 x 518 x 48.
    @Test func theNanoMeshIsTheClosedDeviceOnly() {
        let mesh = K3DMesh(body: .nano)
        #expect(mesh.closedVertexCount == mesh.vertexCount && mesh.closedIndexCount == mesh.indices.count)
        let box = K3DRenderer.box(mesh, apart: false)
        #expect(abs(Double(box.max.x - box.min.x) - 388) < 0.01 && abs(Double(box.max.y - box.min.y) - 518) < 0.01)
        #expect(abs(Double(box.max.z - box.min.z) - 48) < 0.01)
        #expect(K3DMesh(body: .classic).vertices == K3DMesh().vertices)
    }

    /// The textures are bundled at 776 x 1036 px, and every LCD pixel is in the body's LCD rect.
    @Test func theNanoTexturesAreBundled() throws {
        let body = K3DBody.nano, n = body.textureSize.x * body.textureSize.y * 4
        let front = try #require(K3DTextures.rgba(named: body.front)), back = try #require(K3DTextures.rgba(named: body.back))
        #expect(front.count == n && back.count == n)
        let outside = stride(from: 3, to: n, by: 4).filter { i in
            let p = i / 4, x = Double(p % body.textureSize.x), y = Double(p / body.textureSize.x)
            return front[i] == 251 && !(x >= body.lcd.x && x < body.lcd.y && y >= body.lcd.z && y < body.lcd.w)
        }
        #expect(outside.isEmpty)
        // Ids 250 and 251 only above `topPart` of the height (the shader's `hi`).
        let top = Int(body.topPart * Double(body.textureSize.y)) * body.textureSize.x * 4
        #expect(!front[top...].enumerated().contains { $0.offset % 4 == 3 && ($0.element == 250 || $0.element == 251) })
    }

    /// MATCH (README of n3d1-frozen): the reference poses (turn, tilt) on the reference canvas,
    /// 560 x 640 pt at 1 px per pt, with the mock's camera (1 pt per pt at the body's center).
    /// Every color draws; the PNGs are Silver at the 6 poses, Pink at [0, 0] and [30, 15], Blue at [0, 0].
    @Test(.enabled(if: Self.hasMetal, "no Metal device")) func theNanoPicturesForMatch() throws {
        let canvas = CGSize(width: 560, height: 640), scale = 2600 / (2600 - K3DMesh.depth / 2)  // see `K3DRenderer.projection`
        let saved: [K3DBody.NanoColor: [(Double, Double)]] = [
            .silver: [(0, 0), (30, 15), (180, 0), (90, 0), (330, -15), (150, 20)], .pink: [(0, 0), (30, 15)], .blue: [(0, 0)],
        ]
        for color in K3DBody.NanoColor.allCases {
            let renderer = try #require(K3DRenderer(body: .nano(color)))
            for (turn, tilt) in saved[color] ?? [(0, 0)] {
                let pose = K3DPose(angle: turn, tilt: tilt, black: color == .black, scale: scale)
                let bytes = try #require(renderer.image(pose, screen: nil, size: canvas, scale: 1))
                #expect(bytes.contains { $0 != 0 }, "\(color)")
                if saved[color] != nil { save(bytes, canvas, "n3d1-\(color)-\(Int(turn))-\(Int(tilt))") }
            }
        }
    }

    func save(_ bytes: [UInt8], _ size: CGSize, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else { return }
        let w = Int(size.width), h = Int(size.height)
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
