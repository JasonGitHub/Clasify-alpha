import Foundation

/// CLA-171: "Get New Beta" downloads the newest DMG directly. The beta feed
/// (`dl.getmypod.app/beta/latest.json`, written by app-dmg.yml) also names the DMG's `url`.
public enum BetaDownload {
    /// The only host the app downloads a beta from.
    public static let host = "dl.getmypod.app"

    /// The feed's `url`, or nil when it is not allowed. Only an https URL whose host is exactly
    /// `dl.getmypod.app`, with no user, password or port and a path under it, is kept. Any other
    /// value, such as another host or a lookalike like `dl.getmypod.app.example.com`, is nil, so
    /// the app opens the beta page instead.
    public static func url(_ value: String?) -> URL? {
        guard let value, let parts = URLComponents(string: value), parts.scheme?.lowercased() == "https",
              parts.host?.lowercased() == host, parts.user == nil, parts.password == nil, parts.port == nil,
              parts.path.count > 1, parts.path.hasPrefix("/")
        else { return nil }
        return parts.url
    }
}
