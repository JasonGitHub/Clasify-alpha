import AppKit
import ClasifySkins
import SwiftUI

/// CLA-163: the turn hint's own clear window, just over the device window. Its top is at the
/// device's bottom edge, centred under the device. The 90 pt bottom margin of the device window
/// is too small for the key and the words, so they get a window of their own. It takes no
/// clicks: they go through to the apps behind it. Not a child window: the 3D room moves the
/// device window's frame while the device stays still (Codex on #363), so the hint follows the
/// device itself, from the window's frame and `DeviceWindow.room`, at each move.
@MainActor final class TurnHintWindow {
    private let panel: NSPanel
    private let host: NSHostingView<TurnHint>
    private let start = Date.now
    private var ended: Date?
    private var closing: Task<Void, Never>?
    private var gone = false
    private weak var device: NSWindow?
    private var moves: NSObjectProtocol?
    /// Runs once, when the hint is gone (for the menu bar hint that comes after it).
    var onEnd: (() -> Void)?

    /// Shows the hint under the device in `window`. `room` is the room the skin has round its margins.
    init(under window: NSWindow, room: EdgeInsets) {
        let size = TurnHint.size
        let frame = Self.frame(under: window, room: room)
        device = window
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        host = NSHostingView(rootView: TurnHint(start: start))
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
        panel.order(.above, relativeTo: window.windowNumber)
        moves = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.follow() }
        }
        closeAt(TurnHint.over(end: nil))
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

    /// The first Cmd turn: all fades out in `TurnHint.endFade`.
    func end() {
        guard ended == nil, !gone else { return }
        let now = Date.now
        ended = now
        host.rootView = TurnHint(start: start, ended: now)
        closeAt(TurnHint.over(end: now.timeIntervalSince(start)))
    }

    /// Takes the window away now, with no fade (the device window closed).
    func remove() {
        closing?.cancel()
        closing = nil
        guard !gone else { return }
        gone = true
        if let moves { NotificationCenter.default.removeObserver(moves) }
        moves = nil
        panel.orderOut(nil)
        let done = onEnd
        onEnd = nil
        done?()
    }

    private func closeAt(_ seconds: Double) {
        closing?.cancel()
        closing = Task { @MainActor [weak self] in
            guard let self else { return }
            let wait = seconds - Date.now.timeIntervalSince(start)
            do { try await Task.sleep(for: .seconds(max(0, wait))) } catch { return }
            remove()
        }
    }
}
