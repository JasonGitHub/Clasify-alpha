import Foundation

/// CLA-145: the activation device ID comes from the Mac's hardware UUID, so a copy or a reset
/// of app data gives no "new Mac". The app computes it at each request and stores nothing.
/// The hash is passed in (CryptoKit's SHA-256 in the app), because Core builds on Linux too.
public enum DeviceID {
    /// Fixed for the app. It is not a secret: it only keeps this ID apart from other hashes of
    /// the same UUID. A change makes every Mac a new Mac.
    static let salt = "com.cappyai.mypod.activation.v1:"

    /// base64url(SHA-256(salt + UUID)), 43 characters. Nil with no UUID: never a random ID.
    /// With a test value (`Settings.testMac`, Jason's test switch) it is
    /// base64url(SHA-256(salt + UUID + ":" + value)): this Mac as another new Mac. It still
    /// needs this Mac's UUID, so it cannot give the ID of another Mac.
    public static func make(uuid: String?, testMac: String? = nil, sha256: ([UInt8]) -> [UInt8]) -> String? {
        guard let uuid, !uuid.isEmpty else { return nil }
        let digest = sha256(Array((salt + uuid + (testMac.map { ":" + $0 } ?? "")).utf8))
        guard digest.count == 32 else { return nil }
        return base64URL(digest)
    }

    /// RFC 4648 base64url with no padding.
    static func base64URL(_ bytes: [UInt8]) -> String {
        Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
