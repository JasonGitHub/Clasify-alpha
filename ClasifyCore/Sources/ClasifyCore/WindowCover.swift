/// Card AN.1 (Jason, 13:10 JST 11-19): a partly covered myPod counts as not shown, so a click
/// on the menu bar icon brings it to the front. The device sits in a window with a wide clear
/// margin, so only a window over the device itself counts, not one over the margin. Plain
/// numbers here, so the rule is tested on Linux; the app reads the windows with
/// `CGWindowListCopyWindowInfo`.
public enum WindowCover {
    /// A rectangle in the window server's coordinates: the origin is the top left of the main
    /// screen, and y grows down.
    public struct Box: Equatable, Sendable {
        public var x, y, width, height: Double
        public init(x: Double, y: Double, width: Double, height: Double) {
            (self.x, self.y, self.width, self.height) = (x, y, width, height)
        }

        /// True when the two share an area, not only an edge.
        func overlaps(_ o: Box) -> Bool {
            min(x + width, o.x + o.width) > max(x, o.x) && min(y + height, o.y + o.height) > max(y, o.y)
        }
    }

    /// Another app's window, or one of ours, on screen above the device window.
    public struct Window: Sendable {
        public var bounds: Box
        public var layer: Int
        public var alpha: Double
        public init(bounds: Box, layer: Int, alpha: Double) {
            (self.bounds, self.layer, self.alpha) = (bounds, layer, alpha)
        }
    }

    /// The device inside its window. `frame` is the AppKit window frame (y grows up from the
    /// bottom of the main screen, `mainHeight` high). The insets are the clear margin.
    public static func device(frame: Box, mainHeight: Double,
                              top: Double, leading: Double, bottom: Double, trailing: Double) -> Box {
        let y = mainHeight - (frame.y + frame.height)  // the window's top, y down
        return Box(x: frame.x + leading, y: y + top,
                   width: frame.width - leading - trailing, height: frame.height - top - bottom)
    }

    /// True when a normal visible window above covers any part of the device. Menus, the menu
    /// bar and other layers do not count, and neither does a fully clear window.
    public static func isCovered(_ device: Box, by above: [Window]) -> Bool {
        above.contains { $0.layer == 0 && $0.alpha > 0 && $0.bounds.overlaps(device) }
    }
}
