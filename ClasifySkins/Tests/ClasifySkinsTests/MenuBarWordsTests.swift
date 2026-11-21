import AppKit
import Testing

@testable import ClasifySkins

/// CLA-163, card CE option F (a test behind `hints.menuBarStyle`): white words 16 pt under the
/// menu bar icon. CTO rule (21:06 JST 11-20): a new window gets snapshots of the real window.
/// The words' window is clear, so the PNGs come as the window draws, and in place under a
/// light and a dark menu bar with the icon's glow.
@Suite @MainActor struct MenuBarWordsTests {
    /// Centered under the icon, 16 pt below its bottom edge, and kept 8 pt inside its screen.
    @Test func theWordsSitUnderTheIcon() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let icon = NSRect(x: 1000, y: 878, width: 18, height: 18)
        let frame = MenuBarWordsPanel.frame(under: icon, screens: [screen])
        #expect(frame == NSRect(x: 1009 - 160, y: 878 - 16 - 40, width: 320, height: 40))
        let right = MenuBarWordsPanel.frame(under: NSRect(x: 1400, y: 878, width: 18, height: 18), screens: [screen])
        #expect(abs(right.maxX - CGFloat(1440 - 8)) < 0.01, "right \(right)")
        let left = MenuBarWordsPanel.frame(under: NSRect(x: 20, y: 878, width: 18, height: 18), screens: [screen])
        #expect(left.minX == 8)
        #expect(MenuBarWords.words == "Click here to show or hide myPod")
    }

    /// The real window: clear, no shadow, takes no clicks, stays when myPod hides.
    @Test func theWindowDrawsOnlyTheWords() throws {
        let words = MenuBarWordsPanel(under: NSRect(x: 600, y: 600, width: 18, height: 18))
        let panel = words.panel
        defer { panel.close() }
        #expect(!panel.isOpaque && panel.ignoresMouseEvents && !panel.hasShadow && !panel.canHide && panel.alphaValue == 0)
        #expect(panel.frame.size == CGSize(width: MenuBarWords.width, height: MenuBarWords.height))
        let view = try #require(panel.contentView)
        view.layoutSubtreeIfNeeded()
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 80, bitsPerSample: 8,
                                                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        let corner = try #require(rep.colorAt(x: 2, y: 78))
        #expect(corner.alphaComponent == 0)
        // White in the words' line, 14 pt text at the window's top.
        #expect((100..<540).contains { x in
            guard let c = rep.colorAt(x: x, y: 18)?.usingColorSpace(.sRGB) else { return false }
            return c.alphaComponent > 0.9 && c.redComponent > 0.9 && c.greenComponent > 0.9 && c.blueComponent > 0.9
        })
        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else { return }
        let url = URL(fileURLWithPath: dir)
        if let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: url.appendingPathComponent("menu-bar-words-f-window.png"))
        }
        for dark in [false, true] {
            let image = try #require(Self.inPlace(words: rep, dark: dark))
            if let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                try png.write(to: url.appendingPathComponent("menu-bar-words-f-\(dark ? "dark" : "light").png"))
            }
        }
    }

    /// A 400 x 110 pt piece of the screen at 2x: a 24 pt menu bar with the glowing icon at
    /// x 200, and the words' window 16 pt under the icon, on a desktop picture's blue.
    static func inPlace(words: NSBitmapImageRep, dark: Bool) -> CGImage? {
        let scale = 2.0, size = CGSize(width: 400, height: 110)
        guard let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(CGColor(srgbRed: 0.22, green: 0.36, blue: 0.56, alpha: 1))  // the desktop
        context.fill(CGRect(origin: .zero, size: size))
        let bar = CGRect(x: 0, y: size.height - 24, width: size.width, height: 24)
        context.setFillColor(dark ? CGColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1) : CGColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1))
        context.fill(bar)
        let slot = CGRect(x: 185, y: bar.minY + 1, width: 30, height: 22)
        let icon = CGRect(x: 6, y: 2, width: 18, height: 18)  // in the slot
        context.saveGState()
        context.translateBy(x: slot.minX + icon.minX, y: slot.minY + icon.minY)
        context.addPath(MenuBarGlow.iconPath)
        context.setFillColor(dark ? .white : .black)
        context.fillPath(using: .evenOdd)
        context.restoreGState()
        let glow = MenuBarGlow(frame: NSRect(origin: .zero, size: slot.size), icon: icon, breath: 1)
        glow.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        glow.viewDidChangeEffectiveAppearance()
        glow.show(animated: false)
        context.saveGState()
        context.translateBy(x: slot.minX, y: slot.minY)
        glow.layer?.render(in: context)
        context.restoreGState()
        if let image = words.cgImage {
            let iconBottom = slot.minY + icon.minY
            context.draw(image, in: CGRect(x: 200 - MenuBarWords.width / 2, y: iconBottom - MenuBarWords.gap - MenuBarWords.height,
                                           width: MenuBarWords.width, height: MenuBarWords.height))
        }
        return context.makeImage()
    }
}
