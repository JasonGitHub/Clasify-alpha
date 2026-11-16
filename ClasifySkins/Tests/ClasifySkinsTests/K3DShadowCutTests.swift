import Foundation
import Metal
import SwiftUI
import Testing

@testable import ClasifySkins

/// CLA-119 (build 269: pale strips beside the body edge-on in a color spin): at a still pose the
/// shadow's cut is the drawn body's outline, within 2 pt, also near 90°. The strips came from the
/// Metal frame showing a frame after `K3DShadow` (`presentsWithTransaction` now joins them).
@Suite @MainActor struct K3DShadowCutTests {
    nonisolated static var hasMetal: Bool { MTLCreateSystemDefaultDevice() != nil }

    @Test(.enabled(if: Self.hasMetal, "no Metal device"), arguments: [80.0, 85, 90, 95, 100])
    func theCutIsTheBodyEdgeOn(_ angle: Double) throws {
        let renderer = try #require(K3DRenderer.shared)
        let size = PocketSkin.size
        for lift in [0.0, K3DFlip.lift] {
            let bytes = try #require(renderer.image(K3DPose(angle: angle, lift: lift), screen: nil, size: size, scale: 1))
            let w = Int(size.width), h = Int(size.height)
            var x0 = w, x1 = -1
            for y in stride(from: 0, to: h, by: 2) {
                for x in 0..<w where bytes[(y * w + x) * 4 + 3] > 64 {
                    x0 = min(x0, x)
                    x1 = max(x1, x)
                }
            }
            let cut = K3DShadow.cut(angle: angle, lift: lift).boundingRect
            #expect(abs(cut.minX - CGFloat(x0)) <= 2 && abs(cut.maxX - CGFloat(x1 + 1)) <= 2,
                    "angle \(angle), lift \(lift): body \(x0)...\(x1 + 1), cut \(cut.minX)...\(cut.maxX)")
        }
    }

    /// The body's horizontal extent in points, at a pose, at 1x: pixels with alpha over `alpha`.
    func extent(_ renderer: K3DRenderer, angle: Double, lift: Double, tilt: Double, alpha: UInt8 = 64) throws -> (CGFloat, CGFloat) {
        let size = PocketSkin.size
        let bytes = try #require(renderer.image(K3DPose(angle: angle, lift: lift, tilt: tilt), screen: nil, size: size, scale: 1))
        let w = Int(size.width), h = Int(size.height)
        var x0 = w, x1 = -1
        for y in stride(from: 0, to: h, by: 2) {
            for x in 0..<w where bytes[(y * w + x) * 4 + 3] > alpha {
                x0 = min(x0, x)
                x1 = max(x1, x)
            }
        }
        return (CGFloat(x0), CGFloat(x1 + 1))
    }

    /// CLA-119 (build 275, 60 fps: the gap stayed while the body widens): in a color spin, at
    /// every frame, the cut lies inside the body of this frame AND of the frame before, within
    /// 2 pt. So a body that shows up to a frame late still covers the cut's edge.
    @Test(.enabled(if: Self.hasMetal, "no Metal device"), arguments: [K3DFlip.spinPick, K3DFlip.spinSettings])
    func theCutStaysInsideALateBody(_ turn: Double) throws {
        let renderer = try #require(K3DRenderer.shared)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let flip = K3DFlip.spin(turn: turn, fromBlack: false, at: start, screen: { nil })
        var bodies: [Int: (CGFloat, CGFloat)] = [:]
        func body(_ frame: Int) throws -> (CGFloat, CGFloat) {
            if let known = bodies[frame] { return known }
            let then = start.addingTimeInterval(Double(frame) / 60)
            let pose = flip.pose(at: then)
            // Any coverage: the desktop shows only where the body does not cover a pixel at all.
            let found = try extent(renderer, angle: pose.angle, lift: pose.lift, tilt: flip.tilt(at: then), alpha: 0)
            bodies[frame] = found
            return found
        }
        for frame in 1...Int(flip.length * 60) {
            let now = start.addingTimeInterval(Double(frame) / 60)
            let pose = flip.pose(at: now)
            let cut = K3DShadow.cut(angle: pose.angle, lift: pose.lift, tilt: flip.tilt(at: now), trail: K3DShadow.trail(flip, at: now))
            let box = cut.boundingRect
            for shown in [frame, frame - 1] {
                let (x0, x1) = try body(shown)
                #expect(box.minX >= x0 - 2 && box.maxX <= x1 + 2,
                        "turn \(turn), frame \(frame), body of frame \(shown) \(x0)...\(x1), cut \(box.minX)...\(box.maxX)")
            }
        }
    }

    /// At rest, and in a drag that holds still, the cut is exactly the pose's own, as before.
    @Test func theCutAtRestIsUnchanged() {
        let rest = K3DFlip()
        let restTrail = K3DShadow.trail(rest, at: .distantFuture)
        let restPose = rest.pose(at: .distantFuture)
        #expect(K3DShadow.cut(angle: restPose.angle, lift: restPose.lift, trail: restTrail) == K3DShadow.cut(angle: restPose.angle, lift: restPose.lift))
        let held = rest.held(angle: 40, tilt: 3)
        let now = Date.now
        let pose = held.pose(at: now)
        #expect(pose.angle == 40)
        #expect(K3DShadow.cut(angle: pose.angle, lift: pose.lift, tilt: held.tilt(at: now), trail: K3DShadow.trail(held, at: now))
                == K3DShadow.cut(angle: 40, lift: pose.lift, tilt: 3))
    }
}
