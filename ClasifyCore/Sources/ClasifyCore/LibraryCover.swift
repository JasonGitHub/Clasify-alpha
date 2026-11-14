/// An Apple Music library cover from Apple's iTunesLibrary framework (CLA-103). Its cover ID is
/// `itlib:<persistent ID in hex>:<side in pixels>`: an opaque key, never a URL, so `CoverURL`
/// refuses it. The app reads the image from the library into memory at that side.
public enum LibraryCover {
    static let prefix = "itlib:"

    public static func coverID(persistentID: UInt64, side: Int) -> String {
        prefix + String(persistentID, radix: 16) + ":" + String(side)
    }

    /// The persistent ID and side in a library cover ID. nil for any other cover ID.
    public static func parse(_ coverID: String) -> (persistentID: UInt64, side: Int)? {
        guard coverID.hasPrefix(prefix) else { return nil }
        let parts = coverID.dropFirst(prefix.count).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let id = UInt64(parts[0], radix: 16), let side = Int(parts[1]),
              (1...2048).contains(side) else { return nil }
        return (id, side)
    }

    /// The persistent ID in a MusicKit library song ID, when the ID is a 64-bit decimal number,
    /// signed or unsigned (build 194, macOS 27: 19 digits, or 20 characters). A negative ID
    /// keeps its bit pattern. nil for any other ID. Not checked on a Mac: that it is the same
    /// number as the iTunesLibrary item's persistent ID.
    public static func persistentID(musicKitID: String) -> UInt64? {
        if let value = UInt64(musicKitID) { return value }
        if let value = Int64(musicKitID) { return UInt64(bitPattern: value) }
        return nil
    }
}
