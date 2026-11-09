import Foundation

/// The settings that stay after a restart: Shuffle, Repeat, Album Art, Body (the device color)
/// and Clicker, and whether the first launch setup ended.
public struct Settings: Equatable, Sendable {
    public var shuffle = false
    public var repeatMode = RepeatMode.off
    public var albumArt = AlbumArt.all
    public var deviceColor = DeviceColor.silver
    public var clicker = true
    public var setupDone = false

    public init() {}

    /// The keys in the settings store. Each value is a string: "true" or "false", or a raw value.
    enum Key {
        static let shuffle = "settings.shuffle"
        static let repeatMode = "settings.repeat"
        static let albumArt = "settings.albumArt"
        static let deviceColor = "settings.deviceColor"
        static let clicker = "settings.clicker"
        static let setupDone = "setup.done"
    }

    /// The saved settings. A missing or unknown value gives the default.
    public init(from store: some SettingsStore) {
        self.init()
        if let v = store.string(forKey: Key.shuffle).flatMap({ Bool($0) }) { shuffle = v }
        if let v = store.string(forKey: Key.repeatMode).flatMap(RepeatMode.init(rawValue:)) { repeatMode = v }
        if let v = store.string(forKey: Key.albumArt).flatMap(AlbumArt.init(rawValue:)) { albumArt = v }
        if let v = store.string(forKey: Key.deviceColor).flatMap(DeviceColor.init(rawValue:)) { deviceColor = v }
        if let v = store.string(forKey: Key.clicker).flatMap({ Bool($0) }) { clicker = v }
        if let v = store.string(forKey: Key.setupDone).flatMap({ Bool($0) }) { setupDone = v }
    }

    public func save(to store: some SettingsStore) {
        store.set(String(shuffle), forKey: Key.shuffle)
        store.set(repeatMode.rawValue, forKey: Key.repeatMode)
        store.set(albumArt.rawValue, forKey: Key.albumArt)
        store.set(deviceColor.rawValue, forKey: Key.deviceColor)
        store.set(String(clicker), forKey: Key.clicker)
        store.set(String(setupDone), forKey: Key.setupDone)
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
            (v.shuffle, v.repeatMode, v.albumArt, v.deviceColor, v.clicker) = (shuffle, repeatMode, albumArt, deviceColor, clicker)
            v.setupDone = setupDone
            return v
        }
        set {
            (shuffle, repeatMode, albumArt, deviceColor, clicker) =
                (newValue.shuffle, newValue.repeatMode, newValue.albumArt, newValue.deviceColor, newValue.clicker)
            setupDone = newValue.setupDone
        }
    }
}
