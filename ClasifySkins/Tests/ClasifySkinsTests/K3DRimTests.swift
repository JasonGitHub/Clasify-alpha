import AppKit
import ClasifyCore
import Foundation
import Metal
import SwiftUI
import Testing

@testable import ClasifySkins

/// CLA-119, #263 design check: a black line on the 3D body's right and bottom edge from 1°.
/// The cause: `K3DShadow`'s hidden black copy (the section hull) is wider than the mesh's real
/// outline, and its mask keeps a band 1.5 pt outside the outline. Now only its shadow draws.
@Suite @MainActor struct K3DRimTests {
    nonisolated static var hasMetal: Bool { MTLCreateSystemDefaultDevice() != nil }

    /// The cause, in numbers: how far the section hull runs past the mesh's outline.
    @Test(.enabled(if: Self.hasMetal, "no Metal device"), arguments: [1.0, 2, 3, 5])
    func theSectionHullIsWiderThanTheBody(_ angle: Double) throws {
        _ = try #require(K3DRenderer.shared)
        let cut = K3DShadow.cut(angle: angle, lift: 0)
        let copy = K3DShadow.outline(angle: angle, lift: 0, drop: PocketSkin.shadowDrop)
        let size = PocketSkin.size
        var past: [String] = []
        // At mid height on the right, and in the middle of the bottom.
        for (name, start, step) in [("right", CGPoint(x: size.width / 2, y: size.height / 2), CGVector(dx: 0.01, dy: 0)),
                                    ("bottom", CGPoint(x: size.width / 2, y: size.height / 2), CGVector(dx: 0, dy: 0.01))] {
            func last(_ path: Path) -> Double {
                var p = start, n = 0
                while path.contains(p) && n < 100_000 { p.x += step.dx; p.y += step.dy; n += 1 }
                return Double(n) * 0.01
            }
            past.append("\(name) \(String(format: "%.2f", last(copy) - last(cut))) pt")
            // Cut to the outline, the copy never runs past it.
            #expect(last(copy.intersection(cut)) <= last(cut) + 0.011, "\(name) at \(angle)°")
        }
        print("CLA-119 rim at \(angle)°: section hull past the body: \(past.joined(separator: ", "))")
    }

    /// At 1, 2, 3 and 5°, the 3D body with its shadow on a clear background: where the body has
    /// no pixel, nothing is opaque (only the soft shadow), and on Silver the last opaque rim
    /// pixel at mid height on the right and in the middle of the bottom is not dark (90 or more).
    @Test(.enabled(if: Self.hasMetal, "no Metal device"), arguments: [DeviceColor.silver, .black])
    func theRimHasNoBlackLine(_ color: DeviceColor) throws {
        let renderer = try #require(K3DRenderer.shared)
        var state = AppState.silver
        state.deviceColor = color
        let black = color == .black
        let shot = try #require(K3DSpike.snapshot(state))
        let size = PocketSkin.size, m: CGFloat = 60
        let room = CGSize(width: size.width + 2 * m, height: size.height + 2 * m)
        let w = Int(room.width) * 2, h = Int(room.height) * 2
        for angle in [1.0, 2, 3, 5] {
            let body = try #require(renderer.image(K3DPose(angle: angle, black: black), screen: shot, size: room, scale: 2))  // BGRA
            let bodyImage = try #require(K3DFadeFramesTests.image(body, w, h))
            let view = ZStack {
                K3DShadow(angle: angle, lift: 0, black: black)
                Image(decorative: bodyImage, scale: 2)
            }
            .frame(width: room.width, height: room.height)
            let renderer2 = ImageRenderer(content: view)
            renderer2.scale = 2
            let frame = try #require(renderer2.cgImage.flatMap { Self.rgba($0, w, h) })
            var lines: [String] = []
            for (name, along) in [("right", true), ("bottom", false)] {
                var values: [String] = [], lastOpaque: Int?
                let cx = w / 2, cy = h / 2
                let span = along ? Int(size.width / 2 + 8) * 2 : Int(size.height / 2 + 8) * 2
                let from = along ? Int(size.width / 2 - 6) * 2 : Int(size.height / 2 - 6) * 2
                for d in from..<span {
                    let (x, y) = along ? (cx + d, cy) : (cx, cy + d)
                    let i = (y * w + x) * 4
                    let a = Int(frame[i + 3]), lum = Self.luminance(frame, i)
                    let bodyAlpha = Int(body[i + 3])
                    if bodyAlpha == 0 { #expect(a < 250, "\(name) at \(angle)°, \(d - from) px: opaque \(a) past the body") }
                    if a >= 250 { lastOpaque = lum }
                    if d >= span - 40 { values.append("\(lum)/\(a)") }
                }
                if !black, let lastOpaque { #expect(lastOpaque >= 90, "\(name) at \(angle)°: last opaque rim pixel \(lastOpaque)") }
                lines.append("\(name): \(values.joined(separator: " "))")
            }
            print("CLA-119 rim \(black ? "black" : "silver") \(angle)° (lum/alpha, outward): \(lines.joined(separator: " | "))")
        }
    }

    /// Straight RGBA bytes of an image, in sRGB.
    static func rgba(_ image: CGImage, _ w: Int, _ h: Int) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        for i in stride(from: 0, to: bytes.count, by: 4) where bytes[i + 3] > 0 && bytes[i + 3] < 255 {
            let a = Double(bytes[i + 3])
            for c in 0..<3 { bytes[i + c] = UInt8(min(255, (Double(bytes[i + c]) * 255 / a).rounded())) }
        }
        return bytes
    }

    /// Rec. 601 luminance of the RGB at `i`.
    static func luminance(_ bytes: [UInt8], _ i: Int) -> Int {
        let r = Double(bytes[i]), g = Double(bytes[i + 1]), b = Double(bytes[i + 2])
        return Int((0.299 * r + 0.587 * g + 0.114 * b).rounded())
    }
}
