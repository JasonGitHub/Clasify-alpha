import CoreGraphics
import SwiftUI

/// CLA-142 (build 330: after a reset the device opened 207 pt left of the screen center and
/// about 100 pt low, every time): with no saved frame, SwiftUI centered the new window at its
/// own default size (about 900 x 450) and then shrank it to the content, keeping its top-left.
/// The device window now tells macOS its first place: the device, not the window, at the center
/// of the screen's visible area. A saved frame still wins on a normal open.
public enum FirstWindowPlace {
    /// The window's top-left for a window of `window` size whose content (the device) sits inside
    /// `margin`, in `visible` (the display's visible rect, y down, as `DisplayProxy.visibleRect`).
    /// The device's center is at the center of `visible`. On a screen too small for that, the
    /// window is moved in so it stays inside `visible`; a window larger than `visible` starts
    /// at its top-left.
    public static func origin(visible: CGRect, window: CGSize, margin: EdgeInsets) -> CGPoint {
        let device = CGPoint(
            x: margin.leading + (window.width - margin.leading - margin.trailing) / 2,
            y: margin.top + (window.height - margin.top - margin.bottom) / 2)
        let x = visible.midX - device.x, y = visible.midY - device.y
        return CGPoint(
            x: max(visible.minX, min(x, visible.maxX - window.width)),
            y: max(visible.minY, min(y, visible.maxY - window.height)))
    }
}
