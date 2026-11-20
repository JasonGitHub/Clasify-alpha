import AppKit
import ClasifySkins
import SwiftUI

/// CLA-163: the turn hint's own clear window, just over the device window. Its top is at the
/// device's bottom edge, centred under the device. The 90 pt bottom margin of the device window
/// is too small for the key and the words, so they get a window of their own. It takes no
/// clicks: they go through to the apps behind it. Not a child window: the 3D room moves the
/// device window's frame while the device stays still (Codex on #363), so the hint follows the
/// device itself, from the window's frame and `DeviceWindow.room`, at each move.
///
/// Card CE.1: the window stays while the tour shows the hint (`Hint.tourTurn`); `end()` fades it
/// out. Its key follows the person's own ⌘ key (394). The window looks at ⌘ every `pollEvery`
/// seconds, with `NSEvent.modifierFlags`: a key monitor gets ⌘ only while myPod is the active
/// app. Until that first press, `onNudge` comes on each press of the key's loop (393).
@MainActor final class TurnHintWindow {
    /// Seconds between two looks at ⌘: well under the key's 0.08 s move.
    static let pollEvery = 0.02

    private let panel: NSPanel
    private let host: NSHostingView<TurnHint>
    private let start: Date
    private var ended: Date?
    private var press: TurnHint.Press?
    /// ⌘ at the last look. A ⌘ already down when the hint shows is no press of the person's.
    private var command = NSEvent.modifierFlags.contains(.command)
    private var nextNudge = TurnHint.nextNudge(after: 0)
    private var watch: Task<Void, Never>?
    private var gone = false
    private weak var device: NSWindow?
    private var moves: NSObjectProtocol?
    /// The device nudges: a press of the key's loop, before the person's first ⌘ press.
    var onNudge: (() -> Void)?

    /// Shows the hint under the device in `window`. `room` is the room the skin has round its margins.
    init(under window: NSWindow, room: EdgeInsets) {
        let start = Date.now
        self.start = start
        device = window
        let made = TurnHintPanel.make(TurnHint(start: start), frame: Self.frame(under: window, room: room))
        panel = made.0
        host = made.1
        panel.order(.above, relativeTo: window.windowNumber)
        moves = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.follow() }
        }
        watch = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(TurnHintWindow.pollEvery)) } catch { return }
                guard let self else { return }
                self.look()
            }
        }
    }

    /// Where the hint goes for the device in `window` with `room` round its margins.
    private static func frame(under window: NSWindow, room: EdgeInsets) -> NSRect {
        let size = TurnHint.size
        let deviceBottom = window.frame.minY + DeviceWindow.margin.bottom + room.bottom
        let centre = window.frame.minX + DeviceWindow.margin.leading + room.leading + PocketSkin.size.width / 2
        return NSRect(x: centre - size.width / 2, y: deviceBottom - size.height, width: size.width, height: size.height)
    }

    /// The device window moved: a drag, or its room changed (then the device stays still).
    private func follow() {
        guard !gone, let device else { return }
        panel.setFrame(Self.frame(under: device, room: DeviceWindow.room), display: false)
    }

    /// One look at ⌘ and at the loop's next nudge.
    private func look() {
        guard !gone, ended == nil else { return }
        let t = Date.now.timeIntervalSince(start)
        let down = NSEvent.modifierFlags.contains(.command)
        if down != command {
            command = down
            // 394: the key goes the person's way from where it is now, and the loop never comes back.
            press = TurnHint.Press(at: t, down: down, from: TurnHint.down(at: t, press: press))
            host.rootView = TurnHint(start: start, press: press)
        }
        guard press == nil, t >= nextNudge else { return }
        nextNudge = TurnHint.nextNudge(after: t)
        onNudge?()
    }

    /// The hint ended (its step is done, other input hid it, or the device does not show): all
    /// fades out in `TurnHint.fade`. The window keeps itself until then.
    func end() {
        guard ended == nil, !gone else { return }
        let now = Date.now
        ended = now
        watch?.cancel()
        host.rootView = TurnHint(start: start, ended: now, press: press)
        let wait = TurnHint.over(end: now.timeIntervalSince(start)) - now.timeIntervalSince(start)
        watch = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(wait)) } catch { return }
            self.remove()
        }
    }

    /// Takes the window away now, with no fade (the device window closed).
    func remove() {
        watch?.cancel()
        watch = nil
        guard !gone else { return }
        gone = true
        if let moves { NotificationCenter.default.removeObserver(moves) }
        moves = nil
        onNudge = nil
        panel.orderOut(nil)
    }
}
