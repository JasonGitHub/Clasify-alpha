import Foundation

/// Where a cover comes from (CLAUDE.md: Spotify's image CDN and Apple's image server only).
public enum CoverURL {
    /// The URL for a track's `coverID`, or nil when it is not allowed:
    /// - a Spotify image file ID (40 hex digits) gives `https://i.scdn.co/image/<id>`;
    /// - an Apple Music Artwork URL is kept only when it is https on a `*.mzstatic.com` host,
    ///   with no user, password or port.
    /// Every other value never becomes a URL.
    public static func url(for coverID: String) -> URL? {
        if coverID.count == 40, coverID.allSatisfy(\.isHexDigit) {
            return URL(string: "https://i.scdn.co/image/\(coverID)")
        }
        guard let parts = URLComponents(string: coverID), parts.scheme?.lowercased() == "https",
              let host = parts.host?.lowercased(), host.hasSuffix(".mzstatic.com"),
              parts.user == nil, parts.password == nil, parts.port == nil
        else { return nil }
        return parts.url
    }
}
