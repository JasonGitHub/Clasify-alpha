import ClasifyCore
import UIKit

/// Reads the iPhone's battery from UIDevice and sends `.batteryChanged` to the store, for the
/// device's title bar (card CX): once at launch, then on each change of level or charge state.
/// It only reads. iOS gives the level in 5 % steps. With no reading (the Simulator), it sends
/// nil, and the title bar shows no battery.
@MainActor
final class PhoneBattery {
    private weak var store: Store?
    private var observers: [NSObjectProtocol] = []

    init(store: Store) {
        self.store = store
        UIDevice.current.isBatteryMonitoringEnabled = true
        update()
        for name in [UIDevice.batteryLevelDidChangeNotification, UIDevice.batteryStateDidChangeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // The queue is .main, so this runs on the main actor.
                MainActor.assumeIsolated { self?.update() }
            })
        }
    }

    private func update() {
        guard let store else { return }
        let battery = Self.read()
        if battery != store.state.battery { store.send(.batteryChanged(battery)) }
    }

    /// The level and charge state. Nil when iOS has no reading.
    static func read() -> Battery? {
        let device = UIDevice.current
        guard device.batteryLevel >= 0, device.batteryState != .unknown else { return nil }
        let state = device.batteryState
        return Battery(level: Double(device.batteryLevel), charging: state == .charging, onPower: state == .charging || state == .full)
    }
}
