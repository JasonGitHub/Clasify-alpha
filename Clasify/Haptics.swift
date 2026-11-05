import AppKit
import ClasifyCore
import Observation

/// TEST: trackpad ticks that follow the wheel. They run from state changes, not from input,
/// so the skins and the reducer do not change. The Clicker setting turns them on and off.
/// A separate "Haptics" setting may come later.
@MainActor
final class Haptics {
    /// At most one tick in this time, so a fast spin does not flood the trackpad.
    private static let minGap = Duration.milliseconds(15)

    private weak var store: Store?
    private var last: AppState
    private var lastTick: ContinuousClock.Instant?

    init(store: Store) {
        self.store = store
        last = store.state
        observe()
    }

    /// Calls `changed()` after each change of the store's state, until the store goes away.
    private func observe() {
        guard let store else { return }
        withObservationTracking {
            _ = store.state
        } onChange: { [weak self] in
            // onChange runs before the new value is set, so read it on the next main-actor turn.
            Task { @MainActor in
                self?.changed()
                self?.observe()
            }
        }
    }

    private func changed() {
        guard let state = store?.state else { return }
        defer { last = state }
        guard state.clicker, let pattern = Self.pattern(from: last, to: state) else { return }
        let now = ContinuousClock.now
        if let lastTick, now - lastTick < Self.minGap { return }
        lastTick = now
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    /// The tick for one state change, or nil for none.
    /// - The selected row moves on the same screen: `.generic`.
    /// - The volume, the scrub position, or the shuffle or repeat slider steps: `.generic`.
    /// - The wheel turns past the end of the volume or scrub bar or a slider: `.alignment`.
    /// A turn past the first or last row of a list leaves the state the same,
    /// so it cannot be found from state and gets no tick.
    static func pattern(from old: AppState, to new: AppState) -> NSHapticFeedbackManager.FeedbackPattern? {
        guard old.stack.count == new.stack.count, old.top.screen == new.top.screen else { return nil }
        if new.top.screen.isList {
            return old.top.sel != new.top.sel ? .generic : nil
        }
        // On Now Playing, each wheel step pushes overlayUntil forward. A press of the
        // center button does too, but it also changes nowMode. Playback moves `t` alone.
        guard new.top.screen == .now, old.nowMode == new.nowMode,
            new.overlayUntil > old.overlayUntil
        else { return nil }
        let stepped =
            switch new.nowMode {
            case .volume: old.volume != new.volume
            case .scrub: old.t != new.t
            case .shuffle: old.shuffle != new.shuffle
            case .repeatMode: old.repeatMode != new.repeatMode
            }
        return stepped ? .generic : .alignment
    }
}
