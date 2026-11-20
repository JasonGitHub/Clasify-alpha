import Foundation

/// CLA-163 (Jason 15:30 JST 11-20): the turn hint (card BZ A v2) and the menu bar hint (card CE
/// H.2) are a trial behind one UserDefaults switch, off by default. Off, the app is exactly as
/// before. Turn it on with `defaults write com.cappyai.mypod hints.trial -bool true`.
enum HintsTrial {
    static let key = "hints.trial"
    static var on: Bool { UserDefaults.standard.bool(forKey: key) }
}
