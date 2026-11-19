import ClasifyCore
import CryptoKit
import Foundation
import IOKit

/// CLA-145: the activation device ID from this Mac's hardware UUID (IOKit, Apple only). CLA-156:
/// it is the only device ID, in every build. It is computed at each request and stored nowhere. The raw
/// UUID never leaves this file.
enum HardwareID {
    static func deviceID() -> String? {
        DeviceID.make(uuid: platformUUID()) { Array(SHA256.hash(data: Data($0))) }
    }

    /// IOPlatformExpertDevice's kIOPlatformUUIDKey, the UUID that System Information shows.
    /// Nil when it cannot be read: then there is no ID, and the server is not asked.
    static func platformUUID() -> String? {
        let device = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard device != 0 else { return nil }
        defer { IOObjectRelease(device) }
        let value = IORegistryEntryCreateCFProperty(device, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)
        return value?.takeRetainedValue() as? String
    }
}
