import AppKit
import ImageIO
import SwiftUI
import Testing

@testable import ClasifySkins

/// CLA-163, card CE.1 (from BZ D): the turn hint's timeline and its look.
@Suite @MainActor struct TurnHintTests {
    @Test func theKeyRisesInAndWaits() {
        let start = TurnHint.frame(at: 0)
        #expect(start.opacity == 0 && start.down == 0)
        #expect(TurnHint.frame(at: 0.5).opacity == 1)
        let shown = TurnHint.frame(at: 0.85)
        #expect(shown.down == 0 && shown.glow == 0 && shown.blue == 0)
        #expect(TurnHint.frame(at: 600).opacity == 1)  // no timer ends it
    }

    /// 393: from 1.4 s the key presses itself every 7.2 s: down in 0.7 s, up at 3.0 s in 0.7 s.
    @Test func theKeyPressesItselfInA7Point2SecondLoop() {
        func down(_ t: Double) -> Double { TurnHint.down(at: t, press: nil) }
        #expect(down(1.4) == 0 && abs(down(1.75) - 0.5) < 1e-9)
        #expect(down(2.2) == 1 && down(4.3) == 1)
        #expect(abs(down(4.75) - 0.5) < 1e-9)
        #expect(down(5.2) == 0 && down(8.5) == 0)
        #expect(down(9.4) == 1)
        // The device nudges 0.6 s into each press.
        #expect(abs(TurnHint.nextNudge(after: 0) - 2.0) < 1e-9)
        #expect(abs(TurnHint.nextNudge(after: 2.0) - 9.2) < 1e-9)
        #expect(abs(TurnHint.nextNudge(after: 9.3) - 16.4) < 1e-9)
    }

    /// From 1.4 s the ⌘ is blue and the rings pulse from 0.15 to 1 every 2.4 s.
    @Test func theGlowPulsesEvery2Point4Seconds() {
        #expect(TurnHint.frame(at: 1.8).blue == 1 && TurnHint.frame(at: 1.4).blue == 0)
        #expect(abs(TurnHint.frame(at: 3.6).glow - 1) < 1e-9)
        #expect(abs(TurnHint.frame(at: 4.8).glow - 0.15) < 1e-9)
    }

    /// 394: the person's own ⌘ key moves the key in 0.08 s, from where it is, and the loop
    /// does not come back.
    @Test func theKeyFollowsThePersonsCommandKey() {
        let down = TurnHint.Press(at: 5.5, down: true, from: TurnHint.down(at: 5.5, press: nil))
        #expect(down.from == 0)
        #expect(TurnHint.down(at: 5.6, press: down) == 1)
        let up = TurnHint.Press(at: 6, down: false, from: TurnHint.down(at: 6, press: down))
        #expect(up.from == 1 && abs(TurnHint.frame(at: 6.04, press: up).down - 0.5) < 1e-9)
        #expect(TurnHint.down(at: 6.1, press: up) == 0)
        #expect(TurnHint.down(at: 9.4, press: up) == 0)
    }

    /// When the hint ends, all fades out in place in 0.5 s (Jason: "it shouldnt rise").
    @Test func theEndFadesAllOut() {
        #expect(TurnHint.frame(at: 10, end: 10).opacity == 1)
        #expect(abs(TurnHint.frame(at: 10.25, end: 10).opacity - 0.5) < 1e-9)
        #expect(TurnHint.frame(at: 10.5, end: 10).opacity < 1e-9)
        #expect(abs(TurnHint.over(end: 10) - 10.5) < 1e-9)
    }

    /// The look at 3.6 s (the key down, the glow full), on a dark ground so the white words show.
    @Test func theKeyGlowsBlueWithTheWordsUnderIt() throws {
        let renderer = ImageRenderer(content: TurnHint(start: .now, fixed: 3.6)
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

/// CTO rule (21:06 JST 11-20): a new window gets snapshots of the real window. The turn hint's
/// window is clear, so each PNG comes twice: as the window draws (clear), and on a dark desktop.
@Suite @MainActor struct TurnHintWindowTests {
    private func check(at t: Double, press: TurnHint.Press? = nil, _ name: String) throws -> NSBitmapImageRep {
        let (panel, _) = TurnHintPanel.make(TurnHint(start: .now, press: press, fixed: t), frame: NSRect(origin: .zero, size: TurnHint.size))
        defer { panel.close() }
        #expect(panel.frame.size == TurnHint.size && !panel.isOpaque && panel.ignoresMouseEvents && !panel.hasShadow)
        let frame = try #require(panel.contentView?.superview ?? panel.contentView)
        let rep = try #require(frame.bitmapImageRepForCachingDisplay(in: frame.bounds))
        frame.cacheDisplay(in: frame.bounds, to: rep)
        let image = NSImage(size: TurnHint.size)
        image.addRepresentation(rep)
        let dark = NSImage(size: TurnHint.size, flipped: false) { rect in
            NSColor(red: 0.16, green: 0.2, blue: 0.28, alpha: 1).setFill()
            rect.fill()
            image.draw(in: rect)
            return true
        }
        if let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] {
            let url = URL(fileURLWithPath: dir)
            if let png = rep.representation(using: .png, properties: [:]) {
                try png.write(to: url.appendingPathComponent(name + ".png"))
            }
            if let tiff = dark.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try png.write(to: url.appendingPathComponent(name + "-on-dark.png"))
            }
        }
        return rep
    }

    /// Clear round the key and the words: only they draw.
    @Test func theWindowIsClearRoundTheKey() throws {
        let rep = try check(at: 1.0, "turn-hint-window-up")
        let corner = try #require(rep.colorAt(x: 2, y: 2))
        #expect(corner.alphaComponent == 0)
        let face = try #require(rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh * (27 + 30) / 150))
        #expect(face.alphaComponent > 0.95)
    }

    @Test func theWindowWithTheKeyDownAndGlowing() throws {
        _ = try check(at: 3.6, "turn-hint-window-down")
    }

    /// 394: the person holds ⌘, so the key is down by their hand, at 1.0 s with no glow yet.
    @Test func theWindowWithThePersonsCommandKeyDown() throws {
        _ = try check(at: 1.0, press: TurnHint.Press(at: 0.9, down: true, from: 0), "turn-hint-window-held")
    }
}

/// Jason (build 390): "the button press on the turn hint seemed not smooth". The key moved in
/// whole device pixels: 8 steps for its 4 pt at 2x, each held for several frames. These tests
/// draw one press of the key's loop at 60 fps and measure where the key is in each frame from
/// the pixels (the "command" label's centre of ink), not from the model: drawn by ImageRenderer
/// at 2x, and drawn by the real hint window (`TurnHintPanel`) into a 2x bitmap. Each frame of
/// the sink and the rise must move the key on: no step, no repeat. They also save the frames as
/// a GIF and the measures as a CSV for the designer.
@Suite @MainActor struct TurnHintMotionTests {
    /// One whole press: 1.4 s to 5.4 s (sink 0.7 s, down until 3.0 s, rise 0.7 s, rest).
    private let times = (0...240).map { 1.4 + Double($0) / 60 }

