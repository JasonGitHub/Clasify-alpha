import AppKit
import ClasifySkins
import SwiftUI

/// CLA-130 (card BT row 4): Cmd + a two-finger swipe, a mouse wheel or a pinch on the device.
/// Change 355: Cmd + a mouse drag turns it too, a hold takes it apart, a click puts it together.
/// Without Cmd, a drag moves the window as before.
/// SwiftUI has no scroll or magnify events outside a ScrollView, so this is a small AppKit view,
/// as `ScrollCatcher`. Put it in the background of the device. It never takes clicks: it watches
/// the window's events, and `K3DTurnGesture` says which ones are the turn's.
struct K3DTurnInput: NSViewRepresentable {
    /// One mouse-wheel line, in points of finger travel.
    static let line = 20.0

    let onSwipe: @MainActor (_ dx: Double, _ dy: Double) -> Void
    let onPinch: @MainActor (_ amount: Double, _ began: Bool) -> Void
    let onEnd: @MainActor () -> Void
    /// Change 355: a Cmd press on the device (the prints get ready), its hold, and its click.
    let onPress: @MainActor () -> Void
    let onHold: @MainActor () -> Void
    let onClick: @MainActor () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        (view.onSwipe, view.onPinch, view.onEnd) = (onSwipe, onPinch, onEnd)
        (view.onPress, view.onHold, view.onClick) = (onPress, onHold, onClick)
    }

    final class CatcherView: NSView {
        var onSwipe: @MainActor (Double, Double) -> Void = { _, _ in }
        var onPinch: @MainActor (Double, Bool) -> Void = { _, _ in }
        var onEnd: @MainActor () -> Void = {}
        var onPress: @MainActor () -> Void = {}
        var onHold: @MainActor () -> Void = {}
        var onClick: @MainActor () -> Void = {}
        /// Change 355: the Cmd press, from mouse down to up: where it is, whether it moved past
        /// the slop, and the hold that waits for 1.2 s.
        private var press: NSPoint?
        private var moved = false
        private var last = NSPoint.zero
        private var hold: Task<Void, Never>?
        private var gesture = K3DTurnGesture()
        private var monitor: Any?
        private var observers: [NSObjectProtocol] = []

        override func hitTest(_ point: NSPoint) -> NSView? { nil }  // clicks and drags go to SwiftUI

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            (monitor, observers) = (nil, [])
            guard let window else { return resign() }
            // AppKit calls local monitors on the main thread.
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify, .flagsChanged, .leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
                let taken = MainActor.assumeIsolated { self?.take(event) ?? false }
                return taken ? nil : event
            }
            // The CTO's safety exit: Clasify or the device window goes to the back. The plain
            // window cannot become key (CLA-83), so the app's own notice counts most.
            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.resign() }
                },
                center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.resign() }
                },
            ]
        }

        private func resign() {
            endPress()
            if gesture.resign() { onEnd() }
        }

        private func endPress() {
            hold?.cancel()
            (hold, press, moved) = (nil, nil, false)
        }

        /// Change 355: a Cmd press, drag or release with the mouse. True: the event is the turn's.
        private func mouse(_ event: NSEvent, command: Bool, inside: Bool) -> Bool {
            let point = convert(event.locationInWindow, from: nil)
            switch event.type {
            case .leftMouseDown:
                guard gesture.scroll(.begin, command: command, inside: inside) == .turn else { return false }
                (press, moved) = (point, false)
                onPress()
                hold = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(K3DTurn.holdTime)) } catch { return }
                    guard let self, self.press != nil, !self.moved else { return }
                    self.hold = nil
                    self.onHold()
                }
            case .leftMouseDragged:
                guard let start = press, gesture.scroll(.move, command: command, inside: inside) == .turn else { return false }
                if !moved {
                    guard Double(hypot(point.x - start.x, point.y - start.y)) > K3DTurn.slop else { return true }
                    hold?.cancel()
                    (moved, hold, last) = (true, nil, start)
                }
                // The view is not flipped: up is +y, so a drag down is a positive dy.
                onSwipe(point.x - last.x, last.y - point.y)
                last = point
            default:
                guard press != nil else { return false }
                let click = !moved && hold != nil
                endPress()
                if click { onClick() }
                if gesture.scroll(.lift, command: command, inside: inside) == .end { onEnd() }
            }
            return true
        }

        /// Returns true to take the event, false to pass it on.
        private func take(_ event: NSEvent) -> Bool {
            let command = event.modifierFlags.contains(.command)
            if event.type == .flagsChanged {
                if gesture.command(down: command) { onEnd() }
                return false  // Cmd itself is not the turn's: shortcuts keep working
            }
            guard event.window === window else { return false }
            let inside = bounds.contains(convert(event.locationInWindow, from: nil))
            if [.leftMouseDown, .leftMouseDragged, .leftMouseUp].contains(event.type) {
                return mouse(event, command: command, inside: inside)
            }
            if event.type == .magnify {
                guard gesture.pinch(command: command, inside: inside) else { return false }
                onPinch(event.magnification, event.phase == .began)
                return true
            }
            switch gesture.scroll(Self.kind(event), command: command, inside: inside) {
            case .pass: return false
            case .swallow: return true
            case .end: onEnd()
            case .turn:
                if event.hasPreciseScrollingDeltas {
                    // Follow the fingers, not the natural scrolling setting (CLA-48): with it on,
                    // fingers right and down give positive deltas.
                    let sign = event.isDirectionInvertedFromDevice ? 1.0 : -1.0
                    onSwipe(sign * event.scrollingDeltaX, sign * event.scrollingDeltaY)
                } else {
                    onSwipe(event.scrollingDeltaY * K3DTurnInput.line, 0)  // a mouse wheel turns only
                }
            }
            return true
        }

        private static func kind(_ event: NSEvent) -> K3DTurnGesture.Scroll {
            if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) { return .glideEnd }
            if !event.momentumPhase.isEmpty { return .glide }
            if event.phase.contains(.began) { return .begin }
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) { return .lift }
            return event.phase.isEmpty ? .wheel : .move
        }
    }
}
