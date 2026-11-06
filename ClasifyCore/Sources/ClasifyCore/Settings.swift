import Foundation

/// The settings that stay after a restart: Shuffle, Repeat, Album Art and Clicker.
public struct Settings: Equatable, Sendable {
    public var shuffle = false
    public var repeatMode = RepeatMode.off
    public var albumArt = AlbumArt.all
    public var clicker = true

    public init() {}

    /// The keys in the settings store. Each value is a string: "true" or "false", or a raw value.
    enum Key {
        static let shuffle = "settings.shuffle"
        static let repeatMode = "settings.repeat"
        static let albumArt = "settings.albumArt"
        static let clicker = "settings.clicker"
    }

    /// The saved settings. A missing or unknown value gives the default.
    public init(from store: some SettingsStore) {
        self.init()
        if let v = store.string(forKey: Key.shuffle).flatMap({ Bool($0) }) { shuffle = v }
        if let v = store.string(forKey: Key.repeatMode).flatMap(RepeatMode.init(rawValue:)) { repeatMode = v }
        if let v = store.string(forKey: Key.albumArt).flatMap(AlbumArt.init(rawValue:)) { albumArt = v }
        if let v = store.string(forKey: Key.clicker).flatMap({ Bool($0) }) { clicker = v }
    }

    public func save(to store: some SettingsStore) {
        store.set(String(shuffle), forKey: Key.shuffle)
        store.set(repeatMode.rawValue, forKey: Key.repeatMode)
        store.set(albumArt.rawValue, forKey: Key.albumArt)
        store.set(String(clicker), forKey: Key.clicker)
    }
}

/// Where settings are saved: UserDefaults in the app, a fake in tests. Nothing else is
/// written to disk.
public protocol SettingsStore: AnyObject {
    func string(forKey key: String) -> String?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: SettingsStore {}

extension AppState {
    /// The settings part of the state, which `Store` loads at launch and saves when it changes.
    public var settings: Settings {
        get {
            var v = Settings()
            (v.shuffle, v.repeatMode, v.albumArt, v.clicker) = (shuffle, repeatMode, albumArt, clicker)
            return v
        }
        set { (shuffle, repeatMode, albumArt, clicker) = (newValue.shuffle, newValue.repeatMode, newValue.albumArt, newValue.clicker) }
    }
}
