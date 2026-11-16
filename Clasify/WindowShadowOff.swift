import AppKit
import SwiftUI

/// CLA-119 (build 258: a pale box of the resting device's shape, with a darker halo, behind
/// the turned 3D device): macOS draws the plain window's own shadow from the window's opaque
/// shape, and it does not make it again while the 3D body turns. The device draws its own
/// shadows (`PocketSkin`'s, and `K3DShadow` while the 3D body shows), so the device window has
/// none. Not the How to Use window: it keeps the standard look.
struct WindowShadowOff: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Hook() }
    func updateNSView(_ view: NSView, context: Context) {}

    final class Hook: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.hasShadow = false
        }

        /// Clicks go through to the device and the window drag.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
