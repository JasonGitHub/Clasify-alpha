import Foundation

// CLA-202 spike: iOS stand-ins for the 2 Mac-only types that the copied Apple Music files call.
// The Mac files (Clasify/AppleMusic/MacVolume.swift and AppleMusicArt.swift) are not in this
// target. Everything here does nothing, so the copied files compile unchanged.

/// The Mac's output volume (CLA-168). On the iPhone the spike has no volume control.
@MainActor final class MacVolume {
    var onChange: (@MainActor (Int) -> Void)?
    func start() {}
    func stop() {}
    func read() -> Int? { nil }
    func write(_ percent: Int) {}
}

/// The Mac's iTunesLibrary covers. The iPhone has no iTunesLibrary framework: no match.
actor AppleMusicArt {
    static let shared = AppleMusicArt()
    func forget() {}
    func match(_ songs: [(id: String, key: String)]) -> (found: [String: UInt64], byID: Int, byName: Int) {
        ([:], 0, 0)
    }
}
