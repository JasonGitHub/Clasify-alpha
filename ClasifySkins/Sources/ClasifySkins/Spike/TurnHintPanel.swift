import AppKit
import SwiftUI

/// CLA-163, card CE.1: the turn hint's own clear window, the size of `TurnHint`. It has no
/// frame, no shadow, and takes no clicks: they go through to the apps behind it. The app places
/// it under the device and keeps it there; the snapshot tests draw this same window.
@MainActor public enum TurnHintPanel {
    /// A new window at `frame` that shows `hint`, and the view that holds it, for its updates.
    public static func make(_ hint: TurnHint, frame: NSRect) -> (NSPanel, NSHostingView<TurnHint>) {
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingView(rootView: hint)
        host.frame = NSRect(origin: .zero, size: TurnHint.size)
        panel.contentView = host
        return (panel, host)
    }
}
