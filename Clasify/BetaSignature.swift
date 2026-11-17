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
        // Card BV: the build number (CFBundleVersion = the run number), to compare with the newest beta.
        let number = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String).flatMap { Int($0) } ?? 0
        return BetaBuild(signed: signed.timeIntervalSinceReferenceDate, number: number)
    }
}

/// Card BV (CLA-125, change 314): reads the newest beta's build number from one small file on
/// getmypod.app, `{"build": 290, ...}`, once a launch. Only `build` is read. Offline, no answer in
/// 5 s, an error status or a bad file give nil, with no error shown. The session is ephemeral:
/// no cache and no cookies on disk.
struct BetaFeedLive: BetaFeed {
    static let latest = URL(string: "https://getmypod.app/beta/latest.json")!

    private struct Latest: Decodable { let build: Int }

    func latestBuild() async -> Int? {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(from: Self.latest),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let latest = try? JSONDecoder().decode(Latest.self, from: data), latest.build > 0
        else { return nil }
        return latest.build
    }
}
