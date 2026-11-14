import CoreGraphics
import CoreText
import Foundation
import ImageIO

/// SPIKE (CLA-101): the K.3D.7 textures from the About thread's frozen folder, bundled as they
/// are, 732 x 1226 px (2 per pt): `front-ids.png`, `back-etch.png` and `steel.png`.
///
/// The front's alpha is a material id, not a transparency: 255 wheel, 253 aluminium, 251 LCD,
/// 250 bezel ink, 249 center button. The shader matches it within 0.0018, so the bytes are read
/// as they are in the PNG: no premultiplied alpha and no color conversion.
enum K3DTextures {
    static let width = 732, height = 1226
    /// The LCD (id 251) in the front texture, in px: 600 x 450 from (66, 65).
    static let lcd = (x: 66..<666, y: 65..<515)

    enum Name: String { case front = "k3d-front", back = "k3d-back", steel = "k3d-steel" }

    /// The PNG's RGBA bytes, row by row from the top, as stored: straight alpha, no color
    /// matching. Nil when the file is missing or not 8-bit RGBA with straight alpha.
    static func rgba(_ name: Name) -> [UInt8]? {
        guard let url = Bundle.module.url(forResource: name.rawValue, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        return straight(image)
    }

    /// The image's own decoded bytes when they are 8-bit RGBA with straight alpha last.
    private static func straight(_ image: CGImage) -> [UInt8]? {
        let info = image.bitmapInfo
        guard image.bitsPerComponent == 8, image.bitsPerPixel == 32,
              image.alphaInfo == .last,
              info.intersection(.byteOrderMask) == [] || info.contains(.byteOrder32Big),
              let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data)
        else { return nil }
        let w = image.width, h = image.height, row = image.bytesPerRow
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<(w * 4) { out[y * w * 4 + x] = bytes[y * row + x] }
        }
        return out
    }

    /// The front with a live picture of the device's screen in the LCD (alpha 251). Only the
    /// color changes; every alpha id stays as it is. `screen` is the device drawn at 2x. The
    /// texture's LCD, 600 x 450 px from (66, 65), is where the app's screen is, so each LCD pixel
    /// takes the snapshot's pixel at the same place.
    /// `base` is the bundled front, when the caller has it already.
    static func front(screen: CGImage?, base: [UInt8]? = nil) -> [UInt8]? {
        guard var front = base ?? rgba(.front) else { return nil }
        guard let screen, let live = draw(screen) else { return front }
        // Every id 251 pixel is in this rect: only its 270,000 pixels are looked at, not the
        // texture's 897,432 (build 194 stuttered at the turn's start).
        for y in lcd.y {
            for x in lcd.x {
                let i = (y * width + x) * 4
                guard front[i + 3] == 251 else { continue }
                front[i] = live[i]; front[i + 1] = live[i + 1]; front[i + 2] = live[i + 2]
            }
        }
        return front
    }

    /// The etched back, with the app's real version in the spec table. The frozen art says
    /// "1.0 · Build 161" there: that text is cleared and the version is etched in its place, in
    /// white like the rest of the etch, at the art's size and baseline.
    static func back(version: String) -> [UInt8]? {
        guard var back = rgba(.back) else { return nil }
        // The art's value text is 337 to 415 px across and 942 to 951 px down.
        let clear = (x: 330..<540, y: 936..<958)
        for y in clear.y {
            for x in clear.x { back[(y * width + x) * 4 + 3] = 0 }
        }
        guard let text = etch(version, x: 337, baseline: 952) else { return back }
        for y in clear.y {
            for x in clear.x {
                let i = (y * width + x) * 4
                guard text[i + 3] > 0 else { continue }
                back[i] = 255; back[i + 1] = 255; back[i + 2] = 255; back[i + 3] = text[i + 3]
            }
        }
        return back
    }

    /// The app's version for the back: "1.0 · Build 162", or the short version alone when the
    /// bundle has no build number, as in tests.
    static var version: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(Labels.version) · Build \($0)" } ?? Labels.version
    }

    /// One line of white text on a clear 732 x 1226 picture, premultiplied, rows from the top.
    /// The art's text is 14 px (7 pt): its capitals are 10 px high.
    private static func etch(_ text: String, x: Double, baseline: Double) -> [UInt8]? {
        var out = [UInt8](repeating: 0, count: width * height * 4)
        let done = out.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            let font = CTFontCreateUIFontForLanguage(.system, 14, nil) ?? CTFontCreateWithName("Helvetica" as CFString, 14, nil)
            let string = NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
            ])
            // Core Graphics draws with y up: a row y px from the top is at height - y.
            context.textPosition = CGPoint(x: x, y: Double(height) - baseline)
            CTLineDraw(CTLineCreateWithAttributedString(string as CFAttributedString), context)
            return true
        }
        return done ? out : nil
    }

    /// The image drawn into 732 x 1226 RGBA bytes. The screen is opaque, so premultiplied
    /// bytes are its colors.
    private static func draw(_ image: CGImage) -> [UInt8]? {
        var out = [UInt8](repeating: 0, count: width * height * 4)
        let done = out.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            // Core Graphics draws with y up: the top row of the image is the first row of bytes.
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return done ? out : nil
    }
}
