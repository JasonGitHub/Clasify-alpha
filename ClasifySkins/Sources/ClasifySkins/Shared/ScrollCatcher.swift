import AppKit
import SwiftUI

/// Turns trackpad and mouse-wheel scrolling over a view into wheel detents.
/// SwiftUI on macOS 14 has no scroll-event API outside a ScrollView, so this is a small AppKit view.
/// It takes only scroll events. Clicks and drags go through it to the SwiftUI views below.
struct ScrollCatcher: NSViewRepresentable {
    /// Scroll distance for one detent, as in the mockup.
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

        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp.currentEvent?.type == .scrollWheel ? super.hitTest(point) : nil
        }

        override func scrollWheel(with event: NSEvent) {
            if event.phase == .began { distance = 0 }
            // A mouse wheel reports lines, a trackpad points. Down the list is positive, as in a browser.
            let lines: CGFloat = event.hasPreciseScrollingDeltas ? 1 : Self.lineHeight
            distance -= event.scrollingDeltaY * lines
            while distance >= ScrollCatcher.step { distance -= ScrollCatcher.step; onDetent(1) }
            while distance <= -ScrollCatcher.step { distance += ScrollCatcher.step; onDetent(-1) }
        }

        /// One mouse-wheel line counts as one detent.
        private static let lineHeight = ScrollCatcher.step
    }
}
