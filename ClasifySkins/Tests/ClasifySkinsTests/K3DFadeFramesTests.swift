import AppKit
import ClasifyCore
import Foundation
import Metal
import SwiftUI
import Testing

@testable import ClasifySkins

/// CLA-119 PR 2b: the 2D device and the 3D body hand over by angle, within 2° of the front.
@Suite @MainActor struct K3DFadeFramesTests {
    nonisolated static var hasMetal: Bool { MTLCreateSystemDefaultDevice() != nil }

    /// Frames for the design check, at 0, 0.5, 1, 1.5, 2 and 3°, Silver and Black, at 2x on
    /// purple (#9b5fd0, as Jason's desktop), composed as `K3DFlipView` shows them: the 3D body
    /// with the 2D device over it at the fade's opacity, and one shadow (the 2D device's own at
    /// rest, else `K3DShadow`). PNGs: `pocket-k3d-fade-<color>-<angle>.png`.
    @Test(.enabled(if: Self.hasMetal, "no Metal device"), arguments: [DeviceColor.silver, .black])
    func theFramesNearTheFront(_ color: DeviceColor) throws {
        let renderer = try #require(K3DRenderer.shared)
        var state = AppState()
        state.deviceColor = color
        let black = color == .black
        let shot = try #require(K3DSpike.snapshot(state))
        let expected: [Double: Double] = [0: 1, 0.5: 0.84375, 1: 0.5, 1.5: 0.15625, 2: 0, 3: 0]
        for angle in [0, 0.5, 1, 1.5, 2, 3] {
            let shown = K3DFlip.nearRest(angle: angle, tilt: 0)
            #expect(abs(shown - (expected[angle] ?? -1)) < 1e-9, "at \(angle)°")
            let png = try frame(renderer, state, shot, angle: angle, lift: 0, shown: shown)
            #expect(png.count > 0)
            let name = "\(black ? "black" : "silver")-\(String(format: "%.1f", angle))"
            if let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] {
                try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("pocket-k3d-fade-\(name).png"))
            }
        }
    }

    /// Frames from the real flip off the front, at the times where the 2D device shows at 1,
    /// 0.75, 0.5, 0.25 and 0, with the flip's own pose (its push back included), Silver and
    /// Black, on #9b5fd0. PNGs: `pocket-k3d-flip-<color>-<opacity>.png`.
    @Test(.enabled(if: Self.hasMetal, "no Metal device"), arguments: [DeviceColor.silver, .black])
    func theFlipFramesOffTheFront(_ color: DeviceColor) throws {
        let renderer = try #require(K3DRenderer.shared)
        var state = AppState()
        state.deviceColor = color
        let black = color == .black
        let shot = try #require(K3DSpike.snapshot(state))
        let t0 = Date(timeIntervalSinceReferenceDate: 1000)
        var flip = K3DFlip()
        flip.toggle(at: t0, screen: shot)
        for target in [1, 0.75, 0.5, 0.25, 0] {
            // The fade falls as the turn starts: find its time by halving.
            var (lo, hi) = (0.0, 0.3)
            for _ in 0..<50 {
                let mid = (lo + hi) / 2
                if flip.flatOpacity(at: t0.addingTimeInterval(mid)) > target { lo = mid } else { hi = mid }
            }
            let time = t0.addingTimeInterval(target == 1 ? 0 : hi)
            let pose = flip.pose(at: time), shown = flip.flatOpacity(at: time)
            #expect(abs(shown - target) < 0.01, "at \(target)")
            if shown > 0 { #expect(pose.lift == 0, "the 3D body is the 2D device's size while it shows") }
            let png = try frame(renderer, state, shot, angle: pose.angle, lift: pose.lift, shown: shown)
            let name = "\(black ? "black" : "silver")-\(String(format: "%.2f", target))"
            if let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] {
                try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("pocket-k3d-flip-\(name).png"))
            }
        }
    }

    /// One frame as `K3DFlipView` composes it, at 2x, 60 pt of purple round the device.
    func frame(_ renderer: K3DRenderer, _ state: AppState, _ shot: CGImage, angle: Double, lift: Double, shown: Double) throws -> Data {
        let black = state.deviceColor == .black
        let size = PocketSkin.size, m: CGFloat = 60
        let room = CGSize(width: size.width + 2 * m, height: size.height + 2 * m)
        let pose = K3DPose(angle: angle, lift: lift, black: black)
        let bytes = try #require(renderer.image(pose, screen: shot, size: room, scale: 2))
        let body = try #require(Self.image(bytes, Int(room.width) * 2, Int(room.height) * 2))
        let view = ZStack {
            Color(hex: 0x9b5fd0)
            if shown < 1 { K3DShadow(angle: angle, lift: lift, black: black) }
            Image(decorative: body, scale: 2)
            PocketSkin(state: state, interactive: false)
                .environment(\.pocketDropShadow, shown >= 1)
                .compositingGroup()
                .opacity(shown)
        }
        .frame(width: room.width, height: room.height)
        let image = ImageRenderer(content: view)
        image.scale = 2
        return try #require(image.cgImage.flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) })
    }

    /// A color spin starts from the 2D device in the old color: the 3D body, still the old
    /// color, shows the old color's picture (`oldScreen`), not the new one's.
    @Test(.enabled(if: Self.hasMetal, "no Metal device")) func theSpinStartsFromTheOldColorsPicture() throws {
        let renderer = try #require(K3DRenderer.shared)
        var state = AppState()
        state.deviceColor = .black
        let newShot = try #require(K3DSpike.snapshot(state))  // the spin to Black
        let oldShot = try #require(K3DSpike.snapshot(state, black: false))  // Silver, as the 2D device to 180°
        let size = PocketSkin.size, w = Int(size.width) * 2
        let spin = try #require(renderer.image(K3DPose(black: false), screen: newShot, old: oldShot, size: size, scale: 2))
        let flat = try #require(renderer.image(K3DPose(black: false), screen: oldShot, size: size, scale: 2))
        let none = try #require(renderer.image(K3DPose(black: false), screen: newShot, size: size, scale: 2))
        var worst = 0, apart = 0
        for y in stride(from: 100, to: 1126, by: 7) {
            for x in stride(from: 40, to: 692, by: 7) {
                let i = (y * w + x) * 4
                for c in 0..<3 {
                    worst = max(worst, abs(Int(spin[i + c]) - Int(flat[i + c])))
                    apart = max(apart, abs(Int(none[i + c]) - Int(flat[i + c])))
                }
            }
        }
        #expect(worst <= 1, "the spin's first frame differs from the old color's 2D layer by \(worst)")
        #expect(apart > 8, "without the old picture the front is 3D only: \(apart)")
    }

    /// The 2D layer fades out over the start of the take-apart, from `ex` 0 to 0.05.
    @Test func theLayerFadesAsThePartsMove() {
        #expect(K3DRenderer.exFade == 0.05)
        #expect(K3DRenderer.smooth(0) == 0 && K3DRenderer.smooth(0.5) == 0.5 && K3DRenderer.smooth(1) == 1)
    }

    static func image(_ bytes: [UInt8], _ w: Int, _ h: Int) -> CGImage? {
        var copy = bytes
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        return copy.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info)?.makeImage()
        }
    }
}
