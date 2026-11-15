import ClasifyCore
import Foundation
import Security

/// Card BI v2 (CLA-96): a beta is a Developer ID build. The app reads its own signature: a
/// Team ID and a secure timestamp make it a beta that ends 30 days after that time. An ad-hoc
/// build has neither, so it is no beta and never ends. A missing or unreadable timestamp
/// counts as no beta.
enum BetaSignature {
    /// "Get New Beta" opens this page (cards BI v2 and BP): a page just for the beta.
    static let downloadPage = URL(string: "https://getmypod.app/beta")!

    static func read() -> BetaBuild? {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess,
              let info = info as? [String: Any],
              let team = info[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty,
              let signed = info[kSecCodeInfoTimestamp as String] as? Date
        else { return nil }
        return BetaBuild(signed: signed.timeIntervalSinceReferenceDate)
    }
}
