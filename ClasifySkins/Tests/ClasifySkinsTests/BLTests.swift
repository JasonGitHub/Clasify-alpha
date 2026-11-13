import AppKit
import ClasifyCore
import SwiftUI
import Testing

@testable import ClasifySkins

/// SPIKE (CLA-101, K.3D spike 2): card BL's 2D look, drawn only with the hidden switch. The
/// expected colors come from `design-review/round17/bl/k7-spike1.json`. Points are in device
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
        // 91% down: #c3c3c3 to #bfbfbf is #c3, with the shade #be.
        let low = shot.mean(Self.x, 560)
        #expect(near(low, try reference(0xbebebe)), "low body \(low)")
        // The wheel at 27% down its 160° gradient: #f9fbfc.
        let wheel = shot.pixel(Self.x * 2, (Self.wheelTop + 60) * 2)
        #expect(near(wheel, try reference(0xf9fbfc)), "wheel \(wheel)")
        // The 0.5 point ring just above the wheel (y 320.5 to 321) is darker than the body above it.
        let ring = shot.pixel(Self.x * 2, Self.wheelTop * 2 - 1), above = shot.pixel(Self.x * 2, Self.wheelTop * 2 - 6)
        #expect(ring.g < above.g - 20, "ring \(ring), above \(above)")
        let center = shot.pixel(Self.x * 2, Self.centerY * 2)
        #expect(near(center, try reference(0xcdcdce)), "center \(center)")
    }

    /// Black: the dark gray tone, the flat #1e1e1e wheel and the flat #454545 center.
    @Test func blBlack() throws {
        let shot = try render(.black, "bl-black")
        // 47% down: #4f4f4f to #4c4c4c is #4c, with the side shade #4a. BH is #656467 here.
        let middle = shot.mean(Self.x, 290)
        #expect(near(middle, try reference(0x4a4a4a)), "body \(middle)")
        let wheel = shot.pixel(Self.x * 2, (Self.wheelTop + 60) * 2)
        #expect(near(wheel, try reference(0x1e1e1e)), "wheel \(wheel)")
        let center = shot.pixel(Self.x * 2, Self.centerY * 2)
        #expect(near(center, try reference(0x454545)), "center \(center)")
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
