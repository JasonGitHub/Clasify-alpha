import QuartzCore
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A main menu cover that Core Animation pans. SwiftUI snaps an offset to whole pixels, so a
/// slow pan moved in steps. Core Animation moves the layer below a pixel and filters the image.
/// The cover comes from the skin's `artwork` value; this view only draws it.
/// CLA-202: an AppKit view on the Mac and a UIKit view on iOS, with the same `CoverPan`.
struct PanningCover {
    let image: CGImage
    /// The side of the square cover in points, centered in the view.
    let side: Double
    /// Nil: the cover stays still at the center (Reduce Motion).
    let pan: MainArt.Pan?
    /// Seconds since the pan began, at this update. It fixes when the pan began, so a view
    /// update does not restart or jump it.
    let elapsed: Double
}

#if os(macOS)
extension PanningCover: NSViewRepresentable {
    func makeNSView(context: Context) -> PanView { PanView() }

    func updateNSView(_ view: PanView, context: Context) {
        view.update(image: image, side: side, pan: pan, elapsed: elapsed)
    }
}

final class PanView: NSView {
    private let coverPan: CoverPan
    var cover: CALayer { coverPan.cover }  // internal for the tests

    override init(frame: NSRect) {
        coverPan = CoverPan()
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.addSublayer(coverPan.cover)
    }

    required init?(coder: NSCoder) { nil }

    /// The cover takes no clicks: the click wheel and the list get them.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(image: CGImage, side: Double, pan: MainArt.Pan?, elapsed: Double) {
        if coverPan.update(image: image, side: side, pan: pan, elapsed: elapsed) { needsLayout = true }
    }

    override func layout() {
        super.layout()
        coverPan.layout(in: bounds.size, yUp: true)
    }
}
#else
extension PanningCover: UIViewRepresentable {
    func makeUIView(context: Context) -> PanView { PanView() }

    func updateUIView(_ view: PanView, context: Context) {
        view.update(image: image, side: side, pan: pan, elapsed: elapsed)
    }
}

final class PanView: UIView {
    private let coverPan: CoverPan

    override init(frame: CGRect) {
        coverPan = CoverPan()
        super.init(frame: frame)
        layer.masksToBounds = true
        layer.addSublayer(coverPan.cover)
        isUserInteractionEnabled = false  // the click wheel and the list get the touches
    }

    required init?(coder: NSCoder) { nil }

    func update(image: CGImage, side: Double, pan: MainArt.Pan?, elapsed: Double) {
        if coverPan.update(image: image, side: side, pan: pan, elapsed: elapsed) { setNeedsLayout() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        coverPan.layout(in: bounds.size, yUp: false)
    }
}
#endif

/// CLA-202: the cover layer and its pan, the same on the Mac and on iOS. Only the y direction
/// of the host view's layer differs.
@MainActor final class CoverPan {
    let cover = CALayer()
    private var image: CGImage?
    private var side = 0.0
    private var pan: MainArt.Pan?
    /// When the pan began, in media time.
    private var began: CFTimeInterval = 0
    /// What the layer shows now, so `layout` sets it again only when something changed.
    private var applied: (pan: MainArt.Pan?, size: CGSize, side: Double)?

    init() {
        cover.contentsGravity = .resizeAspectFill
        cover.magnificationFilter = .linear
        cover.minificationFilter = .linear
        cover.masksToBounds = true
    }

    /// Takes the view's values. True when the layer needs a new layout.
    func update(image: CGImage, side: Double, pan: MainArt.Pan?, elapsed: Double) -> Bool {
        if image !== self.image {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            cover.contents = image
            CATransaction.commit()
            self.image = image
        }
        guard pan != self.pan || side != self.side else { return false }
        self.pan = pan
        self.side = side
        began = CACurrentMediaTime() - elapsed
        return true
    }

    /// Centers the cover in a host of `size` and starts its pan. `yUp`: the host layer's y goes
    /// up (AppKit), else down (UIKit).
    func layout(in size: CGSize, yUp: Bool) {
        if let applied, applied.pan == pan, applied.size == size, applied.side == side { return }
        applied = (pan, size, side)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        cover.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        cover.position = center
        cover.removeAnimation(forKey: "pan")
        if let pan, size.width > 0 {
            // A positive pan `y` moves the cover down.
            let point = { (o: MainArt.Offset) in Self.value(CGPoint(x: center.x + o.x, y: yUp ? center.y - o.y : center.y + o.y)) }
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = point(pan.from)
            move.toValue = point(pan.to)
            move.duration = MainArt.slot + MainArt.fade
            move.beginTime = cover.convertTime(began, from: nil)
            move.timingFunction = CAMediaTimingFunction(name: .linear)
            move.fillMode = .both  // before the start, at `from`; after the end, at `to`
            move.isRemovedOnCompletion = false
            if pan.reverses {
                move.autoreverses = true
                move.repeatCount = .infinity
            }
            cover.add(move, forKey: "pan")
        }
        CATransaction.commit()
    }

    private static func value(_ point: CGPoint) -> NSValue {
        #if os(macOS)
        return NSValue(point: point)
        #else
        return NSValue(cgPoint: point)
        #endif
    }
}
