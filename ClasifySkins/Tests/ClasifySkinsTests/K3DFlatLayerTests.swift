import AppKit
import ClasifyCore
import Foundation
import Metal
import Testing

@testable import ClasifySkins

/// CLA-119: the 3D front has the mock's 2D layer (k3d_src3.js `t2`): the 2D device's picture plus
/// only the change of the 3D light from rest. So at 0° the 3D front is the 2D device.
@Suite @MainActor struct K3DFlatLayerTests {
    nonisolated static var hasMetal: Bool { MTLCreateSystemDefaultDevice() != nil }

    /// At 0°, at 2x, every pixel 3 pt or more inside the device's outline is the 2D picture's
    /// pixel within 1/255, in both colors. Within 3 pt of the edge the plate's round takes the 3D
    /// light only, as in the mock. PNGs: the 2D picture, the 3D frame, and their difference x16.
    @Test(.enabled(if: Self.hasMetal, "no Metal device"), arguments: [DeviceColor.silver, .black])
    func theFrontAt0IsThe2DDevice(_ color: DeviceColor) throws {
        let renderer = try #require(K3DRenderer.shared)
        var state = AppState()
        state.deviceColor = color
        let name = color == .black ? "black" : "silver"
        let shot = try #require(K3DSpike.snapshot(state))
        let flat = try #require(K3DTextures.picture(shot))  // RGBA
        #expect(K3DTextures.isBlack(flat) == (color == .black))
        let size = PocketSkin.size, w = Int(size.width) * 2, h = Int(size.height) * 2
        let body = try #require(renderer.image(K3DPose(black: color == .black), screen: shot, size: size, scale: 2))  // BGRA
        #expect(flat.count == w * h * 4 && body.count == w * h * 4)
        // Signed distance from the outline (366 x 613, radius 34), in points; < 0 inside.
        func distance(_ x: Double, _ y: Double) -> Double {
            let qx = abs(x - size.width / 2) - (size.width / 2 - 34), qy = abs(y - size.height / 2) - (size.height / 2 - 34)
            return hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - 34
        }
        var flatBGRA = [UInt8](repeating: 0, count: w * h * 4), diff = [UInt8](repeating: 255, count: w * h * 4)
        var worst = 0, off = 0, first: [(Int, Int, Int)] = []
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                for c in 0..<4 { flatBGRA[i + c] = flat[i + [2, 1, 0, 3][c]] }
                let d = (0..<3).map { abs(Int(flatBGRA[i + $0]) - Int(body[i + $0])) }
                for c in 0..<3 { diff[i + c] = UInt8(min(255, d[c] * 16)) }
                guard distance((Double(x) + 0.5) / 2, (Double(y) + 0.5) / 2) <= -3 else { continue }
                let m = d.max() ?? 0
                worst = max(worst, m)
                if m > 1 {
                    off += 1
                    if first.count < 5 { first.append((x, y, m)) }
                }
            }
        }
        save(flatBGRA, w, h, "k3d-layer-\(name)-2d", alpha: true)
        save(body, w, h, "k3d-layer-\(name)-3d", alpha: true)
        save(diff, w, h, "k3d-layer-\(name)-diff", alpha: false)
        #expect(off == 0, "\(name): \(off) pixels differ by more than 1, worst \(worst), first (x, y, d) \(first)")
    }

    /// The 2D layer shows only in the picture's own color: in the first half of a color spin the
    /// 3D body is the old color, and the front is 3D only there (as before CLA-119).
    @Test(.enabled(if: Self.hasMetal, "no Metal device")) func theLayerNeedsThePicturesColor() throws {
        let renderer = try #require(K3DRenderer.shared)
        let shot = try #require(K3DSpike.snapshot(AppState()))  // Silver
        let size = PocketSkin.size
        let plain = try #require(renderer.image(K3DPose(black: true), screen: nil, size: size, scale: 2))
        let other = try #require(renderer.image(K3DPose(black: true), screen: shot, size: size, scale: 2))
        // Outside the LCD the two are the same: only the screen picture changed.
        let w = Int(size.width) * 2
        for (x, y) in [(366, 700), (100, 1100), (366, 867)] {
            let i = (y * w + x) * 4
            #expect(Array(plain[i..<(i + 4)]) == Array(other[i..<(i + 4)]), "at \(x), \(y)")
        }
    }

    /// The picture is the face as it is at the swap: the wheel key under the pointer is drawn so.
    @Test func thePictureShowsTheWheelKeyUnderThePointer() throws {
        let look = WheelLook()
        let plain = try #require(K3DSpike.snapshot(AppState(), wheel: look).flatMap(K3DTextures.picture))
        look.hovered = .menu
        let hovered = try #require(K3DSpike.snapshot(AppState(), wheel: look).flatMap(K3DTextures.picture))
        // MENU: the wheel's top key, about 40 pt below the wheel's top (y 321 pt), centered.
        var changed = 0
        for y in 660..<700 {
            for x in 320..<412 {
                let i = (y * 732 + x) * 4
                if plain[i..<(i + 3)] != hovered[i..<(i + 3)] { changed += 1 }
            }
        }
        #expect(changed > 20, "\(changed) MENU pixels changed")
    }

    /// CLA-119: a color spin's picture shows the centre button let go (the press that started
    /// the spin lets go a moment later), and keeps the key under the pointer.
    @Test func theReleasedLookHasNoPressedKey() {
        let live = WheelLook.live
        let (hovered, pressed) = (live.hovered, live.pressed)
        defer { (live.hovered, live.pressed) = (hovered, pressed) }
        (live.hovered, live.pressed) = (.center, .center)
        let look = WheelLook.released
        #expect(look.pressed == nil && look.hovered == .center && look !== live)
    }

    func save(_ bytes: [UInt8], _ w: Int, _ h: Int, _ name: String, alpha: Bool) {
        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else { return }
        var copy = bytes
        let info = (alpha ? CGImageAlphaInfo.premultipliedFirst : .noneSkipFirst).rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let image = copy.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info)?.makeImage()
        }
        guard let image, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("pocket-\(name).png"))
    }
}
