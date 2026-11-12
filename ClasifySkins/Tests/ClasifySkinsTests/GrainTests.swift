import Testing
@testable import ClasifySkins

/// Card BH (CLA-95): the grain tile is the same on every run, mid gray on average, and it
/// repeats with no seam.
@Suite struct GrainTests {
    @Test func theGrainIsStableMidGrayAndTiles() {
        let a = Grain.pixels(), b = Grain.pixels()
        let side = Grain.tile * Grain.scale
        #expect(a.count == side * side * 4 && a == b)
        var alpha = 0
        for i in stride(from: 3, to: a.count, by: 4) { alpha += Int(a[i]) }
        let mean = Double(alpha) / Double(side * side)
        #expect(abs(mean - 127.5) < 8, "mean alpha \(mean)")
        // Stitched: one tile later, the noise is the same.
        let noise = Grain.Turbulence(seed: 0)
        for y in [0.25, 37.5, 159.75] {
            #expect(abs(noise.fractal(0, 0.25, y) - noise.fractal(0, 160.25, y)) < 1e-9)
            #expect(abs(noise.fractal(0, y, 0.25) - noise.fractal(0, y, 160.25)) < 1e-9)
        }
    }
}
