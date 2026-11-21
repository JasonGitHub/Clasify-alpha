import Foundation

/// CLA-163, card CE options A and F (Jason 14:07 JST 11-21: "build A and F into the app behind a
/// flag to let me try"): two test looks of the menu bar hint, with the hints trial on. Unset, the
/// hint is CE.1 as built: the glow only.
/// `defaults write com.cappyai.mypod hints.menuBarStyle -string A` (or F);
/// `defaults delete com.cappyai.mypod hints.menuBarStyle` goes back to CE.1.
enum MenuBarHintStyle: String {
    /// The glow and a label on the device screen, like the button hints (`AppState.menuBarLabel`).
    case a = "A"
    /// The glow and white words under the icon (`MenuBarWords`).
    case f = "F"

    static let key = "hints.menuBarStyle"
    static var current: MenuBarHintStyle? {
        UserDefaults.standard.string(forKey: key).flatMap { MenuBarHintStyle(rawValue: $0.uppercased()) }
    }
}
