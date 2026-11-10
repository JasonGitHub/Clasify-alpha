import AppKit
import SwiftUI

/// Lets the plain device window (macOS 15 and later) become the key window, so it gets the
/// keyboard (CLA-79). A window with no title bar says it cannot be key. This adds a title bar
/// that does not show: hidden title, clear bar, no buttons, content under the bar. The window
/// keeps its clear background and its shadow setting. Only a window that cannot be key changes.
struct KeyableWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> FixView { FixView() }
    func updateNSView(_ view: FixView, context: Context) {}

    final class FixView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }  // clicks and drags go to SwiftUI

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !window.canBecomeKey else { return }
            let shadow = window.hasShadow
            window.styleMask.insert([.titled, .fullSizeContentView])
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.isHidden = true
            }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = shadow
        }
    }
}
