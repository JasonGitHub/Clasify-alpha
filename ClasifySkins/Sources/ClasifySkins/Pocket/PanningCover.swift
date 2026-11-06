import AppKit
import QuartzCore
import SwiftUI

/// A main menu cover that Core Animation pans. SwiftUI snaps an offset to whole pixels, so a
/// slow pan moved in steps. Core Animation moves the layer below a pixel and filters the image.
/// The cover comes from the skin's `artwork` value; this view only draws it.
struct PanningCover: NSViewRepresentable {
    let image: CGImage
    let scale: Double
    /// Nil: the cover stays still at the center (Reduce Motion).
    let pan: MainArt.Pan?
    /// Seconds since the pan began, at this update. It fixes when the pan began, so a view
    /// update does not restart or jump it.
    let elapsed: Double

    func makeNSView(context: Context) -> PanView { PanView() }

    func updateNSView(_ view: PanView, context: Context) {
        view.update(image: image, scale: scale, pan: pan, elapsed: elapsed)
    }
}

final class PanView: NSView {
    let cover = CALayer()  // internal for the tests
    private var image: CGImage?
    private var scale = 1.0
    private var pan: MainArt.Pan?
    /// When the pan began, in media time.
    private var began: CFTimeInterval = 0
    /// What the layer shows now, so `layout` sets it again only when something changed.
    private var applied: (pan: MainArt.Pan?, size: CGSize, scale: Double)?

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

    func update(image: CGImage, scale: Double, pan: MainArt.Pan?, elapsed: Double) {
        if image !== self.image {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            cover.contents = image
            CATransaction.commit()
            self.image = image
        }
        if pan != self.pan || scale != self.scale {
            self.pan = pan
            self.scale = scale
            began = CACurrentMediaTime() - elapsed
            needsLayout = true
        }
    }

    override func layout() {
        super.layout()
        let size = bounds.size
        if let applied, applied.pan == pan, applied.size == size, applied.scale == scale { return }
        applied = (pan, size, scale)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        cover.bounds = CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale)
        cover.position = center
        cover.removeAnimation(forKey: "pan")
        if let pan, size.width > 0 {
            let move = CABasicAnimation(keyPath: "position.x")
            move.fromValue = center.x + pan.from * size.width
            move.toValue = center.x + pan.to * size.width
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
