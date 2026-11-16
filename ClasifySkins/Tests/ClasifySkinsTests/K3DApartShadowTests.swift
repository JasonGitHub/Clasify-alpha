import SwiftUI
import Testing

@testable import ClasifySkins

/// CLA-105 (Jason's take-apart picture, 17:45 JST 11-16): the closed body's shadow fades out
/// as the device opens, and back in as it closes. Closed, it is exactly today's shadow.
@MainActor struct K3DApartShadowTests {
    func bytes<V: View>(_ view: V) throws -> [UInt8] {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        return try #require(K3DTextures.picture(image))
    }

    let ground = Color(.sRGB, red: 0.9, green: 0.9, blue: 0.9)
    let margin = EdgeInsets(top: 5, leading: 60, bottom: 90, trailing: 60)

    @Test func theFadeRunsFromClosedToOpen() {
        #expect(K3DShadow.fade(ex: 0) == 1)
        #expect(K3DShadow.fade(ex: 0.15) == 0)
        #expect(K3DShadow.fade(ex: 0.5) == 0)
        #expect(K3DShadow.fade(ex: 1) == 0)
        var last = 1.0
        for ex in stride(from: 0.0, through: 0.2, by: 0.01) {
            let f = K3DShadow.fade(ex: ex)
            #expect(f <= last, "ex \(ex)")
            last = f
        }
    }

    /// Closed (ex 0), the shadow is today's, pixel for pixel, at rest and turned.
    @Test(arguments: [(0.0, false), (0.0, true), (90.0, false), (150.0, true)])
    func theClosedShadowIsUnchanged(_ pose: (angle: Double, black: Bool)) throws {
        let today = try bytes(K3DShadow(angle: pose.angle, lift: 0, black: pose.black).padding(margin).background(ground))
        let now = try bytes(
            K3DShadow(angle: pose.angle, lift: 0, black: pose.black).opacity(K3DShadow.fade(ex: 0)).padding(margin).background(ground))
        #expect(today == now)
    }

    /// Open (ex from 0.15 to 1), at any turn or tilt a drag gives, no shadow shows: only the ground.
    @Test(arguments: [0.15, 0.5, 1.0])
    func theOpenDeviceHasNoShadow(_ ex: Double) throws {
        let bare = try bytes(Color.clear.frame(width: PocketSkin.size.width, height: PocketSkin.size.height).padding(margin).background(ground))
        for (angle, tilt) in [(305.0, 20.0), (40.0, -35.0), (180.0, 0.0)] {
            let fade = K3DShadow.fade(ex: ex)
            let open = try bytes(
                ZStack { if fade > 0 { K3DShadow(angle: angle, lift: 0, tilt: tilt, black: true).opacity(fade) } }
                    .frame(width: PocketSkin.size.width, height: PocketSkin.size.height).padding(margin).background(ground))
            #expect(open == bare, "ex \(ex), angle \(angle), tilt \(tilt)")
        }
    }
}
