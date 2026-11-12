import CoreGraphics
import Foundation
import SwiftUI

/// The Classic body's matte grain (card BH, CLA-95), as the mockup's `.dev::after`: SVG
/// `feTurbulence` fractal noise, base frequency 0.8, 1 octave, stitched on a 160 point tile, with
/// the red channel copied to gray. It is made in memory, the same every time, and never written
/// to disk.
enum Grain {
    /// The tile's size in points.
    static let tile = 160
    /// Pixels per point. The mockup draws the noise in CSS pixels, so a 2x tile keeps its size.
    static let scale = 2

    /// The tile, made once.
    @MainActor static let image: Image = {
        let side = tile * scale
        let data = Data(pixels()) as CFData
        let image = CGImage(
            width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return Image(decorative: image, scale: CGFloat(scale))
    }()

    /// The tile's RGBA bytes, premultiplied: gray from the noise's red channel, alpha from its
    /// alpha channel, as `feColorMatrix` leaves them. Filtered in sRGB, as the mockup asks.
    static func pixels() -> [UInt8] {
        let side = tile * scale
        let noise = Turbulence(seed: 0)
        var out = [UInt8](repeating: 0, count: side * side * 4)
        for py in 0..<side {
            for px in 0..<side {
                // The pixel's center, in points.
                let p = (Double(px) + 0.5) / Double(scale), q = (Double(py) + 0.5) / Double(scale)
                let gray = channel(noise.fractal(0, p, q))
                let alpha = channel(noise.fractal(3, p, q))
                let i = (py * side + px) * 4
                let g = UInt8((gray * alpha * 255).rounded())
                out[i] = g; out[i + 1] = g; out[i + 2] = g
                out[i + 3] = UInt8((alpha * 255).rounded())
            }
        }
        return out
    }

    /// Fractal noise gives (sum + 1) / 2, kept between 0 and 1.
    static func channel(_ sum: Double) -> Double { min(1, max(0, (sum + 1) / 2)) }

    /// The SVG 1.1 reference `feTurbulence`, for one octave of fractal noise with stitching on
    /// the tile. Seed 0, as the mockup has no seed.
    struct Turbulence {
        static let size = 0x100, mask = 0xff, offset = 4096.0
        var lattice = [Int](repeating: 0, count: 0x100 + 0x100 + 2)
        var gradient = [[(Double, Double)]](repeating: .init(repeating: (0, 0), count: 0x100 + 0x100 + 2), count: 4)
        /// The base frequency after stitching, and the stitch's size and wrap.
        let frequency: Double
        let width: Int, wrap: Int

        init(seed: Int, baseFrequency: Double = 0.8, tile: Int = Grain.tile) {
            var s = Self.setup(seed)
            for k in 0..<4 {
                for i in 0..<Self.size {
                    lattice[i] = i
                    s = Self.random(s); let x = Double(s % (2 * Self.size) - Self.size) / Double(Self.size)
                    s = Self.random(s); let y = Double(s % (2 * Self.size) - Self.size) / Double(Self.size)
                    let length = (x * x + y * y).squareRoot()
                    gradient[k][i] = length == 0 ? (0, 0) : (x / length, y / length)
                }
            }
            for i in stride(from: Self.size - 1, to: 0, by: -1) {
                s = Self.random(s)
                lattice.swapAt(i, s % Self.size)
            }
            for i in 0..<(Self.size + 2) {
                lattice[Self.size + i] = lattice[i]
                for k in 0..<4 { gradient[k][Self.size + i] = gradient[k][i] }
            }
            // Stitching moves the frequency to the nearest one with whole cycles on the tile.
            let t = Double(tile)
            let low = (t * baseFrequency).rounded(.down) / t, high = (t * baseFrequency).rounded(.up) / t
            frequency = low == 0 || baseFrequency / low < high / baseFrequency ? low : high
            width = Int(t * frequency + 0.5)
            wrap = Int(Self.offset) + width
        }

        static func setup(_ seed: Int) -> Int {
            let m = 2_147_483_647
            var s = seed
            if s <= 0 { s = -(s % (m - 1)) + 1 }
            if s > m - 1 { s = m - 1 }
            return s
        }

        static func random(_ seed: Int) -> Int {
            var s = 16807 * (seed % 127_773) - 2836 * (seed / 127_773)
            if s <= 0 { s += 2_147_483_647 }
            return s
        }

        /// One octave of fractal noise for `channel` (0 red, 3 alpha) at a point in points.
        func fractal(_ channel: Int, _ x: Double, _ y: Double) -> Double {
            noise(channel, x * frequency, y * frequency)
        }

        func noise(_ k: Int, _ x: Double, _ y: Double) -> Double {
            func corners(_ v: Double) -> (Int, Int, Double, Double) {
                let t = v + Self.offset
                var b0 = Int(t), b1 = b0 + 1
                let r0 = t - t.rounded(.towardZero)
                // Stitch: wrap the lattice at the tile's edge, before the mask.
                if b0 >= wrap { b0 -= width }
                if b1 >= wrap { b1 -= width }
                b0 &= Self.mask; b1 &= Self.mask
                return (b0, b1, r0, r0 - 1)
            }
            let (bx0, bx1, rx0, rx1) = corners(x)
            let (by0, by1, ry0, ry1) = corners(y)
            let i = lattice[bx0], j = lattice[bx1]
            let b00 = lattice[i + by0], b10 = lattice[j + by0], b01 = lattice[i + by1], b11 = lattice[j + by1]
            let sx = rx0 * rx0 * (3 - 2 * rx0), sy = ry0 * ry0 * (3 - 2 * ry0)
            func dot(_ b: Int, _ rx: Double, _ ry: Double) -> Double { gradient[k][b].0 * rx + gradient[k][b].1 * ry }
            let a = dot(b00, rx0, ry0) + sx * (dot(b10, rx1, ry0) - dot(b00, rx0, ry0))
            let b = dot(b01, rx0, ry1) + sx * (dot(b11, rx1, ry1) - dot(b01, rx0, ry1))
            return a + sy * (b - a)
        }
    }
}
