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
        // 383: the check box is on by default, so it is blue (14 pt at 14, 27 + 145), off the tick.
        #expect(blue(bitmap, 17, 27 + 145 + 3))
        // The box's blue border at its left edge, the middle of its height.
        #expect((10...14).contains { blue(bitmap, $0, 27 + 29 + 52) })
        // The box is white inside (the snapshot draws the text as Text, not the AppKit view).
        let inside = try #require(bitmap.colorAt(x: 190 * 2, y: (27 + 29 + 70) * 2)?.usingColorSpace(.sRGB))
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
        #expect(bitmap.pixelsWide == 380 * 2 && bitmap.pixelsHigh == 262 * 2)
        // The wide Done button: the selected-row blue, at the middle, near the bottom.
        #expect((200...255).contains { y in blue(bitmap, 190, y) })
    }

    /// CG.3 (396): before activation, Write to Us shows in place of the form: no text box,
    /// the blue address, and Done, in the same 380 x 262.
    @Test func beforeActivationWriteToUsShows() throws {
        let bitmap = try render(ReportProblem(text: "", sent: false, fixedTime: 0, activated: false), "report-problem-write-to-us.png")
        #expect(bitmap.pixelsWide == 380 * 2 && bitmap.pixelsHigh == 262 * 2)
        #expect(!(10...14).contains { blue(bitmap, $0, 27 + 29 + 52) })  // no box border
        #expect((200...255).contains { y in blue(bitmap, 190, y) })  // Done
        // The address: #1f6fd1 text on one line above Done.
        #expect((170...215).contains { y in (120...260).contains { x in link(bitmap, x, y) } })
    }

    private func link(_ bitmap: NSBitmapImageRep, _ x: Int, _ y: Int) -> Bool {
        guard let c = bitmap.colorAt(x: x * 2, y: y * 2)?.usingColorSpace(.sRGB) else { return false }
        return c.blueComponent > 0.7 && c.redComponent < 0.35 && c.greenComponent < 0.6
    }
}

/// CTO 21:06 JST 11-20 (Jason's build 382): the real window is exactly the view, with no strip
/// under the buttons. Its snapshot shows the title bar with the macOS window buttons.
@Suite @MainActor struct ReportProblemWindowTests {
    private func check(_ content: ReportProblem, height: CGFloat, _ name: String) throws {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        ReportProblemPanel.configure(window, content)
        window.layoutIfNeeded()
        #expect(window.frame.size == CGSize(width: ReportProblem.width, height: height), "\(window.frame.size)")
        #expect(window.contentView?.frame.size == CGSize(width: ReportProblem.width, height: height))
        let frame = try #require(window.contentView?.superview)  // with the title bar and its buttons
        let rep = try #require(frame.bitmapImageRepForCachingDisplay(in: frame.bounds))
        frame.cacheDisplay(in: frame.bounds, to: rep)
        if let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"], let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }
        window.close()
    }

    @Test func theFormWindowIs380By262() throws {
        try check(ReportProblem(text: "", sent: false, fixedTime: 0), height: ReportProblem.formHeight, "report-problem-window.png")
    }

    /// CG.2 (395): from the form to Thanks, the window keeps its place and its size.
    @Test func theWindowStaysStillWhenTheFormTurnsIntoThanks() async throws {
        let window = TopFixedWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        ReportProblemPanel.configure(window, ReportProblem(text: "x", sent: false, fixedTime: 0))
        window.layoutIfNeeded()
        window.setFrameOrigin(NSPoint(x: 200, y: 300))
        let top = window.frame.maxY
        #expect(window.frame.height == ReportProblem.formHeight)
        let host = try #require(window.contentView as? FittingHost)
        host.rootView = AnyView(ReportProblem(text: "x", sent: true, fixedTime: 0.8).id("thanks"))  // a new view: Send was pressed
        host.layoutSubtreeIfNeeded()
        for _ in 0..<50 where window.frame.height != ReportProblem.thanksHeight {  // the fit runs on the next main-actor turn
            try await Task.sleep(for: .milliseconds(20))
            host.layoutSubtreeIfNeeded()
        }
        #expect(window.frame.height == ReportProblem.thanksHeight && ReportProblem.thanksHeight == ReportProblem.formHeight, "\(window.frame)")
        #expect(window.frame.maxY == top && window.frame.minX == 200, "\(window.frame)")
        window.close()
    }

    /// CG.3 (396): the window that opens follows the activation: the form when activated,
    /// Write to Us before. Its snapshot is the real window, title bar included.
    @Test func theOpeningScreenFollowsTheActivation() throws {
        for activated in [true, false] {
            let window = ReportProblemPanel.make(activated: activated) { _, _ in }
            window.layoutIfNeeded()
            #expect(window.frame.size == CGSize(width: ReportProblem.width, height: ReportProblem.formHeight))
            let frame = try #require(window.contentView?.superview)
            let rep = try #require(frame.bitmapImageRepForCachingDisplay(in: frame.bounds))
            frame.cacheDisplay(in: frame.bounds, to: rep)
            if !activated, let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"],
               let png = rep.representation(using: .png, properties: [:]) {
                try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("report-problem-window-write-to-us.png"))
            }
            // The form's white box, inside it at the middle: only when activated.
            let scale = Double(rep.pixelsWide) / ReportProblem.width
            let inside = try #require(rep.colorAt(x: Int(190 * scale), y: Int(Double(27 + 29 + 70) * scale))?.usingColorSpace(.sRGB))
            let white = inside.redComponent > 0.97 && inside.greenComponent > 0.97 && inside.blueComponent > 0.97
            #expect(white == activated, "activated \(activated): \(inside)")
            window.close()
        }
    }

    @Test func theThanksWindowIs380By262() throws {
        try check(ReportProblem(text: "x", sent: true, fixedTime: 0.8), height: ReportProblem.thanksHeight, "report-problem-window-thanks.png")
    }
}
