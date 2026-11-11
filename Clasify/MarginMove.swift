import AppKit
import SwiftUI

/// CLA-92: the window's clear margin grew, so the device's shadow is not cut off. After the
/// update, macOS brings back the window's old frame, and then the window grows to the new
/// size. This moves the window once, so the device stays where it was on the screen.
struct MarginMove: NSViewRepresentable {
    /// The margin before CLA-92.
    static let oldMargin = EdgeInsets(top: 10, leading: 30, bottom: 50, trailing: 30)
    /// Set after the first launch with the new margin. Then this does nothing.
    static let doneKey = "window.marginMoved"

    func makeNSView(context: Context) -> NSView { Watcher() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Watcher: NSView {
        private var last: NSRect?
        private var observers: [NSObjectProtocol] = []

        override func hitTest(_ point: NSPoint) -> NSView? { nil }  // clicks and drags go to SwiftUI

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let defaults = UserDefaults.standard
            guard let window, observers.isEmpty, !defaults.bool(forKey: MarginMove.doneKey) else { return }
            defaults.set(true, forKey: MarginMove.doneKey)
            last = window.frame
            for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    // The queue is .main, so this runs on the main actor.
                    MainActor.assumeIsolated { self?.check() }
                })
            }
            // The restore and the resize come at launch. Stop watching after that.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                self?.stop()
            }
        }

        /// Moves the window when it grows from the old size to the new size, and only then.
        private func check() {
            guard let window, let old = last else { return }
            let now = window.frame
            last = now
            let new = DeviceWindow.margin, before = MarginMove.oldMargin
            let wider = (new.leading + new.trailing) - (before.leading + before.trailing)
            let taller = (new.top + new.bottom) - (before.top + before.bottom)
            guard now.width - old.width == wider, now.height - old.height == taller else { return }
            stop()
            // AppKit frames start at the bottom left. Keep the device's bottom-left corner.
            window.setFrameOrigin(NSPoint(
                x: old.minX + before.leading - new.leading, y: old.minY + before.bottom - new.bottom))
        }

        private func stop() {
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers = []
        }
    }
}
