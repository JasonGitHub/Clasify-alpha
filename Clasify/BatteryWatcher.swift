import ClasifyCore
import Foundation
import IOKit.ps

/// Posted by the IOKit callback when a power source changes. A global, so the C callback can
/// use it without the main actor.
private let powerSourceChanged = Notification.Name("ClasifyPowerSourceChanged")

/// Reads the Mac's battery from IOKit (Apple only, no new dependency) and sends
/// `.batteryChanged` to the store: once at launch, then each time macOS reports a change, such
/// as a new level or a plugged in adapter. It only reads: it writes nothing and changes no
/// power setting. A Mac with no battery sends nil, and the title bar shows no battery.
@MainActor
final class BatteryWatcher {
    private weak var store: Store?
    private var source: CFRunLoopSource?
    private var observer: NSObjectProtocol?

    init(store: Store) {
        self.store = store
        update()
        observer = NotificationCenter.default.addObserver(forName: powerSourceChanged, object: nil, queue: .main) { [weak self] _ in
            // The queue is .main, so this runs on the main actor.
            MainActor.assumeIsolated { self?.update() }
        }
        // IOKit calls this C function on the run loop it is added to: the main one.
        if let src = IOPSNotificationCreateRunLoopSource({ _ in
            NotificationCenter.default.post(name: powerSourceChanged, object: nil)
        }, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
            source = src
        }
    }

    private func update() {
        guard let store else { return }
        let battery = Self.read()
        if battery != store.state.battery { store.send(.batteryChanged(battery)) }
    }

    /// The internal battery's level, charge state and power source. Nil when there is none.
    nonisolated static func read() -> Battery? {
        guard let snapshot = IOPSCopyPowerSourcesInfo() else { return nil }
        let info = snapshot.takeRetainedValue()
        guard let sources = IOPSCopyPowerSourcesList(info) else { return nil }
        for ps in sources.takeRetainedValue() as [AnyObject] {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  d[kIOPSIsPresentKey] as? Bool ?? true,
                  let current = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            return Battery(
                level: Double(current) / Double(max),
                charging: d[kIOPSIsChargingKey] as? Bool ?? false,
                onPower: d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
        }
        return nil
    }
}
