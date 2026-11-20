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
        // 549 points wide. The top line, 5 wheel rows and 4 rows not on the wheel, of 42 points.
        #expect(image.width == 549 * 2)
        #expect(image.height > (9 * 42 + 60) * 2 && image.height < (9 * 42 + 120) * 2, "height \(image.height)")
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
        #expect(HowToUse.title == "How to Use myPod")
        #expect(HowToUse.wheelRows.map(\.action) == ["Turn", "Select", "Back", "Play / Pause", "Previous / Next"])
        // Card CH (CLA-165): under the section label, each of the 4 rows has its blue mark too.
        let other = topLine + 5 * 42 + 16 + 14 + 5  // the section label's padding and its text
        for row in 0..<4 {
            let top = other + row * 42
            #expect((top..<(top + 42)).contains { y in (16..<46).contains { x in blue(x, y) } }, "other row \(row)")
        }
        #expect(HowToUse.otherRows.map(\.action) == ["Shuffle / Repeat", "Turn myPod", "Take apart", "Move myPod"])
        #expect(HowToUse.otherRows.map(\.how).dropFirst() == [
            "Hold ⌘, then drag or swipe with two fingers", "Hold ⌘, then press still or pinch out", "Drag it by its body",
        ])
    }

    /// CLA-163, card CE H.2 (c): with the `hints.trial` switch on, one more row under "Not on the
    /// wheel": the menu bar icon in blue. Off, the window is as before.
    @Test func theTrialAddsTheMenuBarIconRow() throws {
        let plain = try #require(ImageRenderer(content: HowToUse()).cgImage)
        let renderer = ImageRenderer(content: HowToUse(menuBar: true))
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        #expect(image.height == (plain.height + 42) * 2)
        let bitmap = NSBitmapImageRep(cgImage: image)
        if let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("how-to-use-trial.png"))
        }
        // The last row's mark is blue, in its 30 point box 16 points from the left.
        let top = plain.height - 8  // under the Move myPod row, above the 8 point foot
        #expect((top..<(top + 42)).contains { y in
            (16..<46).contains { x in
                guard let c = bitmap.colorAt(x: x * 2, y: y * 2)?.usingColorSpace(.sRGB) else { return false }
                return c.blueComponent > c.redComponent + 0.3 && c.blueComponent > 0.6
            }
        })
        #expect(HowToUse.menuBarRow.action == "Menu bar icon" && HowToUse.menuBarRow.how == "Click it to show or hide myPod")
    }
}
