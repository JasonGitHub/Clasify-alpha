import CoreGraphics
import CoreText
import Foundation

/// CLA-105 B3: the take-apart parts' printed textures, drawn in code as the mock does
/// (K.3D.8 `k3d_src3.js`, Jason 23:43 JST 11-13: our own names only, no photo, no other
/// company's names or marks). Each is RGBA bytes, row 0 at the top, as the mock's canvas.
/// - `label` (the mock's `tl`, 1024 x 1024): the drive label, the battery print, three chip
///   tops and the ribbon print.
/// - `board` (`tp`, 2048 x 1024, half the mock's 4096 x 2048): the logic board's white print, wheel side left, chip side
///   right. Blue marks where no loose part may sit under the text.
/// - `parts` (`tq`, 2048 x 2048): the drive board's print, the shell floor's etched text, the
///   shield's stamped text (red), and three strips: frame, wheel back, plate back.
/// They are made off the main actor when the device starts to come apart, kept in memory
/// only, and released when it is closed again (`K3DRenderer.preparePrints`).
enum K3DPrints {
    static let labelSize = 1024, boardSize = (w: 2048, h: 1024), partsSize = 2048

    /// The three textures' bytes. Plain arrays, so they are made off the main actor.
    struct Bytes: Sendable {
        let label: [UInt8], board: [UInt8], parts: [UInt8]
    }

    /// All three, or nil if a canvas cannot be made.
    static func all() -> Bytes? {
        guard let label = label(), let board = board(), let parts = parts() else { return nil }
        return Bytes(label: label, board: board, parts: parts)
    }

    static func label() -> [UInt8]? {
        guard let x = Canvas(width: labelSize, height: labelSize) else { return nil }
        x.fill("#f1f1ee")
        x.fillRect(0, 0, 640, 800)
        x.fill("#16171a")
        x.stroke("#16171a")
        x.lineWidth = 2
        x.strokeRect(34, 30, 572, 108)
        x.font(500, 19)
        x.text("• Read the playlist before operation.", 48, 60)
        x.text("• Back up your Liked Songs regularly.", 48, 88)
        x.text("• CappyAI is not responsible for songs stuck in your head.", 48, 116)
        x.font(900, 66)
        x.text("CAPPYAI", 34, 222)
        x.font(700, 30)
        x.text("CP8022CAA", 350, 200)
        x.text("80GB", 540, 200)
        x.font(700, 20)
        x.text("DISK DRIVE", 36, 252)
        x.font(700, 27)
        x.text("HDD1805  P  ZK01   DC 3.3V   500mA", 34, 292)
        x.font(500, 18)
        x.text("S/N  61B1CAPY7T5     A0/CA10QA0V91DA", 34, 320)
        x.barcode(from: 34, to: 606, y: 336, height: 44, count: 150) { 1 + Double(($0 * 7 + 3) % 4) }
        for (cx, t) in [(70.0, "♥"), (150, "♪"), (230, "SI")] {
            x.lineWidth = 3
            x.circle(cx, 440, 30, fill: false)
            x.font(700, t.count > 1 ? 24 : 32)
            x.text(t, cx, t.count > 1 ? 449 : 452, align: .center)
        }
        x.font(700, 20)
        x.text("PLAYS: ALL YOUR LIKED SONGS", 290, 430)
        x.font(500, 18)
        x.text("RATED: CHILL", 290, 458)
        x.lineWidth = 2
        x.strokeRect(34, 500, 572, 96)
        x.font(500, 17)
        x.text("This drive holds no music. It plays your playlists", 46, 530)
        x.text("and Liked Songs. No real capybaras inside.", 46, 554)
        x.text("Do not drop. Do not feed.", 46, 578)
        x.font(900, 34)
        x.text("CappyAI", 34, 660)
        x.barcode(from: 250, to: 606, y: 628, height: 40, count: 170) { 1 + Double(($0 * 5 + 1) % 3) }
        x.font(500, 17)
        x.text("L8006  SAPPA  455-1395A   A0571L5HCYLMA4", 34, 704)
        x.font(700, 22)
        x.text("CAPPYAI LTD", 34, 750)
        x.font(500, 18)
        x.text("DESIGNED BY CAPPYAI", 420, 750)
        x.font(500, 15)
        x.text("© 2026 CappyAI Ltd", 34, 778)
        // The battery print (Jason 23:59 JST: the real print is black).
        x.fill("#215cc7")
        x.fillRect(0, 820, 612, 204)
        x.fill("#0a0d14")
        x.font(900, 40)
        x.text("BATTERY PACK", 306, 866, align: .center)
        x.font(700, 24)
        x.text("Li-ion Polymer   3.7V   850mAh   3.1Wh", 306, 900, align: .center)
        x.font(500, 19)
        x.text("Model CP-B01     CappyAI Ltd", 306, 928, align: .center)
        x.font(500, 17)
        x.text("CAUTION: do not open, crush, heat above 60\u{00b0}C or put in fire.", 306, 956, align: .center)
        x.text("Charge with songs only. Keep away from real capybaras.", 306, 980, align: .center)
        x.font(700, 18)
        x.text("S/N CP61B1-7T5-0042      Designed by CappyAI", 306, 1008, align: .center)
        chipTops(x)
        ribbonPrint(x)
        return x.bytes()
    }

