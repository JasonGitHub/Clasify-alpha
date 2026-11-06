import AppKit
import ClasifyCore
import ClasifySkins

/// The wheel's click and trackpad tick. The store calls `step()` after each wheel step that
/// moved something, so a step past the end of a list, bar or slider is silent.
/// The Clicker setting turns both on and off. A separate "Haptics" setting may come later.
@MainActor
final class Haptics {
    /// At most one tick in this time, so a fast spin does not flood the trackpad.
    private static let minGap = Duration.milliseconds(15)

    private weak var store: Store?
    private var lastTick: ContinuousClock.Instant?

    init(store: Store) {
        self.store = store
    }

    func step() {
        guard store?.state.clicker == true else { return }
        Clicker.shared.click()
        let now = ContinuousClock.now
        if let lastTick, now - lastTick < Self.minGap { return }
        lastTick = now
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
}
