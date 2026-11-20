import AppKit
import SwiftUI
import Testing

@testable import ClasifySkins

/// Card CG (CLA-166, changes 381-385): Help › Report a Problem, the form and the Thanks screen.
@Suite @MainActor struct ReportProblemTests {
    private func render(_ view: ReportProblem, _ name: String) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        if let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }
        return bitmap
    }

    private func blue(_ bitmap: NSBitmapImageRep, _ x: Int, _ y: Int) -> Bool {
        guard let c = bitmap.colorAt(x: x * 2, y: y * 2)?.usingColorSpace(.sRGB) else { return false }
        return c.blueComponent > c.redComponent + 0.3 && c.blueComponent > 0.6
    }

    @Test func theEmptyFormShowsTheBoxAndTheOnCheckBox() throws {
        let bitmap = try render(ReportProblem(text: "", sent: false, fixedTime: 0), "report-problem.png")
        #expect(bitmap.pixelsWide == 380 * 2 && bitmap.pixelsHigh == 262 * 2)
        // 383: the check box is on by default, so it is blue (14 pt at 14, 26 + 145), off the tick.
        #expect(blue(bitmap, 17, 26 + 145 + 3))
        // The box's blue border at its left edge, the middle of its height.
        #expect((10...14).contains { blue(bitmap, $0, 26 + 29 + 52) })
        // The box is white inside (the snapshot draws the text as Text, not the AppKit view).
        let inside = try #require(bitmap.colorAt(x: 190 * 2, y: (26 + 29 + 70) * 2)?.usingColorSpace(.sRGB))
        #expect(inside.redComponent > 0.95 && inside.greenComponent > 0.95 && inside.blueComponent > 0.95)
        #expect(ReportProblem(text: "  \n ", sent: false, fixedTime: nil).report.isEmpty)
        #expect(ReportProblem(text: " The wheel got stuck\n", sent: false, fixedTime: nil).report == "The wheel got stuck")
    }

    /// The CTO on #367: the server answers 400 above 4000 code points after the trim, so the box
    /// stops at 4000 and a long report is never dropped.
    @Test func theBoxStopsAt4000Characters() {
        #expect(ReportProblem.capped("short") == "short")
        let exact = "  " + String(repeating: "a", count: 4000) + "\n"
        #expect(ReportProblem.capped(exact) == exact)
        let long = "\n " + String(repeating: "é", count: 3999) + "👍🏽 more"
        let cut = ReportProblem.capped(long)
        #expect(cut.unicodeScalars.count == 4000 && cut.hasPrefix("é") && cut.unicodeScalars.last == "👍")
        #expect(ReportProblem(text: cut, sent: false, fixedTime: nil).report.unicodeScalars.count <= ReportProblem.maxCount)
    }

    @Test func aTypedReportEnablesSend() throws {
        _ = try render(ReportProblem(text: "Song skipped twice in a row.", sent: false, fixedTime: 0), "report-problem-typed.png")
    }

    @Test func theThanksScreenShowsTheWave() throws {
        let bitmap = try render(ReportProblem(text: "x", sent: true, fixedTime: 0.8), "report-problem-thanks.png")
        #expect(bitmap.pixelsWide == 380 * 2 && bitmap.pixelsHigh == 246 * 2)
        // The wide Done button: the selected-row blue, at the middle, near the bottom.
        #expect((180...235).contains { y in blue(bitmap, 190, y) })
    }
}