    /// Three chip tops, 384 x 256 each, at (640, 256 k).
    private static func chipTops(_ x: Canvas) {
        let chips: [[(String, Int, Double, Double)]] = [
            [("CappyAI", 600, 60, 118), ("CP7-0842", 500, 46, 180), ("A1 2611 REV C", 400, 30, 232), ("CAPYBARA CORE", 400, 26, 276)],
            [("CAPPYAI", 600, 44, 112), ("K9-SONGS-30G", 500, 40, 168), ("2611 B2", 400, 32, 218), ("LOT 0842-7", 400, 28, 264)],
            [("CP", 700, 96, 170), ("4412", 500, 64, 244)],
        ]
        for (k, lines) in chips.enumerated() {
            x.save()
            x.translate(640, Double(k) * 256)
            x.scale(1, 256.0 / 384)
            x.fill("#1b1c1e")
            x.fillRect(0, 0, 384, 384)
            x.stroke("#303236")
            x.lineWidth = 3
            x.strokeRect(14, 14, 356, 356)
            x.fill("#8d9197")
            for (t, w, size, y) in lines {
                x.font(w, size)
                x.text(t, 192, y, align: .center)
            }
            x.fill("#2e3034")
            x.circle(52, 330, 15, fill: true)
            x.stroke("#44474c")
            x.lineWidth = 2
            x.circle(52, 330, 15, fill: false)
            x.restore()
        }
    }

    /// The shell ribbon's print: four white lines on black, 384 x 64 each, at (640, 768 + 64 k).
    private static func ribbonPrint(_ x: Canvas) {
        x.fill("#000000")
        x.fillRect(640, 768, 384, 256)
        x.fill("#ffffff")
        for (k, (t, length)) in [("CP1-0399-01", 74.0), ("CAPPYAI LTD \u{00a9} 2026", 140), ("Designed by CappyAI", 130), ("CP2-0371", 75)].enumerated() {
            x.save()
            x.translate(640, 768 + Double(k) * 64)
            let sx = 60 / length
            x.scale(sx, 1)
            x.font(600, 40)
            x.text(t, 192 / sx, 46, align: .center)
            x.restore()
        }
    }

    /// One line of print: font, text, where its baseline starts, and its alignment.
    struct Item {
        let weight: Int, size: Double, text: String, x: Double, y: Double, align: Canvas.Align
    }

    /// The mock's `flush`: a blue keep-out box round each item, then the white text over them.
    private static func flush(_ x: Canvas, _ items: [Item]) {
        x.fill("#0000ff")
        for item in items {
            x.font(item.weight, item.size)
            let m = x.measure(item.text)
            let x0 = item.align == .center ? item.x - m / 2 : item.align == .right ? item.x - m : item.x
            x.fillRect(x0 - 1.5, item.y - item.size - 1, m + 3, item.size + 2.6)
        }
        x.fill("#ffffff")
        for item in items {
            x.font(item.weight, item.size)
            x.text(item.text, item.x, item.y, align: item.align)
        }
    }

    /// The mock's `T`: an item at board point (X, Y), drawn at (X, -Y).
    private static func at(_ weight: Int, _ size: Double, _ text: String, _ px: Double, _ py: Double, _ align: Canvas.Align = .left) -> Item {
        Item(weight: weight, size: size, text: text, x: px, y: -py, align: align)
    }