    /// One frame at `t` seconds by ImageRenderer, at 2x, on the dark desktop colour.
    private func rendered(_ t: Double) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: TurnHint(start: .now, fixed: t)
            .background(Color(red: 0.16, green: 0.2, blue: 0.28)))
        renderer.scale = 2
        return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
    }

    /// One frame at `t` seconds as the real hint window draws it, into a 2x bitmap.
    private func windowed(_ t: Double) throws -> NSBitmapImageRep {
        let (panel, _) = TurnHintPanel.make(TurnHint(start: .now, fixed: t), frame: NSRect(origin: .zero, size: TurnHint.size))
        defer { panel.close() }
        let view = try #require(panel.contentView)
        view.layoutSubtreeIfNeeded()
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 600, pixelsHigh: 300, bitsPerSample: 8,
                                                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = TurnHint.size
        view.cacheDisplay(in: view.bounds, to: rep)
        if t == times[0] { print("turn hint window backingScaleFactor:", panel.backingScaleFactor) }
        return rep
    }

    /// The label's centre of ink, in points from the top: dark pixels on the key's white face.
    private func labelY(_ bitmap: NSBitmapImageRep) -> Double {
        let scale = Double(bitmap.pixelsWide) / TurnHint.size.width
        var weight = 0.0, sum = 0.0
        for py in Int(62 * scale)..<Int(83 * scale) {  // the label, up or down, and only the face round it
            for px in Int(115 * scale)..<Int(160 * scale) {  // the label's left part
                guard let c = bitmap.colorAt(x: px, y: py)?.usingColorSpace(.sRGB) else { continue }
                let ink = c.alphaComponent * max(0, 0.94 - (c.redComponent + c.greenComponent + c.blueComponent) / 3)
                weight += ink
                sum += ink * (Double(py) + 0.5)
            }
        }
        return weight > 0 ? sum / weight / scale : .nan
    }

    /// Checks one way of drawing, and saves its CSV (and GIF) as `name`.
    private func check(_ name: String, gif: Bool, _ draw: (Double) throws -> NSBitmapImageRep) throws {
        var rows = ["t,model_down_pt,measured_label_y_pt"]
        var measured: [Double] = []
        var images: [CGImage] = []
        for (n, t) in times.enumerated() {
            let bitmap = try draw(t)
            let y = labelY(bitmap)
            measured.append(y)
            rows.append(String(format: "%.4f,%.4f,%.4f", t, 4 * TurnHint.down(at: t, press: nil), y))
            if gif, n % 2 == 0, let image = bitmap.cgImage { images.append(image) }  // 30 fps for the GIF
        }
        if let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] {
            let url = URL(fileURLWithPath: dir)
            try rows.joined(separator: "\n").write(to: url.appendingPathComponent(name + ".csv"), atomically: true, encoding: .utf8)
            if gif { writeGIF(images, to: url.appendingPathComponent(name + ".gif")) }
        }
        print("\(name) measured label y (pt):", measured.map { String(format: "%.3f", $0) }.joined(separator: " "))
        // Each frame where the model moves the key 0.05 pt or more (the sink from 1.4 s, the
        // rise from 4.4 s) moves the drawn key on by at least a third of that.
        for n in 1..<times.count {
            let step = 4 * (TurnHint.down(at: times[n], press: nil) - TurnHint.down(at: times[n - 1], press: nil))
            guard abs(step) >= 0.05 else { continue }
            #expect((measured[n] - measured[n - 1]) * (step > 0 ? 1 : -1) > abs(step) / 3,
                    "\(name) frame \(n) at \(times[n]) s: model \(step) pt, drawn \(measured[n - 1]) -> \(measured[n])")
        }
        // Down, the key is 4 pt lower than up.
        #expect(abs(measured[60] - measured[0] - 4) < 0.25, "\(name): \(measured[0]) -> \(measured[60])")
    }

    @Test func thePressMovesTheKeyOnInEveryFrame() throws {
        try check("turn-hint-press", gif: true) { try rendered($0) }
    }

    @Test func theRealWindowMovesTheKeyOnInEveryFrame() throws {
        try check("turn-hint-press-window", gif: false) { try windowed($0) }
    }

    private func writeGIF(_ images: [CGImage], to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "com.compuserve.gif" as CFString, images.count, nil) else { return }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for image in images {
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / 30]] as CFDictionary)
        }
        CGImageDestinationFinalize(destination)
    }
}
