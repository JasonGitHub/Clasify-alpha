import Foundation

/// A key that names one library song by its title, artist and album, so that two lists of the
/// same library can be matched when their IDs differ (Apple Music covers, CLA-103). Case,
/// accents, full-width letters and outer spaces do not count.
public enum LibraryKey {
    public static func of(title: String, artist: String, album: String?) -> String {
        [title, artist, album ?? ""].map(fold).joined(separator: "\u{1F}")
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension CoverURL {
    /// An Apple Music artwork URL template (`.../{w}x{h}bb.jpg`) filled for a square cover of
    /// `size` pixels. nil when the result is not an address that `url(for:)` allows.
    public static func apple(template: String, size: Int) -> String? {
        let filled = template.replacingOccurrences(of: "{w}", with: "\(size)").replacingOccurrences(of: "{h}", with: "\(size)")
            .replacingOccurrences(of: "{c}", with: "bb").replacingOccurrences(of: "{f}", with: "jpg")
        return url(for: filled) == nil ? nil : filled
    }
}
