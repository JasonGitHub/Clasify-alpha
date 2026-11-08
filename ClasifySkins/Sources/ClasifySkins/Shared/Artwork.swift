import CoreGraphics
import SwiftUI

/// Album covers for the skins. The app loads them; a skin only asks for one by cover ID and
/// draws it, so skins stay free of network code. A lookup that reads observed state lets the
/// skin redraw when a cover arrives.
public struct Artwork: Sendable {
    let lookup: @MainActor @Sendable (String) -> CGImage?
    let pending: @MainActor @Sendable (String) -> Bool
    let loadedAt: @MainActor @Sendable (String) -> Double?

    /// `pending` says that a cover is still loading, so a skin can keep the cover it showed.
    /// `loadedAt` gives when a cover in memory arrived, in seconds since the reference date
    /// (`Date.timeIntervalSinceReferenceDate`), so a skin can tell whether it was there when
    /// a cover's turn began. By default, each cover in memory has always been there.
    public init(
        _ lookup: @escaping @MainActor @Sendable (String) -> CGImage?,
        pending: @escaping @MainActor @Sendable (String) -> Bool = { _ in false },
        loadedAt: @escaping @MainActor @Sendable (String) -> Double? = { _ in -.infinity }
    ) {
        self.lookup = lookup
        self.pending = pending
        self.loadedAt = loadedAt
    }

    /// No covers: the skins show the blue-grey square.
    public static let none = Artwork { _ in nil }

    @MainActor func image(for coverID: String?) -> CGImage? { coverID.flatMap(lookup) }
    @MainActor func isPending(_ coverID: String?) -> Bool { coverID.map(pending) ?? false }
}

private struct ArtworkKey: EnvironmentKey {
    static let defaultValue = Artwork.none
}

extension EnvironmentValues {
    /// The covers that the skins draw. Set it with `.environment(\.artwork, ...)`.
    public var artwork: Artwork {
        get { self[ArtworkKey.self] }
        set { self[ArtworkKey.self] = newValue }
    }
}
