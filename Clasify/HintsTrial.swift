import Foundation

/// CLA-163: the hints switch `hints.trial`, for the turn hint, the menu bar glow, the soft show
/// and hide fade and the How to Use menu bar row. On for everyone (Jason 14:02 JST 11-21): on
/// when it is not set, as `analytics.on` is. Turn it off with
/// `defaults write com.cappyai.mypod hints.trial -bool false`; off, the app is as before.
enum HintsTrial {
    static let key = "hints.trial"
    static var on: Bool { switchOn(.standard) }

    /// The switch in `defaults`: on when it is not set.
    static func switchOn(_ defaults: UserDefaults) -> Bool { defaults.object(forKey: key) as? Bool ?? true }
}
