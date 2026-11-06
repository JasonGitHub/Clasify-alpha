import CoreGraphics
import SwiftUI

/// Album covers for the skins. The app loads them; a skin only asks for one by cover ID and
/// draws it, so skins stay free of network code. A lookup that reads observed state lets the
/// skin redraw when a cover arrives.
public struct Artwork: Sendable {
    let lookup: @MainActor @Sendable (String) -> CGImage?
    let pending: @MainActor @Sendable (String) -> Bool

    /// `pending` says that a cover is still loading, so a skin can keep the cover it showed.
    public init(
        _ lookup: @escaping @MainActor @Sendable (String) -> CGImage?,
        pending: @escaping @MainActor @Sendable (String) -> Bool = { _ in false }
    ) {
        self.lookup = lookup
        self.pending = pending
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
