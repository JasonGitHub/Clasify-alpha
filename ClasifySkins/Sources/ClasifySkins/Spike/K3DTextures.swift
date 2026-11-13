import CoreGraphics
import Foundation
import ImageIO

/// SPIKE (CLA-101): the K.3D.1 textures, bundled as the mock has them, 732 x 1226 px (2 per pt).
///
/// The front's alpha is a material id, not a transparency: 255 wheel, 253 aluminium, 251 LCD,
/// 250 bezel under the glass, 249 center button. The shader matches it within 0.0018, so the
/// bytes are read as they are in the PNG: no premultiplied alpha and no color conversion.
enum K3DTextures {
    static let width = 732, height = 1226

    enum Name: String { case front = "k3d-front3d", back = "k3d-back-L3", steel = "k3d-steel" }

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
    /// color changes; every alpha id stays as it is. `screen` is the device drawn at 2x.
    static func front(screen: CGImage?) -> [UInt8]? {
        guard var front = rgba(.front) else { return nil }
        guard let screen, let live = draw(screen) else { return front }
        // The mock's LCD is 600 x 452 px from (66, 66); the app's screen is 600 x 450 px from
        // (66, 64.8). Each LCD row reads the matching row of the app's screen.
        for y in 66..<518 {
            let sy = min(height - 1, Int((64.8 + Double(y - 66) * 450 / 452).rounded()))
            for x in 66..<666 {
                let i = (y * width + x) * 4, s = (sy * width + x) * 4
                guard front[i + 3] == 251 else { continue }
                front[i] = live[s]; front[i + 1] = live[s + 1]; front[i + 2] = live[s + 2]
            }
        }
        return front
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
