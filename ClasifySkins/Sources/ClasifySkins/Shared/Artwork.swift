import CoreGraphics
import SwiftUI

/// Album covers for the skins. The app loads them; a skin only asks for one by cover ID and
/// draws it, so skins stay free of network code. A lookup that reads observed state lets the
/// skin redraw when a cover arrives.
public struct Artwork: Sendable {
    let lookup: @MainActor @Sendable (String) -> CGImage?

    public init(_ lookup: @escaping @MainActor @Sendable (String) -> CGImage?) {
        self.lookup = lookup
    }

    /// No covers: the skins show the colored square.
    public static let none = Artwork { _ in nil }

    @MainActor func image(for coverID: String?) -> CGImage? { coverID.flatMap(lookup) }
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
