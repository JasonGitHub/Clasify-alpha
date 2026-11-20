import AppKit
import SwiftUI
import Testing

@testable import ClasifySkins

/// CLA-163, card BZ option A v2: the turn hint's timeline (Designer 1) and its look.
@Suite @MainActor struct TurnHintTests {
    @Test func theKeyRisesInThenGoesDownAndComesUp() {
        let start = TurnHint.frame(at: 0)
        #expect(start.opacity == 0 && start.rise == 8 && start.down == 0)
        let shown = TurnHint.frame(at: 0.85)
        #expect(shown.opacity == 1 && shown.rise == 0 && shown.down == 0 && shown.glow == 0)
        #expect(TurnHint.frame(at: 1.4).down == 0)
        let down = TurnHint.frame(at: 1.7)
        #expect(down.down == 1)
        #expect(abs(down.glow - 0.15) < 1e-9)  // the pulse starts at its low point
        #expect(TurnHint.frame(at: 4.9).down == 1)
        #expect(TurnHint.frame(at: 5.3).down == 0)
        #expect(TurnHint.frame(at: 5.3).glow == 0)
        #expect(TurnHint.frame(at: 5.6).opacity == 1)
        #expect(TurnHint.frame(at: 6.6).opacity == 0)
        #expect(TurnHint.over(end: nil) == 6.6)
    }

    @Test func theGlowPulsesEvery2Point4Seconds() {
        // Full at half a pulse after the key is down, low again one pulse after.
        #expect(abs(TurnHint.frame(at: 1.7 + 1.2).glow - 1) < 1e-9)
        #expect(abs(TurnHint.frame(at: 1.7 + 2.4).glow - 0.15) < 1e-9)
    }

    @Test func theFirstCmdTurnFadesAllOutIn0Point3Seconds() {
        #expect(TurnHint.frame(at: 3, end: 3).opacity == 1)
        #expect(abs(TurnHint.frame(at: 3.15, end: 3).opacity - 0.5) < 1e-9)
        #expect(TurnHint.frame(at: 3.3, end: 3).opacity < 1e-9)
        #expect(abs(TurnHint.over(end: 3) - 3.3) < 1e-9)
        #expect(TurnHint.over(end: 6.5) == 6.6)
    }

    /// The look at 2.9 s (the glow full), on a dark ground so the white words show.
    @Test func theKeyGlowsBlueWithTheWordsUnderIt() throws {
        let renderer = ImageRenderer(content: TurnHint(start: .now, fixed: 2.9)
            .background(Color(red: 0.16, green: 0.2, blue: 0.28)))
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        #expect(image.width == 300 * 2 && image.height == 150 * 2)
        let bitmap = NSBitmapImageRep(cgImage: image)
        if let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("turn-hint.png"))
        }
        func color(_ x: Double, _ y: Double) -> NSColor? {
            bitmap.colorAt(x: Int(x * 2), y: Int(y * 2))?.usingColorSpace(.sRGB)
        }
        // The key (78 x 60, 4 pt down) has a white face in the middle.
        let face = try #require(color(150, 27 + 4 + 30))
        #expect(face.redComponent > 0.9 && face.greenComponent > 0.9 && face.blueComponent > 0.9)
        // The blue glow just left of the key.
        let glow = try #require(color(150 - 39 - 2, 27 + 4 + 30))
        #expect(glow.blueComponent > glow.redComponent + 0.2, "glow \(glow)")
        // The words have white in their line, 16 pt under the key.
        let line = 27 + 60 + 16 + 4.0
        #expect((90..<210).contains { x in
            guard let c = color(Double(x), line + 5) else { return false }
            return c.redComponent > 0.9 && c.greenComponent > 0.9 && c.blueComponent > 0.9
        })
    }
}
