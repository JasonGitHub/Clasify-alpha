import ClasifyCore
import ClasifySkins
import UIKit

/// The wheel's click and its haptic tick on the iPhone, as `Haptics` on the Mac. The store calls
/// `step()` after each wheel step that moved something, so a step past the end is silent. The
/// Clicker setting turns both on and off.
@MainActor
final class PhoneHaptics {
    /// At most one tick in this time, so a fast spin does not flood the Taptic Engine.
    private static let minGap = Duration.milliseconds(15)

    private weak var store: Store?
    private var lastTick: ContinuousClock.Instant?
    private let generator = UISelectionFeedbackGenerator()

    init(store: Store) {
        self.store = store
        generator.prepare()
    }

    func step() {
        guard store?.state.clicker == true else { return }
        Clicker.shared.click()
        let now = ContinuousClock.now
        if let lastTick, now - lastTick < Self.minGap { return }
        lastTick = now
        generator.selectionChanged()
        generator.prepare()  // keeps the Taptic Engine ready for the next step
    }
}
