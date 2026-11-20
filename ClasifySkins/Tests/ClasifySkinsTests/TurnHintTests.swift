import AppKit
import SwiftUI
import Testing

@testable import ClasifySkins

/// CLA-163, card CE.1 (from BZ D): the turn hint's timeline and its look.
@Suite @MainActor struct TurnHintTests {
    @Test func theKeyRisesInAndWaits() {
        let start = TurnHint.frame(at: 0)
        #expect(start.opacity == 0 && start.rise == 8 && start.down == 0)
        #expect(TurnHint.frame(at: 0.5).opacity == 1)
        let shown = TurnHint.frame(at: 0.85)
        #expect(shown.rise == 0 && shown.down == 0 && shown.glow == 0 && shown.blue == 0)
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

    /// When the hint ends, all fades out in 0.5 s and sinks 8 pt in 0.85 s.
    @Test func theEndFadesAllOut() {
        #expect(TurnHint.frame(at: 10, end: 10).opacity == 1)
        #expect(abs(TurnHint.frame(at: 10.25, end: 10).opacity - 0.5) < 1e-9)
        #expect(TurnHint.frame(at: 10.5, end: 10).opacity < 1e-9)
        #expect(TurnHint.frame(at: 10.9, end: 10).rise == 8)
        #expect(abs(TurnHint.over(end: 10) - 10.85) < 1e-9)
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
