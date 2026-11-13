import AppKit
import ClasifyCore
import SwiftUI
import Testing

@testable import ClasifySkins

/// SPIKE (CLA-101, K.3D spike 2): at the end of a turn to the front, the K.3D.7 body at rest
/// crossfades to card BL's 2D device in 0.1 s. The two must look the same there, or the fade
/// shows a jump. Points are in device points, read at 2x.
///
/// The limit is 10 of 255 per channel, on 9 x 9 point means (the grain averages out). Card BL
/// was made to match K.3D.7 straight on: on the mock's own render
/// (`k3d7-spike/reference/exact_*_0_0.png`) BL's values are within 3 at these points. The other
/// 7 are for Metal against WebGL: the mock's camera draws the face 1.3% larger, and the
/// mipmaps filter a little differently.
///
/// The test is skipped where the machine has no Metal device.
@Suite @MainActor struct K3DRestTests {
    static let limit = 10

    struct Pixels {
        let width: Int
        let read: (Int, Int) -> (r: Int, g: Int, b: Int)

        /// The mean of 9 x 9 points around a point.
        func mean(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
            var sum = (r: 0, g: 0, b: 0)
            for dy in -4...4 {
                for dx in -4...4 {
                    let c = read((x + dx) * 2, (y + dy) * 2)
                    sum.r += c.r; sum.g += c.g; sum.b += c.b
                }
            }
            return (sum.r / 81, sum.g / 81, sum.b / 81)
        }

        /// The first row, in pixels from the top, between `rows` where a pixel in `columns` is
        /// darker than `green`: the top of the MENU label.
        func firstDark(rows: Range<Int>, columns: Range<Int>, green: Int) -> Int? {
            rows.first { y in columns.contains { read($0, y).g < green } }
        }
    }

    func flat(_ state: AppState, _ name: String) throws -> Pixels {
        let renderer = ImageRenderer(content: PocketSkin(state: state, interactive: false).environment(\.pocketLook, .bl))
        renderer.scale = 2
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        save(bitmap, name)
        return Pixels(width: bitmap.pixelsWide) { x, y in
            let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) ?? .clear
            return (Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
        }
    }

    func rest(_ renderer: K3DRenderer, _ state: AppState, _ name: String) throws -> Pixels {
        let size = PocketSkin.size, w = Int(size.width) * 2, h = Int(size.height) * 2
        var bytes = try #require(renderer.image(
            K3DPose(black: state.deviceColor == .black), screen: K3DSpike.snapshot(state), size: size, scale: 2))
        #expect(bytes.count == w * h * 4)
        // Premultiplied BGRA, rows from the top. Inside the body the alpha is 255.
        let image = bytes.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)?.makeImage()
        }
        if let image { save(NSBitmapImageRep(cgImage: image), name) }
        let copy = bytes
        return Pixels(width: w) { x, y in
            let i = (y * w + x) * 4
            return (Int(copy[i + 2]), Int(copy[i + 1]), Int(copy[i]))
        }
    }

    func save(_ bitmap: NSBitmapImageRep, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"],
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("pocket-\(name).png"))
    }

    func near(_ a: (r: Int, g: Int, b: Int), _ b: (r: Int, g: Int, b: Int)) -> Bool {
        abs(a.r - b.r) <= Self.limit && abs(a.g - b.g) <= Self.limit && abs(a.b - b.b) <= Self.limit
    }

    @Test(arguments: [DeviceColor.silver, .black]) func theRestFrameMatchesBL(_ color: DeviceColor) throws {
        guard let renderer = K3DRenderer.shared else { return }
        var state = AppState()
        state.deviceColor = color
        let name = color == .black ? "black" : "silver"
        let flat = try flat(state, "bl-\(name)-2d")
        let rest = try rest(renderer, state, "k3d7-rest-\(name)")
        // The body between the screen and the wheel and low down, the wheel, the center button.
        for (x, y) in [(183, 290), (183, 560), (183, 381), (183, 433), (60, 450), (306, 450)] {
            let a = flat.mean(x, y), b = rest.mean(x, y)
            #expect(near(a, b), "\(name) at \(x), \(y): 2D \(a), 3D \(b)")
        }
        // The bezel, one pixel: ink #2a2c2e on both.
        let a = flat.read(60, 240), b = rest.read(60, 240)
        #expect(near(a, b), "\(name) bezel: 2D \(a), 3D \(b)")
    }

    /// The 3D texture's MENU label is where the app draws it: its top within 1 pt.
    @Test func menuIsWhereTheAppDrawsIt() throws {
        guard let renderer = K3DRenderer.shared else { return }
        let state = AppState()
        let flat = try flat(state, "bl-silver-2d")
        let rest = try rest(renderer, state, "k3d7-rest-silver")
        // The wheel's top is 321 pt down. MENU is 45 pt wide around x 183.
        let rows = (321 + 4) * 2..<(321 + 34) * 2, columns = 160 * 2..<206 * 2
        let a = try #require(flat.firstDark(rows: rows, columns: columns, green: 200))
        let b = try #require(rest.firstDark(rows: rows, columns: columns, green: 200))
        #expect(abs(a - b) <= 2, "MENU top: 2D \(Double(a) / 2) pt, 3D \(Double(b) / 2) pt")
    }
}
