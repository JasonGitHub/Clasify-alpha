import ClasifyCore
// MusicKit's item types are not Sendable in the macOS 15 SDK. Clasify uses them only on the main actor.
@preconcurrency import MusicKit

/// The IDs that Clasify uses for Apple Music items in the store: "applemusic:song:<id>" and
/// "applemusic:playlist:<id>", with MusicKit's `MusicItemID` at the end. A Spotify ID never
/// starts with "applemusic:", so the two services can never mix.
enum AppleMusicID {
    static let songPrefix = "applemusic:song:"
    static let playlistPrefix = "applemusic:playlist:"

    static func song(_ id: MusicItemID) -> String { songPrefix + id.rawValue }
    static func playlist(_ id: MusicItemID) -> String { playlistPrefix + id.rawValue }

    /// The MusicKit ID in a store ID with this prefix, or nil.
    static func itemID(_ id: String, prefix: String) -> MusicItemID? {
        guard id.hasPrefix(prefix), id.count > prefix.count else { return nil }
        return MusicItemID(String(id.dropFirst(prefix.count)))
    }

    /// The store ID of a queue entry's song or music video. nil while MusicKit has not
    /// resolved the entry's item yet.
    static func of(_ entry: ApplicationMusicPlayer.Queue.Entry) -> String? {
        switch entry.item {
        case .song(let item): Self.song(item.id)
        case .musicVideo(let item): songPrefix + item.id.rawValue
        default: nil
        }
    }
}
