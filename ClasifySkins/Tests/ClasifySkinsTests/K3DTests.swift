import ClasifyCore
import Foundation
import Metal
import Testing

@testable import ClasifySkins

/// SPIKE (CLA-101): the K.3D.1 port. The textures load with their bytes as stored, the mesh
/// matches the mock's `k3d_src.js`, and the shaders compile.
@Suite @MainActor struct K3DTests {
    func pixel(_ bytes: [UInt8], _ x: Int, _ y: Int) -> [UInt8] {
        let i = (y * K3DTextures.width + x) * 4
        return Array(bytes[i..<(i + 4)])
    }

    /// The front's alpha is a material id. One pixel of each id, with its exact color: a
    /// premultiplied or color-matched load would change them.
    @Test func theFrontKeepsItsMaterialIds() throws {
        let front = try #require(K3DTextures.rgba(.front))
        #expect(front.count == K3DTextures.width * K3DTextures.height * 4)
        #expect(pixel(front, 500, 865) == [246, 250, 251, 255])  // wheel
        #expect(pixel(front, 100, 1100) == [195, 199, 190, 253])  // bare aluminium
        #expect(pixel(front, 100, 100) == [203, 211, 220, 251])  // LCD
        #expect(pixel(front, 58, 300) == [42, 44, 46, 250])  // black bezel under the window
        #expect(pixel(front, 365, 865) == [192, 201, 199, 249])  // center button
    }

    @Test func theBackAndSteelLoad() throws {
        for name in [K3DTextures.Name.back, .steel] {
            let bytes = try #require(K3DTextures.rgba(name))
            #expect(bytes.count == K3DTextures.width * K3DTextures.height * 4, "\(name)")
        }
    }

    /// A live screen changes only the LCD's color. Every alpha id stays.
    @Test func aLiveScreenKeepsTheIds() throws {
        let plain = try #require(K3DTextures.rgba(.front))
        let shot = try #require(K3DSpike.snapshot(AppState()))
        let live = try #require(K3DTextures.front(screen: shot))
        #expect(stride(from: 3, to: plain.count, by: 4).allSatisfy { plain[$0] == live[$0] })
        #expect(pixel(live, 100, 1100) == pixel(plain, 100, 1100))  // the aluminium does not change
    }

    /// Counts and one vertex, checked against the mock's own code run in Node.
    @Test func theMeshMatchesTheMock() {
        let mesh = K3DMesh()
        #expect(mesh.vertexCount == 3102)
        #expect(mesh.indices.count == 17400)
        #expect(mesh.indices.allSatisfy { Int($0) < mesh.vertexCount })
        let v = Array(mesh.vertices[(1234 * K3DMesh.stride)..<(1235 * K3DMesh.stride)])
        let want: [Float] = [177.26997, -291.38939, 21.9, 0.83146961, -0.55557023, 0, 0, 0.93637847, 0.10655738, 1, 0.69134172, 2]
        for (got, expected) in zip(v, want) { #expect(abs(got - expected) < 0.0001, "\(v)") }
        #expect(Array(mesh.indices[16795..<16810]) == [2700, 2899, 2700, 2800, 2899, 2900, 2902, 2901, 2900, 2903, 2902, 2900, 2904, 2903, 2900])
    }

    /// The flip: 0.82 s to turn with a small overshoot, settled at 1.0 s, pushed back mid-turn.
    @Test func theFlipFollowsTheMock() {
        var flip = K3DFlip()
        let t0 = Date(timeIntervalSinceReferenceDate: 1000)
        #expect(flip.restsOnFront(at: t0))
        flip.toggle(at: t0, screen: nil)
        #expect(flip.toBack && !flip.restsOnFront(at: t0) && !flip.isResting(at: t0))
        let mid = flip.pose(at: t0.addingTimeInterval(0.41))
        #expect(abs(mid.angle - 92.25) < 0.01 && abs(mid.lift - 70) < 0.01)
        #expect(flip.pose(at: t0.addingTimeInterval(0.82)).angle > 180)  // the overshoot
        let end = flip.pose(at: t0.addingTimeInterval(1))
        #expect(end.angle == 180 && end.lift == 0 && flip.isResting(at: t0.addingTimeInterval(1)))  // the back rests
        flip.toggle(at: t0.addingTimeInterval(2), screen: nil)
        #expect(!flip.toBack && !flip.restsOnFront(at: t0.addingTimeInterval(2.5)))
        #expect(flip.restsOnFront(at: t0.addingTimeInterval(3)))
    }

    /// The shaders compile and link, where the machine has a Metal device.
    @Test func theShadersCompile() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        _ = try K3DRenderer.makePipeline(device)
        #expect(K3DRenderer.shared != nil)
    }
}