    /// The mock's `L`: lines from (X, Y) down, `dy` apart.
    private static func lines(_ weight: Int, _ size: Double, _ texts: [String], _ px: Double, _ py: Double, _ dy: Double) -> [Item] {
        texts.enumerated().map { at(weight, size, $0.element, px, py - Double($0.offset) * dy) }
    }

    static func board() -> [UInt8]? {
        guard let x = Canvas(width: boardSize.w, height: boardSize.h) else { return nil }
        x.fill("#000000")
        x.fillRect(0, 0, Double(boardSize.w), Double(boardSize.h))
        // Half the mock's 4096 x 2048: 3.2 px per pt, still above the 2 px per pt on screen.
        let half = Double(boardSize.w / 2), sx = half / 324, sy = Double(boardSize.h) / 276
        // The wheel side, in board points (x, -y).
        x.setTransform(sx, sy, 162 * sx, -14 * sy)
        var items: [Item] = [at(800, 8.2, "CAPPYAI", -145, -92), at(600, 4.3, "\u{00a9}2026  CP-2168-04", -145, -99.5)]
        items += lines(600, 3.7, ["R218 C182", "R223 C181", "Q3  XW26", "CP-A  01"], 24.5, -42, 5.4)
        items += lines(600, 3.7, ["R107 R252", "R220 C132", "CAPPYAI CORE", "R176 R180", "CP7-0842 B"], -58, -182, 5.4)
        items += lines(600, 3.7, ["C51 R14 L10 XW15 R110", "R120 R116 R121 C62", "DESIGNED BY CAPPYAI"], 43, -237.5, 5.4)
        items += lines(600, 3.7, ["C58 R214", "C171", "C174", "C61 C179", "C172 XW57"], 54, -170, 5.4)
        items += lines(600, 3.7, ["R174 R122", "R178 Q1 Q2", "XW38 XW42", "C224 R219"], -150, -178, 5.4)
        items += [
            at(700, 4.2, "S2 MENU", -20, -51, .right), at(700, 4.2, "S3 PREV", -78, -151, .center),
            at(700, 4.2, "S4 NEXT", 78, -151, .center), at(700, 4.2, "S5 PLAY", 20.5, -206.5),
            at(700, 3.5, "S1 SELECT", 0, -151.5, .center),
            at(600, 3.3, "ZT1", -47.3, -128.2, .center), at(600, 3.3, "ZT2", 47.3, -128.2, .center),
        ]
        for (t, px, py) in [("ZH1", -88.0, -41.0), ("ZH2", 74, -41), ("FD1", 43, -76), ("FD2", -102, -281), ("SP4", 118, -190.5),
                            ("SP3", 118, -226.5), ("U20", 104, -22), ("U31", -158, -268), ("NO REAL CAPYBARAS", 106, -160),
                            ("HF / CP1", -156, -110)] {
            items.append(at(600, 3.7, t, px, py))
        }
        flush(x, items)
        x.lineWidth = 0.5
        x.stroke("#ffffff")
        x.strokeRect(-157.5, 106, 26, 6.5)
        // The chip side, as seen from the back (X = -x).
        x.setTransform(sx, sy, half + 162 * sx, -14 * sy)
        items = [at(800, 7.4, "CAPPYAI", -152, -25), at(600, 3.7, "CP-2168-04  SIDE B", 78, -22)]
        for (t, px, py) in [("U1", -148.0, -143.2), ("U2", -56, -140.2), ("U3", 99, -162.2), ("U4", -46, -72.2), ("U5", 36, -171.2)] {
            items.append(at(600, 3.7, t, px, py))
        }
        items += [
            at(700, 4.2, "J3 DISPLAY", 16, -121.5), at(700, 4.2, "J2 DRIVE", -31, -224.5), at(700, 4.2, "J1 DOCK", -58, -281, .right),
            at(700, 4.2, "J6 WHEEL", 158, -68.5, .right), at(700, 4.2, "J5 AUDIO", -126, -73), at(700, 4.2, "J4 BATT", 115, -262, .right),
            at(600, 3.7, "L1 4R7", 117, -224, .right),
        ]
        for (t, px, py) in [("Y1", -138.0, -214.2), ("C229", 61, -238), ("TP1", -25, -129.5), ("TP2", 15, -132.5), ("RATED: CHILL", 100, -104),
                            ("DO NOT FEED", 100, -110), ("MADE WITH CARE BY CAPPYAI", -150, -268)] {
            items.append(at(600, 3.7, t, px, py))
        }
        flush(x, items)
        x.polyline([(-160, 138), (-62, 138), (-62, 208)])
        x.polyline([(92, 212), (92, 118), (160, 118)])
        x.polyline([(10, 30), (10, 60), (-60, 60)])
        return x.bytes()
    }

