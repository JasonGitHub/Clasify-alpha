import AppKit
import SwiftUI
import Testing

@testable import ClasifySkins

/// Help › How to Use Clasify (card BC, change 152, with the BC.1 look, change 196).
@Suite @MainActor struct HowToUseTests {
    @Test func theWindowShowsEachActionWithItsBlueMark() throws {
        let renderer = ImageRenderer(content: HowToUse())
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        // 549 points wide. The top line, 5 wheel rows and the Shuffle / Repeat row of 42 points.
        #expect(image.width == 549 * 2)
        #expect(image.height > (6 * 42 + 60) * 2 && image.height < (6 * 42 + 120) * 2, "height \(image.height)")
        let bitmap = NSBitmapImageRep(cgImage: image)
        if let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("how-to-use.png"))
        }
        // Each wheel row's mark is blue, in its 30 point box 16 points from the left.
        func blue(_ x: Int, _ y: Int) -> Bool {
            guard let c = bitmap.colorAt(x: x * 2, y: y * 2)?.usingColorSpace(.sRGB) else { return false }
            return c.blueComponent > c.redComponent + 0.3 && c.blueComponent > 0.6
        }
        let topLine = 14 + 15 + 10  // the top line's padding and its text
        for row in 0..<5 {
            let top = topLine + row * 42
            #expect((top..<(top + 42)).contains { y in (16..<46).contains { x in blue(x, y) } }, "row \(row)")
        }
        #expect(HowToUse.title == "How to Use Clasify")
        #expect(HowToUse.wheelRows.map(\.action) == ["Turn", "Select", "Back", "Play / Pause", "Previous / Next"])
        #expect(HowToUse.otherRows.map(\.action) == ["Shuffle / Repeat"])
    }
}
