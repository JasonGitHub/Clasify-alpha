import AppKit
import SwiftUI

/// Turns trackpad and mouse-wheel scrolling over a round view into wheel detents.
/// SwiftUI has no scroll-event API outside a ScrollView, so this is a small AppKit view.
/// Put it in the background of the view. It never takes clicks or drags: it watches the window's
/// scroll events and takes only the ones inside its circle.
struct ScrollCatcher: NSViewRepresentable {
    /// Scroll distance for one detent, as in the mockup. One mouse-wheel line is one detent.
    static let step: CGFloat = 40

    /// The wheel moves a bar (`AppState.wheelMovesBar`), so fingers up on a trackpad are +1.
    var movesBar = false
    let onDetent: @MainActor (Int) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onDetent = onDetent
        view.movesBar = movesBar
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onDetent = onDetent
        view.movesBar = movesBar
    }

    final class CatcherView: NSView {
        var onDetent: @MainActor (Int) -> Void = { _ in }
        var movesBar = false
        private var distance: CGFloat = 0
        /// This swipe began with Cmd: none of it, its glide too, is the wheel's.
        private var cmdScroll = false
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
            // CLA-130: a scroll with Cmd turns the 3D device (`K3DTurnGesture`), with its glide.
            if event.phase == .began { cmdScroll = event.modifierFlags.contains(.command) }
            // A mouse wheel has no phases: the latch is for the trackpad gesture and its glide only.
            let trackpad = !event.phase.isEmpty || !event.momentumPhase.isEmpty
            if cmdScroll && trackpad || event.modifierFlags.contains(.command) { return false }
            let point = convert(event.locationInWindow, from: nil)
            let radius = min(bounds.width, bounds.height) / 2
            guard hypot(point.x - bounds.midX, point.y - bounds.midY) <= radius else { return false }
            if event.phase == .began { distance = 0 }
            if event.hasPreciseScrollingDeltas {
                // A trackpad, in points. Follow the fingers, not the natural scrolling setting
                // (CLA-48): with it on, fingers down give a positive delta. In a list, fingers
                // down are the next row; on a bar, fingers up are more.
                let down = event.isDirectionInvertedFromDevice ? event.scrollingDeltaY : -event.scrollingDeltaY
                distance += movesBar ? -down : down
            } else {
                // A mouse wheel, in lines: down the list is positive, as in a browser.
                distance -= event.scrollingDeltaY * ScrollCatcher.step
            }
            while distance >= ScrollCatcher.step { distance -= ScrollCatcher.step; onDetent(1) }
            while distance <= -ScrollCatcher.step { distance += ScrollCatcher.step; onDetent(-1) }
            return true
        }
    }
}