    static func parts() -> [UInt8]? {
        guard let x = Canvas(width: partsSize, height: partsSize) else { return nil }
        x.fill("#000000")
        x.fillRect(0, 0, 2048, 2048)
        // The drive board at (0, 0), 4 px per pt, in drive points (x, -y).
        x.setTransform(4, 4, 624, 512)
        flush(x, [
            at(800, 11, "CAPPYAI", -132, -244), at(600, 5, "CP8022 DRIVE BOARD  REV C", -132, -254),
            at(700, 5.8, "U1 MOTOR CTRL", -60, -115.5), at(700, 5.8, "U2 SONGS", 64, -85.5), at(600, 5, "Y1", -122, -93.5),
            at(600, 5, "M1", 17, -78), at(600, 5, "C1-C6", 42, -206), at(600, 5, "SPINS ONLY FOR GOOD SONGS", -116, -82),
            at(700, 5.8, "DO NOT COVER THIS HOLE", -103, 94), at(700, 5.8, "CP8022CAA  80GB", 68, -20), at(600, 5, "HANDLE WITH CARE", 68, -28),
        ])
        x.stroke("#ffffff")
        x.lineWidth = 0.7
        for r in [58.4, 16.4, 44] { x.circle(0, -34, r, fill: false) }
        // The shell floor at (1248, 0), 2.5 px per pt: the etched date code down the middle, a small note.
        x.setTransform(2.5, 2.5, 1248 + 400, 725)
        x.fill("#ffffff")
        x.save()
        x.translate(-62, 0)
        x.rotate(.pi / 2)
        x.font(500, 12)
        x.text("CP-HBS-2026-11-13", -122, 4)
        x.restore()
        x.font(700, 7)
        x.text("DESIGNED BY CAPPYAI", -108, 232)
        x.font(500, 5.4)
        x.text("INSIDE: 1 BATTERY, 1 DRIVE, 0 CAPYBARAS", -108, 242)
        // The shield plate's back at (1248, 1456), 2.4 px per pt, as seen from the back: red = stamped text.
        x.setTransform(2.4, 2.4, 1248 + 158 * 2.4, 1456 + 284 * 2.4)
        x.fill("#ff0000")
        x.font(700, 7.5)
        x.text("CP-LCD SHIELD  01", -138, -262)
        x.font(500, 5.6)
        x.text("DO NOT BEND.  DO NOT FEED.", -138, -253)
        x.text("2.5 IN  320 x 240  ALL YOUR COVERS", -138, -52)
        // Three strips: the frame's cross bar (3.75 px per pt), the wheel's back and the plate's back (6 px per pt).
        x.fill("#ffffff")
        x.setTransform(3.75, 3.75, 166 * 3.75, 1664 + 34 * 3.75)
        x.font(700, 6.6)
        x.text("CP-FRAME 01   Mg", -158, -25.6)
        x.text("CAST WITH CARE", 58, -25.6)
        x.setTransform(6, 6, 300, 1360)
        x.font(700, 6.2)
        x.text("CP-WHEEL 01   >PC+ABS<", 0, 67.6, align: .center)
        x.setTransform(6, 6, 600, 278)
        x.text("CP-PLATE 01    ANODIZED ALUMINIUM    THIS SIDE IN", 0, 260.4, align: .center)
        // K.3D.11 (CLA-129): the stamp on the jack can and the print on the jack chip, in the shell
        // floor's place: green = read only there.
        x.setTransform(2.5, 2.5, 1648, 725)
        x.fill("#00ff00")
        x.font(800, 7.5)
        x.text("CJ-01", 115, -262, align: .center)
        x.font(700, 4.2)
        x.text("CAPPYAI", 115, -254, align: .center)
        x.font(700, 5.2)
        x.text("CP7", 115, -201, align: .center)
        x.text("J01", 115, -194, align: .center)
        return x.bytes()
    }
}

