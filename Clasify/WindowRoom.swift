import AppKit
import ClasifySkins
import SwiftUI

/// CLA-119 (build 258: the top of the turned device cut off): while the 3D body may show, the
/// device window gets `K3DRoom.extra` round today's margins (its top cut by `fit`), so the body is never cut at the
/// window's edge. At rest on the front the window is as before, so the device still reaches the
/// menu bar (CLA-94).
///
/// The skin pads its content by `room`. In the same update this hook moves the window's edges out
/// (or in) by the change, so the device stays at the same point on the screen, and the window is
/// already the size SwiftUI asks for. The window's clear area passes clicks through to the apps
/// behind it, as the margins do.
struct WindowRoom: NSViewRepresentable {
    let room: EdgeInsets
    /// This skin's own device window, for `fit` (more than one device window can be open).
    let window: WindowRef

    func makeNSView(context: Context) -> NSView {
        let hook = Hook()
        hook.ref = window
        hook.room = room  // the window is made with this room
        return hook
    }

    /// CLA-119 (build 269: the device jumped down when a spin started after a move up): macOS
    /// keeps a window's top under the menu bar, and moves a taller window down. So the top room is
    /// only the room up to the top of the screen's visible area: nothing could show above it.
    /// The sides and the bottom keep their room (macOS does not move a window for them). Read once
    /// as the 3D body starts; the shrink takes the same room away, so the device comes back exactly.
    @MainActor static func fit(_ room: EdgeInsets, in window: NSWindow?) -> EdgeInsets {
        // No window or screen: no top room, so macOS has nothing to move.
        K3DRoom.fit(room, windowTop: window?.frame.maxY ?? 0, visibleTop: window?.screen?.visibleFrame.maxY ?? -.infinity)
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let hook = view as? Hook, hook.room != room else { return }
        let old = hook.room
        hook.room = room
        // No window yet: SwiftUI makes it at the content's size, room included.
        guard let window = view.window else { return }
        window.setFrame(Self.frame(window.frame, from: old, to: room), display: false)
    }

    /// The window's frame (AppKit: the origin at the bottom left) with its edges moved by the
    /// change in room.
    static func frame(_ frame: NSRect, from old: EdgeInsets, to new: EdgeInsets) -> NSRect {
        let top = new.top - old.top, left = new.leading - old.leading
        let bottom = new.bottom - old.bottom, right = new.trailing - old.trailing
        return NSRect(
            x: frame.minX - left, y: frame.minY - bottom,
            width: frame.width + left + right, height: frame.height + top + bottom)
    }

    /// A skin's device window, set when the hook joins it.
    @MainActor final class WindowRef {
        weak var window: NSWindow?
    }

    final class Hook: NSView {
        var ref: WindowRef?
        /// The room the window has now. Only `updateNSView` and `leave` change it.
        var room = EdgeInsets()

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            ref?.window = window
            let center = NotificationCenter.default
            center.removeObserver(self, name: NSWindow.willCloseNotification, object: nil)
            center.removeObserver(self, name: NSApplication.willTerminateNotification, object: nil)
            guard let window else { return }
            center.addObserver(self, selector: #selector(leave), name: NSWindow.willCloseNotification, object: window)
            center.addObserver(self, selector: #selector(leave), name: NSApplication.willTerminateNotification, object: nil)
        }

        /// CLA-124: the saved frame never holds the room. When the window closes or the app quits
        /// in the middle of a turn, the window goes back to its size with no room first, so the
        /// next open puts the device where it was before the turn.
        @objc private func leave(_ note: Notification) {
            guard room != EdgeInsets(), let window else { return }
            window.setFrame(WindowRoom.frame(window.frame, from: room, to: EdgeInsets()), display: false)
            room = EdgeInsets()
        }

        /// Clicks go through to the device and the window drag.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

extension EdgeInsets {
    static func + (a: EdgeInsets, b: EdgeInsets) -> EdgeInsets {
        EdgeInsets(top: a.top + b.top, leading: a.leading + b.leading, bottom: a.bottom + b.bottom, trailing: a.trailing + b.trailing)
    }
}
