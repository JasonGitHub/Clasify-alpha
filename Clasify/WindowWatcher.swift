import AppKit
import ClasifyCore

/// CLA-162 (Jason 15:09 JST 11-20): sends `.window` with where the device window is
/// (`DeviceWindow.spot`) once a minute, and at once when the area, the screen or the
/// visibility changes: a move, a hide, a cover, a screen change. The reducer counts the time
/// between two reports for `day_active`. It reads only myPod's own window.
@MainActor
final class WindowWatcher {
    private weak var store: Store?
    private var last: WindowSpot?
    private var observers: [NSObjectProtocol] = []
    private var timer: Task<Void, Never>?

    init(store: Store) {
        self.store = store
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didChangeOcclusionStateNotification, NSWindow.didMoveNotification, NSWindow.didChangeScreenNotification,
            NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
            NSApplication.didHideNotification, NSApplication.didUnhideNotification,
            NSApplication.didChangeScreenParametersNotification,
        ]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // The queue is .main, so this runs on the main actor.
                MainActor.assumeIsolated { self?.report(always: false) }
            }
        }
        timer = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.report(always: true)
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    /// A change goes out at once; the same spot goes out only on the minute.
    private func report(always: Bool) {
        let spot = DeviceWindow.spot
        guard always || spot != last else { return }
        last = spot
        store?.send(.window(spot))
    }
}
