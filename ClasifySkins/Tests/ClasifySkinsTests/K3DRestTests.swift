import AppKit
import ClasifyCore
import Metal
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
/// Both pictures are read the same way: the 3D frame is shown as a SwiftUI image and drawn
/// with the same `ImageRenderer` as the 2D device. A first run read the 2D through
/// `ImageRenderer` and the 3D as raw bytes, and every 2D value came out lighter (#2a2c2e read
/// as #373a3c), while the 3D matched the mock's render within 1.
///
/// The tests show as skipped where the machine has no Metal device. Where it has one, a
/// renderer that fails to load fails the test.
@Suite @MainActor struct K3DRestTests {
    static let limit = 10
    nonisolated static var hasMetal: Bool { MTLCreateSystemDefaultDevice() != nil }

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

    /// The view drawn at 2x by `ImageRenderer`, read as sRGB.
    func pixels<V: View>(_ view: V, _ name: String) throws -> Pixels {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        save(bitmap, name)
        return Pixels(width: bitmap.pixelsWide) { x, y in
            let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) ?? .clear
            return (Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
        }
    }

    func flat(_ state: AppState, _ name: String) throws -> Pixels {
        try pixels(PocketSkin(state: state, interactive: false).environment(\.pocketLook, .bl), name)
    }

    func rest(_ renderer: K3DRenderer, _ state: AppState, _ name: String) throws -> Pixels {
        try pixels(restImage(renderer, state), name)
    }

    /// The 3D rest frame as a SwiftUI image the size of the device.
    func restImage(_ renderer: K3DRenderer, _ state: AppState) throws -> some View {
        let size = PocketSkin.size, w = Int(size.width) * 2, h = Int(size.height) * 2
        var bytes = try #require(renderer.image(
            K3DPose(black: state.deviceColor == .black), screen: K3DSpike.snapshot(state), size: size, scale: 2))
        #expect(bytes.count == w * h * 4)
        // Premultiplied BGRA, rows from the top, in sRGB: the Metal view's color space.
        let image = try #require(bytes.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)?.makeImage()
        })
        return Image(decorative: image, scale: 2).frame(width: size.width, height: size.height)
    }

    func save(_ bitmap: NSBitmapImageRep, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"],
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("pocket-\(name).png"))
    }

    func near(_ a: (r: Int, g: Int, b: Int), _ b: (r: Int, g: Int, b: Int)) -> Bool {
        abs(a.r - b.r) <= Self.limit && abs(a.g - b.g) <= Self.limit && abs(a.b - b.b) <= Self.limit
    }

    @Test(.enabled(if: Self.hasMetal, "no Metal device"), arguments: [DeviceColor.silver, .black])
    func theRestFrameMatchesBL(_ color: DeviceColor) throws {
        let renderer = try #require(K3DRenderer.shared)
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
    @Test(.enabled(if: Self.hasMetal, "no Metal device")) func menuIsWhereTheAppDrawsIt() throws {
        let renderer = try #require(K3DRenderer.shared)
        let state = AppState()
        let flat = try flat(state, "bl-silver-2d")
        let rest = try rest(renderer, state, "k3d7-rest-silver")
        // The wheel's top is 321 pt down. MENU is 45 pt wide around x 183.
        let rows = (321 + 4) * 2..<(321 + 34) * 2, columns = 160 * 2..<206 * 2
        let a = try #require(flat.firstDark(rows: rows, columns: columns, green: 200))
        let b = try #require(rest.firstDark(rows: rows, columns: columns, green: 200))
        #expect(abs(a - b) <= 2, "MENU top: 2D \(Double(a) / 2) pt, 3D \(Double(b) / 2) pt")
    }

    /// Halfway through the crossfade (build 166 showed a grey blink there), the flat device
    /// over the 3D rest frame is the average of the two: the screen, MENU, the body and the
    /// wheel. The same fade with no compositing group, each layer at half opacity on its
    /// own, dims it: that check shows the cause of the blink.
    @Test(.enabled(if: Self.hasMetal, "no Metal device"), arguments: [DeviceColor.silver, .black])
    func theHalfwayFadeKeepsTheDevice(_ color: DeviceColor) throws {
        let renderer = try #require(K3DRenderer.shared)
        var state = AppState()
        state.deviceColor = color
        let name = color == .black ? "black" : "silver"
        let flat = try flat(state, "bl-\(name)-2d")
        let body3D = try restImage(renderer, state)
        let rest = try pixels(body3D, "k3d7-rest-\(name)")
        let device = PocketSkin(state: state, interactive: false).environment(\.pocketLook, .bl)
        let half = try pixels(K3DHandover(flat: 0.5, ready: true, content: device) { _ in body3D }, "k3d7-fade-half-\(name)")
        let perLayer = try pixels(device.opacity(0.5).background { body3D }, "k3d7-fade-per-layer-\(name)")
        var worst = 0
        for (x, y) in [(183, 150), (183, 100), (183, 342), (183, 290), (183, 381), (60, 450)] {
            // One picture at half opacity over the other gives their average. Where the rest
            // frames differ (Black's MENU marks), the 2D values alone are not the right target.
            let a = flat.mean(x, y), r = rest.mean(x, y), b = half.mean(x, y), c = perLayer.mean(x, y)
            let mix = (r: (a.r + r.r) / 2, g: (a.g + r.g) / 2, b: (a.b + r.b) / 2)
            #expect(near(mix, b), "\(name) at \(x), \(y): 2D \(a), 3D \(r), halfway \(b)")
            worst = max(worst, abs(mix.r - c.r), abs(mix.g - c.g), abs(mix.b - c.b))
        }
        #expect(worst > Self.limit, "\(name): a fade per layer moves the device by only \(worst)")
    }

    /// Until the Metal view has shown its first frame, the 2D device stays opaque, so nothing
    /// shows through it (build 167 showed the desktop for 2 frames at each click). Here the 3D
    /// body is plain red: any of it in the picture means the device was see-through.
    @Test func theDeviceStaysOpaqueUntilThe3DFrameIsReady() throws {
        #expect(K3DHandover<EmptyView, EmptyView>.shown(flat: 0.5, ready: false) == 1)
        #expect(K3DHandover<EmptyView, EmptyView>.shown(flat: 0.5, ready: true) == 0.5)
        let state = AppState()
        let flat = try flat(state, "bl-silver-2d")
        let device = PocketSkin(state: state, interactive: false).environment(\.pocketLook, .bl)
        let waiting = try pixels(K3DHandover(flat: 0.2, ready: false, content: device) { _ in Color.red }, "k3d7-fade-waiting")
        for (x, y) in [(183, 150), (183, 290), (183, 381), (60, 450)] {
            let a = flat.mean(x, y), b = waiting.mean(x, y)
            #expect(abs(a.r - b.r) <= 1 && abs(a.g - b.g) <= 1 && abs(a.b - b.b) <= 1, "at \(x), \(y): 2D \(a), waiting \(b)")
        }
    }
}
