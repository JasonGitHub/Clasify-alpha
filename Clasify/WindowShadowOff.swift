import AppKit
import SwiftUI

/// CLA-119 (build 258: a pale box of the resting device's shape, with a darker halo, behind
/// the turned 3D device): macOS draws the plain window's own shadow from the window's opaque
/// shape, and it does not make it again while the 3D body turns. The device draws its own
/// shadows (`PocketSkin`'s, and `K3DShadow` while the 3D body shows), so the device window has
/// none. Not the How to Use window: it keeps the standard look. The hook also makes the
/// device window follow the active Space (356).
struct WindowShadowOff: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Hook() }
    func updateNSView(_ view: NSView, context: Context) {}

    final class Hook: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.hasShadow = false
            // Card AN.1, 356: the menu bar icon, the Dock and Cmd+Tab bring myPod to the
            // Space the person is on, at the same place on the screen. macOS never switches
            // the Space to it.
            window?.collectionBehavior.insert(.moveToActiveSpace)
        }

        /// Clicks go through to the device and the window drag.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