/// A small 2D canvas with the HTML canvas's coordinates (y down, text on its alphabetic
/// baseline) over a Core Graphics bitmap, for the prints above.
final class Canvas {
    enum Align { case left, center, right }
    let context: CGContext
    let width: Int, height: Int
    private var font: CTFont
    private var fillColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    var lineWidth: CGFloat = 1 { didSet { context.setLineWidth(lineWidth) } }

    init?(width: Int, height: Int) {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        else { return nil }
        self.context = context
        self.width = width
        self.height = height
        font = CTFontCreateWithName("Helvetica" as CFString, 10, nil)
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.setLineWidth(1)
    }

    static func color(_ hex: String) -> CGColor {
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0
        let r = CGFloat((v >> 16) & 0xff) / 255, g = CGFloat((v >> 8) & 0xff) / 255, b = CGFloat(v & 0xff) / 255
        return CGColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    func fill(_ hex: String) {
        fillColor = Self.color(hex)
        context.setFillColor(fillColor)
    }

    func stroke(_ hex: String) { context.setStrokeColor(Self.color(hex)) }

    /// The canvas font `weight size px Helvetica`: Helvetica has a regular and a bold face,
    /// and a browser picks the bold face from weight 600.
    func font(_ weight: Int, _ size: Double) {
        font = CTFontCreateWithName((weight >= 600 ? "Helvetica-Bold" : "Helvetica") as CFString, CGFloat(size), nil)
    }

    private func line(_ text: String) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): fillColor,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    func measure(_ text: String) -> Double { CTLineGetTypographicBounds(line(text), nil, nil, nil) }

    func text(_ text: String, _ x: Double, _ y: Double, align: Align = .left) {
        let l = line(text)
        let w = CTLineGetTypographicBounds(l, nil, nil, nil)
        let x0 = align == .center ? x - w / 2 : align == .right ? x - w : x
        context.textPosition = CGPoint(x: x0, y: y)
        CTLineDraw(l, context)
    }

    func fillRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) { context.fill(CGRect(x: x, y: y, width: w, height: h)) }

    func strokeRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) { context.stroke(CGRect(x: x, y: y, width: w, height: h)) }

    func circle(_ x: Double, _ y: Double, _ r: Double, fill: Bool) {
        let rect = CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)
        if fill { context.fillEllipse(in: rect) } else { context.strokeEllipse(in: rect) }
    }

    func polyline(_ points: [(Double, Double)]) {
        guard let first = points.first else { return }
        context.beginPath()
        context.move(to: CGPoint(x: first.0, y: first.1))
        for p in points.dropFirst() { context.addLine(to: CGPoint(x: p.0, y: p.1)) }
        context.strokePath()
    }

    /// The mock's bar code: bars `width(i)` wide, 1 apart, every other one filled.
    func barcode(from x0: Double, to x1: Double, y: Double, height: Double, count: Int, width: (Int) -> Double) {
        var bx = x0
        for i in 0..<count where bx < x1 {
            let w = width(i)
            if i % 2 == 0 { fillRect(bx, y, w, height) }
            bx += w + 1
        }
    }

    func save() { context.saveGState() }
    func restore() { context.restoreGState() }
    func translate(_ x: Double, _ y: Double) { context.translateBy(x: x, y: y) }
    func scale(_ x: Double, _ y: Double) { context.scaleBy(x: x, y: y) }
    func rotate(_ a: Double) { context.rotate(by: a) }

    /// The canvas's `setTransform(sx, 0, 0, sy, tx, ty)`, from the canvas's own pixels.
    func setTransform(_ sx: Double, _ sy: Double, _ tx: Double, _ ty: Double) {
        context.concatenate(context.ctm.inverted())
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.concatenate(CGAffineTransform(a: sx, b: 0, c: 0, d: sy, tx: tx, ty: ty))
    }

    /// The pixels, RGBA, row 0 at the top, alpha premultiplied.
    func bytes() -> [UInt8]? {
        guard let data = context.data else { return nil }
        let count = width * height * 4
        return [UInt8](UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: count))
    }
}
