import AppKit

/// CLA-163, card CE.1 (390 I and 388), only with `hints.trial` on: the menu bar hint. The icon
/// turns blue, #3f8de0 (#5aa3f0 on a dark menu bar), with a soft halo of #5aa3f0 at 1.5 and 4 pt
/// (0.95 and 0.7) that stays inside the status item. The halo breathes on the button-glow
/// cycle: 2.4 s, 40 % to 100 %. All fades in over 0.6 s and out over 0.45 s. No words. The app
/// puts this view over the icon in the status item's button, so the item keeps its place and
/// its clicks. Core Animation blurs are half the mock's CSS blurs. A small AppKit view, because
/// a status item's button is AppKit.
@MainActor public final class MenuBarGlow: NSView {
    public static let fadeIn = 0.6, fadeOut = 0.45, breath = 2.4
    static let low: Float = 0.4

    /// The menu bar icon (card AN.1, 343 option C) in an 18 pt box, y up: the body with the screen
    /// and the wheel cut out, and the wheel's center button. Fill it even-odd.
    public static let iconPath: CGPath = {
        let path = CGMutablePath()
        path.addRoundedRect(in: CGRect(x: 3.6, y: 1, width: 10.8, height: 16), cornerWidth: 2.4, cornerHeight: 2.4)
        path.addRoundedRect(in: CGRect(x: 5.4, y: 10.1, width: 7.2, height: 5), cornerWidth: 0.7, cornerHeight: 0.7)
        path.addEllipse(in: CGRect(x: 6.1, y: 2.5, width: 5.8, height: 5.8))
        path.addEllipse(in: CGRect(x: 8, y: 4.4, width: 2, height: 2))
        return path
    }()

    private let glow = CALayer()  // fades in and out
    private let fill = CAShapeLayer()
    private let halo = CALayer()  // breathes
    private let near = CAShapeLayer(), far = CAShapeLayer()

    /// `icon` is the 18 pt icon's place in this view. `breath` fixes the halo's strength, for
    /// snapshot tests; nil breathes.
    public init(frame: NSRect, icon: NSRect, breath: Float? = nil) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true  // the halo stays in the status item's slot
        glow.opacity = 0
        layer?.addSublayer(glow)
        for shape in [far, near, fill] {
            shape.path = Self.iconPath
            shape.fillRule = .evenOdd
            shape.frame = icon
        }
        for (shape, blur, strength) in [(far, 2.0, Float(0.7)), (near, 0.75, Float(0.95))] {
            shape.shadowColor = NSColor(srgbRed: 90 / 255, green: 163 / 255, blue: 240 / 255, alpha: 1).cgColor
            shape.shadowOpacity = strength
            shape.shadowRadius = blur
            shape.shadowOffset = .zero
            halo.addSublayer(shape)
        }
        halo.frame = CGRect(origin: .zero, size: frame.size)
        glow.frame = halo.frame
        glow.addSublayer(halo)
        glow.addSublayer(fill)  // over the halo, so the icon is its own blue at every breath
        if let breath {
            halo.opacity = breath
        } else {
            halo.opacity = Self.low
            let breathe = CABasicAnimation(keyPath: "opacity")
            breathe.fromValue = Self.low
            breathe.toValue = 1
            breathe.duration = Self.breath / 2
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            halo.add(breathe, forKey: "breathe")
        }
        paint()
    }

    /// Clicks go through to the status item's button under it.
    public override func hitTest(_ point: NSPoint) -> NSView? { nil }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
    }

    /// The icon's blue for the menu bar under it.
    private func paint() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let blue = dark ? NSColor(srgbRed: 90 / 255, green: 163 / 255, blue: 240 / 255, alpha: 1)
            : NSColor(srgbRed: 63 / 255, green: 141 / 255, blue: 224 / 255, alpha: 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for shape in [far, near, fill] { shape.fillColor = blue.cgColor }
        CATransaction.commit()
    }

    /// The glow fades in, or with `animated` false shows at once (snapshot tests).
    public func show(animated: Bool = true) {
        fade(to: 1, duration: animated ? Self.fadeIn : 0, timing: .easeOut)
    }

    /// The glow fades out, then the view goes away.
    public func hide() {
        fade(to: 0, duration: Self.fadeOut, timing: .easeInEaseOut) { [weak self] in
            guard let self, self.glow.opacity == 0 else { return }  // not if it showed again
            self.removeFromSuperview()
        }
    }

    private func fade(to opacity: Float, duration: Double, timing: CAMediaTimingFunctionName, then done: (@MainActor () -> Void)? = nil) {
        let from = glow.presentation()?.opacity ?? glow.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let done { CATransaction.setCompletionBlock { MainActor.assumeIsolated { done() } } }
        glow.opacity = opacity
        let time = duration * Double(abs(opacity - from))  // a fade cut short goes on from where it is
        if time > 0.01 {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = from
            fade.toValue = opacity
            fade.duration = time
            fade.timingFunction = CAMediaTimingFunction(name: timing)
            glow.add(fade, forKey: "fade")
        }
        CATransaction.commit()
    }
}
