import AppKit
import SwiftUI

/// Turns trackpad and mouse-wheel scrolling over a round view into wheel detents.
/// SwiftUI on macOS 14 has no scroll-event API outside a ScrollView, so this is a small AppKit view.
/// Put it in the background of the view. It never takes clicks or drags: it watches the window's
/// scroll events and takes only the ones inside its circle.
struct ScrollCatcher: NSViewRepresentable {
    /// Scroll distance for one detent, as in the mockup. One mouse-wheel line is one detent.
    static let step: CGFloat = 40

    let onDetent: @MainActor (Int) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onDetent = onDetent
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onDetent = onDetent
    }

    final class CatcherView: NSView {
        var onDetent: @MainActor (Int) -> Void = { _ in }
        private var distance: CGFloat = 0
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }  // clicks and drags go to SwiftUI

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            // AppKit calls local monitors on the main thread.
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                let taken = MainActor.assumeIsolated { self?.take(event) ?? false }
                return taken ? nil : event
            }
        }

        /// Turns the event into detents if it is over the circle. Returns false to pass it on.
        private func take(_ event: NSEvent) -> Bool {
            guard event.window === window else { return false }
            let point = convert(event.locationInWindow, from: nil)
            let radius = min(bounds.width, bounds.height) / 2
            guard hypot(point.x - bounds.midX, point.y - bounds.midY) <= radius else { return false }
            if event.phase == .began { distance = 0 }
            // A trackpad reports points, a mouse wheel lines. Down the list is positive, as in a browser.
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : ScrollCatcher.step
            distance -= event.scrollingDeltaY * scale
            while distance >= ScrollCatcher.step { distance -= ScrollCatcher.step; onDetent(1) }
            while distance <= -ScrollCatcher.step { distance += ScrollCatcher.step; onDetent(-1) }
            return true
        }
    }
}
