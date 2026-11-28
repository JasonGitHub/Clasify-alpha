#if os(macOS)
import AppKit
import QuartzCore
import SwiftUI

/// A main menu cover that Core Animation pans. SwiftUI snaps an offset to whole pixels, so a
/// slow pan moved in steps. Core Animation moves the layer below a pixel and filters the image.
/// The cover comes from the skin's `artwork` value; this view only draws it.
struct PanningCover: NSViewRepresentable {
    let image: CGImage
    /// The side of the square cover in points, centered in the view.
    let side: Double
    /// Nil: the cover stays still at the center (Reduce Motion).
    let pan: MainArt.Pan?
    /// Seconds since the pan began, at this update. It fixes when the pan began, so a view
    /// update does not restart or jump it.
    let elapsed: Double

    func makeNSView(context: Context) -> PanView { PanView() }

    func updateNSView(_ view: PanView, context: Context) {
        view.update(image: image, side: side, pan: pan, elapsed: elapsed)
    }
}

final class PanView: NSView {
    let cover = CALayer()  // internal for the tests
    private var image: CGImage?
    private var side = 0.0
    private var pan: MainArt.Pan?
    /// When the pan began, in media time.
    private var began: CFTimeInterval = 0
    /// What the layer shows now, so `layout` sets it again only when something changed.
    private var applied: (pan: MainArt.Pan?, size: CGSize, side: Double)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        cover.contentsGravity = .resizeAspectFill
        cover.magnificationFilter = .linear
        cover.minificationFilter = .linear
        cover.masksToBounds = true
        layer?.addSublayer(cover)
    }

    required init?(coder: NSCoder) { nil }

    /// The cover takes no clicks: the click wheel and the list get them.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(image: CGImage, side: Double, pan: MainArt.Pan?, elapsed: Double) {
        if image !== self.image {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            cover.contents = image
            CATransaction.commit()
            self.image = image
        }
        if pan != self.pan || side != self.side {
            self.pan = pan
            self.side = side
            began = CACurrentMediaTime() - elapsed
            needsLayout = true
        }
    }

    override func layout() {
        super.layout()
        let size = bounds.size
        if let applied, applied.pan == pan, applied.size == size, applied.side == side { return }
        applied = (pan, size, side)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        cover.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        cover.position = center
        cover.removeAnimation(forKey: "pan")
        if let pan, size.width > 0 {
            // The layer's y goes up, and a positive pan `y` moves the cover down.
            let point = { (o: MainArt.Offset) in NSValue(point: NSPoint(x: center.x + o.x, y: center.y - o.y)) }
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
}
#else
import SwiftUI

/// CLA-202: on iOS for now, a still cover at the center. The iOS pan comes in a later change.
struct PanningCover: View {
    let image: CGImage
    let side: Double
    let pan: MainArt.Pan?
    let elapsed: Double

    var body: some View {
        Image(decorative: image, scale: 1).resizable().interpolation(.high)
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
