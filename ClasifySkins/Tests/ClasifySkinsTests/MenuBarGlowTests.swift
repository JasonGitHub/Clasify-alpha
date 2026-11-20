import AppKit
import Testing

@testable import ClasifySkins

/// CLA-163, card CE.1: the menu bar hint's glow in the icon, on a light and a dark menu bar.
@Suite @MainActor struct MenuBarGlowTests {
    /// One 30 x 22 pt status item slot: the menu bar, the template icon in its ink, and the glow
    /// at its strongest, drawn as the menu bar draws them. The icon box is at (6, 2), y up.
    func slot(dark: Bool) -> CGImage? {
        let scale = 2.0, size = CGSize(width: 30, height: 22)
        guard let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(dark ? CGColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1) : CGColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        let icon = CGRect(x: 6, y: 2, width: 18, height: 18)
        context.saveGState()
        context.translateBy(x: icon.minX, y: icon.minY)
        context.addPath(MenuBarGlow.iconPath)
        context.setFillColor(dark ? .white : .black)
        context.fillPath(using: .evenOdd)
        context.restoreGState()
        let view = MenuBarGlow(frame: NSRect(origin: .zero, size: size), icon: icon, breath: 1)
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        view.viewDidChangeEffectiveAppearance()
        view.show(animated: false)
        view.layer?.render(in: context)
        return context.makeImage()
    }

    @Test func theIconGlowsBlueInsideItsSlot() throws {
        let light = try #require(slot(dark: false)), dark = try #require(slot(dark: true))
        // Both side by side, 4 pt apart, for the designer's check.
        let both = try #require(CGContext(data: nil, width: 128, height: 44, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        both.draw(light, in: CGRect(x: 0, y: 0, width: 60, height: 44))
        both.draw(dark, in: CGRect(x: 68, y: 0, width: 60, height: 44))
        if let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"], let image = both.makeImage(),
           let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("menu-bar-glow.png"))
        }
        for (image, dark) in [(light, false), (dark, true)] {
            let bitmap = NSBitmapImageRep(cgImage: image)
            /// The color at (x, y) in points, y down.
            func color(_ x: Double, _ y: Double) throws -> NSColor {
                try #require(bitmap.colorAt(x: Int(x * 2), y: Int(y * 2))?.usingColorSpace(.sRGB))
            }
            // The body, left of the screen cut-out: #3f8de0, or #5aa3f0 on a dark bar.
            let body = try color(6 + 4.5, 11)
            let blue: [Double] = dark ? [90, 163, 240] : [63, 141, 224]
            let got: [Double] = [Double(body.redComponent), Double(body.greenComponent), Double(body.blueComponent)].map { $0 * 255 }
            let off: Double = zip(got, blue).map { abs($0 - $1) }.max() ?? 255
            #expect(off < 12, "body \(body) dark \(dark)")
            // The halo, 1 pt left of the body's edge, is blue.
            let halo = try color(6 + 2.6, 11)
            #expect(halo.blueComponent > halo.redComponent + 0.08, "halo \(halo) dark \(dark)")
            // The slot's corner, far from the icon, keeps the bar's own color.
            let corner = try color(0.5, 0.5)
            #expect(abs(corner.blueComponent - corner.redComponent) < 0.05, "corner \(corner) dark \(dark)")
        }
    }
}
