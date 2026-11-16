import AppKit
import Foundation
import Testing

@testable import ClasifySkins

/// CLA-105 B3: the take-apart parts' printed textures, drawn in code as the mock's canvases.
/// PNGs for the design check: `pocket-k3d-print-label.png`, `-board.png`, `-parts.png`.
@Suite struct K3DPrintsTests {
    /// Pixels where `test` holds, counted on every 4th pixel of every 4th row.
    func count(_ bytes: [UInt8], _ w: Int, _ h: Int, _ test: (UInt8, UInt8, UInt8) -> Bool) -> Int {
        var n = 0
        for y in stride(from: 0, to: h, by: 4) {
            for x in stride(from: 0, to: w, by: 4) {
                let i = (y * w + x) * 4
                if test(bytes[i], bytes[i + 1], bytes[i + 2]) { n += 1 }
            }
        }
        return n
    }

    func save(_ bytes: [UInt8], _ w: Int, _ h: Int, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else { return }
        var copy = bytes
        let image = copy.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)?.makeImage()
        }
        guard let image, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("pocket-k3d-print-\(name).png"))
    }

    /// The labels: opaque, the drive label pale with dark text, and the ribbon rows' white
    /// print on black (the shader reads its red).
    @Test func theLabelsAreDrawn() throws {
        let s = K3DPrints.labelSize
        let bytes = try #require(K3DPrints.label())
        #expect(bytes.count == s * s * 4)
        save(bytes, s, s, "label")
        #expect(bytes[3] == 255, "the drive label is opaque")
        let dark = count(bytes, s, s) { r, g, b in Int(r) + Int(g) + Int(b) < 150 }
        let pale = count(bytes, s, s) { r, g, b in Int(r) + Int(g) + Int(b) > 600 }
        #expect(dark > 500 && pale > 5000, "dark \(dark), pale \(pale)")
    }

    /// The board: white text (red channel) on black, and blue keep-out boxes under it, wheel
    /// side left and chip side right.
    @Test func theBoardPrintIsDrawn() throws {
        let (w, h) = K3DPrints.boardSize
        let bytes = try #require(K3DPrints.board())
        #expect(bytes.count == w * h * 4)
        save(bytes, w, h, "board")
        for (name, x0) in [("wheel side", 0), ("chip side", w / 2)] {
            var text = 0, keepOut = 0
            // Every 2nd pixel: the texture is half the mock's size.
            for y in stride(from: 0, to: h, by: 2) {
                for x in stride(from: x0, to: x0 + w / 2, by: 2) {
                    let i = (y * w + x) * 4
                    if bytes[i] > 128 { text += 1 }
                    if bytes[i + 2] > 128 { keepOut += 1 }
                }
            }
            #expect(text > 200 && keepOut > text, "\(name): text \(text), keep-out \(keepOut)")
        }
    }

    /// The other parts: white text, and the shield's stamp in red only (no blue pen tick: Jason
    /// 15:13 JST 11-14, so no green).
    @Test func thePartsPrintIsDrawn() throws {
        let s = K3DPrints.partsSize
        let bytes = try #require(K3DPrints.parts())
        #expect(bytes.count == s * s * 4)
        save(bytes, s, s, "parts")
        let text = count(bytes, s, s) { r, _, _ in r > 128 }
        let stamp = count(bytes, s, s) { r, g, _ in r > 128 && g < 64 }
        let tick = count(bytes, s, s) { r, g, _ in g > 128 && r < 64 }
        #expect(text > 500 && stamp > 50, "text \(text), stamp \(stamp)")
        #expect(tick == 0, "no pen tick")
    }

    /// The time to draw all three, for the log (they are drawn off the main actor).
    @Test func theDrawingTimeIsLogged() throws {
        let clock = ContinuousClock()
        let start = clock.now
        _ = try #require(K3DPrints.all())
        print("CLA-105 B3: K3DPrints.all() took \(clock.now - start)")
    }
}
