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
}
