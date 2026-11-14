import ClasifyCore
import Foundation
import Metal
import SwiftUI
import Testing

@testable import ClasifySkins

/// SPIKE (CLA-101): the K.3D.7 port. The textures load with their bytes as stored, the mesh
/// matches the mock's `k3d_src3.js`, and the shaders compile.
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
        #expect(pixel(front, 500, 865) == [247, 250, 251, 255])  // wheel
        #expect(pixel(front, 100, 1100) == [195, 199, 190, 253])  // bare aluminium
        #expect(pixel(front, 100, 100) == [204, 210, 219, 251])  // LCD
        #expect(pixel(front, 58, 300) == [42, 44, 46, 250])  // bezel ink
        #expect(pixel(front, 365, 865) == [206, 207, 207, 249])  // center button
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

    /// Every LCD pixel (id 251) is in `K3DTextures.lcd`, the only rect a live screen looks at.
    @Test func theLCDIsInItsRect() throws {
        let plain = try #require(K3DTextures.rgba(.front))
        var count = 0
        for i in stride(from: 3, to: plain.count, by: 4) where plain[i] == 251 {
            let p = i / 4, x = p % K3DTextures.width, y = p / K3DTextures.width
            #expect(K3DTextures.lcd.x.contains(x) && K3DTextures.lcd.y.contains(y), "\(x), \(y)")
            count += 1
        }
        #expect(count == 600 * 450)
    }

    /// A turn to the back makes its screen picture first and starts its clock after: the
    /// snapshot's time does not come out of the turn (build 194 jumped at the turn's start).
    /// A turn to the front makes no picture.
    @Test func theTurnStartsAfterTheSnapshot() throws {
        var flip = K3DFlip()
        let shot = try #require(K3DSpike.snapshot(AppState()))
        var made = Date.distantFuture
        flip.turn {
            Thread.sleep(forTimeInterval: 0.05)
            made = .now
            return shot
        }
        #expect(flip.toBack)
        #expect(flip.start >= made)
        #expect(flip.screen === shot)
        var asked = false
        flip.turn { asked = true; return nil }
        #expect(!flip.toBack)
        #expect(!asked)
    }

    /// The shadow's shape follows the 3D body: straight on, it is the 2D body's own rounded
    /// rectangle (366 x 613 pt, 20 pt lower at the top for the shadow's copy). Edge-on it is as
    /// narrow as the body's depth; from the back as wide as the body, a little smaller.
    @Test func theShadowFollowsTheBody() {
        let front = K3DShadow.outline(angle: 0, lift: 0, drop: 0).boundingRect
        #expect(abs(front.minX) < 0.01 && abs(front.minY) < 0.01, "\(front)")
        #expect(abs(front.width - 366) < 0.01 && abs(front.height - 613) < 0.01, "\(front)")
        let copy = K3DShadow.outline(angle: 0, lift: 0, drop: PocketSkin.shadowDrop).boundingRect
        #expect(abs(copy.minY - 20) < 0.01 && abs(copy.maxY - 613) < 0.01, "\(copy)")
        let edge = K3DShadow.outline(angle: 90, lift: 70, drop: 0).boundingRect
        #expect(edge.width > 50 && edge.width < 80, "\(edge)")
        #expect(abs(edge.midX - 183) < 1, "\(edge)")
        let back = K3DShadow.outline(angle: 180, lift: 0, drop: 0).boundingRect
        #expect(back.width > 360 && back.width < 366, "\(back)")
        // The hull's corners are the 2D shape's: a point on the corner's curve is on the outline.
        let path = K3DShadow.outline(angle: 0, lift: 0, drop: 0)
        #expect(path.contains(CGPoint(x: 12, y: 12)) && !path.contains(CGPoint(x: 4, y: 4)))
    }

    /// The back shows the app's version in place of the art's "1.0 · Build 161". Only the spec
    /// table's value changes.
    @Test func theBackShowsTheRealVersion() throws {
        let art = try #require(K3DTextures.rgba(.back))
        let back = try #require(K3DTextures.back(version: "9.9 · Build 999"))
        #expect(back.count == art.count)
        var changed = 0
        for y in 0..<K3DTextures.height {
            for x in 0..<K3DTextures.width where pixel(back, x, y) != pixel(art, x, y) {
                #expect((330..<540).contains(x) && (936..<958).contains(y), "\(x), \(y)")
                changed += 1
            }
        }
        #expect(changed > 100)
    }

    /// Counts, two vertices and some indices, checked against the mock's own code run in Node,
    /// with the Take apart parts and the hidden screen module left out.
    @Test func theMeshMatchesTheMock() {
        let mesh = K3DMesh()
        #expect(mesh.vertexCount == 8542)
        #expect(mesh.indices.count == 47040)
        #expect(mesh.indices.allSatisfy { Int($0) < mesh.vertexCount })
        let want: [Int: [Float]] = [
            1234: [173.96415, -288.08357, 30.092016, 0.36168544, -0.24167049, 0.90043268, 0.97531189, 0.96995689, 0.97531189, 0.96995689, 1, 3, 1],
            6000: [-156.5, 241.42857, 34.054415, 1, 0, 0, 0.072404372, 0.10615241, 0.072404372, 0.10615241, 1, 0, 1],
        ]
        for (index, expected) in want {
            let v = Array(mesh.vertices[(index * K3DMesh.stride)..<((index + 1) * K3DMesh.stride)])
            for (got, value) in zip(v, expected) { #expect(abs(got - value) < 0.0001, "\(index): \(v)") }
        }
        #expect(Array(mesh.indices[40000..<40015]) == [7118, 7116, 7117, 7118, 7119, 7119, 7118, 7120, 7117, 7119, 7118, 7119, 7120, 7118, 7119])
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

    /// The flat 2D device and the 3D body crossfade in 0.1 s where a turn leaves or reaches the
    /// resting front, and nowhere else.
    @Test func theFlatDeviceCrossfades() {
        var flip = K3DFlip()
        let t0 = Date(timeIntervalSinceReferenceDate: 1000)
        #expect(flip.flatOpacity(at: t0) == 1)
        flip.toggle(at: t0, screen: nil)
        #expect(abs(flip.flatOpacity(at: t0.addingTimeInterval(0.05)) - 0.5) < 0.001)
        #expect(flip.flatOpacity(at: t0.addingTimeInterval(0.1)) < 0.001)
        #expect(flip.flatOpacity(at: t0.addingTimeInterval(5)) == 0)  // the back rests
        flip.toggle(at: t0.addingTimeInterval(5), screen: nil)
        #expect(flip.flatOpacity(at: t0.addingTimeInterval(5.89)) == 0)
        #expect(abs(flip.flatOpacity(at: t0.addingTimeInterval(5.95)) - 0.5) < 0.001)
        #expect(flip.flatOpacity(at: t0.addingTimeInterval(6)) > 0.999)
        // A turn to the back that starts mid-turn, not from the resting front, never shows 2D.
        flip.toggle(at: t0.addingTimeInterval(10), screen: nil)
        flip.toggle(at: t0.addingTimeInterval(10.4), screen: nil)
        flip.toggle(at: t0.addingTimeInterval(10.45), screen: nil)
        #expect(flip.flatOpacity(at: t0.addingTimeInterval(10.46)) == 0)
    }

    /// The shaders compile and link, where the machine has a Metal device.
    @Test func theShadersCompile() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        _ = try K3DRenderer.makePipeline(device)
        #expect(K3DRenderer.shared != nil)
    }
}
