import AppKit
import ClasifyCore
import SwiftUI
import Testing

@testable import ClasifySkins

/// SPIKE (CLA-101, K.3D spike 2): card BL's 2D look, drawn only with the hidden switch. The
/// expected colors come from `design-review/round17/bl/v3/k8.json`, BL v3 (Silver as in v2). Points are in device
/// points, read at 2x.
@Suite @MainActor struct BLTests {
    struct Shot {
        let bitmap: NSBitmapImageRep

        /// A pixel of the 2x bitmap.
        func pixel(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
            let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) ?? .clear
            return (Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
        }

        /// The mean of 9 x 9 points around a point, so the grain averages out.
        func mean(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
            var sum = (r: 0, g: 0, b: 0)
            for dy in -4...4 {
                for dx in -4...4 {
                    let c = pixel((x + dx) * 2, (y + dy) * 2)
                    sum.r += c.r; sum.g += c.g; sum.b += c.b
                }
            }
            return (sum.r / 81, sum.g / 81, sum.b / 81)
        }
    }

    func render(_ color: DeviceColor, _ name: String, look: PocketLook = .bl) throws -> Shot {
        var state = AppState()
        state.deviceColor = color
        let renderer = ImageRenderer(content: PocketSkin(state: state, interactive: false).environment(\.pocketLook, look))
        renderer.scale = 2
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        if let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("pocket-\(name).png"))
        }
        return Shot(bitmap: bitmap)
    }

    /// One flat color drawn and read back the same way.
    func reference(_ hex: UInt32) throws -> (r: Int, g: Int, b: Int) {
        let renderer = ImageRenderer(content: Color(hex: hex).frame(width: 10, height: 10))
        renderer.scale = 2
        return Shot(bitmap: NSBitmapImageRep(cgImage: try #require(renderer.cgImage))).pixel(10, 10)
    }

    func near(_ a: (r: Int, g: Int, b: Int), _ b: (r: Int, g: Int, b: Int)) -> Bool {
        abs(a.r - b.r) < 12 && abs(a.g - b.g) < 12 && abs(a.b - b.b) < 12
    }

    static let x = 183, wheelTop = 321, centerY = 433

    /// Silver: the light tone with its side shade, the light wheel with its thin ring, and the
    /// flat light center.
    @Test func blSilver() throws {
        let shot = try render(.silver, "bl-silver")
        // Between the screen and the wheel (47% down): #e8e8e8 to #e0e0e0 is #e1, with the 2.5%
        // side shade #db.
        let middle = shot.mean(Self.x, 290)
        #expect(near(middle, try reference(0xdbdbdb)), "body \(middle)")
        // 91% down: #c4c4c4 to #c2c2c2 (v2) is #c4, with the shade #bf.
        let low = shot.mean(Self.x, 560)
        #expect(near(low, try reference(0xbfbfbf)), "low body \(low)")
        // The wheel at 27% down its 160° gradient: #f9fbfc.
        let wheel = shot.pixel(Self.x * 2, (Self.wheelTop + 60) * 2)
        #expect(near(wheel, try reference(0xf9fbfc)), "wheel \(wheel)")
        // The 0.5 point ring just above the wheel (y 320.5 to 321, black 15%) is darker than the
        // body above it, and the 1 point inner ring (black 10%) darker than the wheel below it.
        let ring = shot.pixel(Self.x * 2, Self.wheelTop * 2 - 1), above = shot.pixel(Self.x * 2, Self.wheelTop * 2 - 6)
        #expect(ring.g < above.g - 20, "ring \(ring), above \(above)")
        let inner = shot.pixel(Self.x * 2, Self.wheelTop * 2 + 1), below = shot.pixel(Self.x * 2, Self.wheelTop * 2 + 8)
        #expect(inner.g < below.g - 12, "inner ring \(inner), below \(below)")
        let center = shot.pixel(Self.x * 2, Self.centerY * 2)
        #expect(near(center, try reference(0xcdcdce)), "center \(center)")
    }

    /// Black (v3): the charcoal tone, the #202123 wheel and the shaded center.
    @Test func blBlack() throws {
        let shot = try render(.black, "bl-black")
        // 47% down: #5c5d61 (40%) to #55565a (49%) is #565759, with the 2.5% side shade
        // #545559. BH is #656467 here.
        let middle = shot.mean(Self.x, 290)
        #expect(near(middle, try reference(0x545559)), "body \(middle)")
        // 52.5 pt from the wheel's center (47% of its radius), between the hole and rim shades.
        let wheel = shot.pixel(Self.x * 2, (Self.wheelTop + 60) * 2)
        #expect(near(wheel, try reference(0x202123)), "wheel \(wheel)")
        // The center's middle: #393a3c at 50%, inside the edge shade.
        let center = shot.pixel(Self.x * 2, Self.centerY * 2)
        #expect(near(center, try reference(0x393a3c)), "center \(center)")
        // BL's bezel is #2a2c2e on Black too, not BH's near black #050505.
        let bezel = shot.pixel(30 * 2, 120 * 2)
        #expect(near(bezel, try reference(0x2a2c2e)), "bezel \(bezel)")
    }

    /// With no switch the look stays BH: the black body is still #656467 there.
    @Test func bhStaysTheDefault() throws {
        var state = AppState()
        state.deviceColor = .black
        let renderer = ImageRenderer(content: PocketSkin(state: state, interactive: false))
        renderer.scale = 2
        let shot = Shot(bitmap: NSBitmapImageRep(cgImage: try #require(renderer.cgImage)))
        let middle = shot.mean(Self.x, 290)
        #expect(near(middle, try reference(0x656467)), "body \(middle)")
    }
}
