import Foundation

/// The music service that Clasify plays from. One service is active at a time (CLA-103): no
/// mixed lists or queues.
public enum MusicService: String, CaseIterable, Sendable {
    case spotify = "Spotify", appleMusic = "Apple Music"
}

/// The settings that stay after a restart: Shuffle, Repeat, Album Art, Color (the device color),
/// Clicker, Now Playing Bar and Service, whether the first launch setup ended, and the first-time hints
/// that ended (card BA).
public struct Settings: Equatable, Sendable {
    public var shuffle = false
    public var repeatMode = RepeatMode.off
    public var albumArt = AlbumArt.all
    public var deviceColor = DeviceColor.silver
    public var clicker = true
    public var nowPlayingBar = false
    public var service = MusicService.spotify
    public var setupDone = false
    public var hintsDone: Set<Hint> = []
    public var tourOn = false
    public var tourHides: [Hint: Int] = [:]

    public init() {}

    /// The keys in the settings store. Each value is a string: "true" or "false", or a raw value.
    enum Key {
        static let shuffle = "settings.shuffle"
        static let repeatMode = "settings.repeat"
        static let albumArt = "settings.albumArt"
        static let deviceColor = "settings.deviceColor"
        static let clicker = "settings.clicker"
        static let nowPlayingBar = "settings.nowPlayingBar"
        static let service = "settings.service"
        static let setupDone = "setup.done"
        static let hintsDone = "hints.done"
        static let tourOn = "hints.tour"
        static let tourHides = "hints.hides"
    }

    /// The saved settings. A missing or unknown value gives the default.
    public init(from store: some SettingsStore) {
        self.init()
        if let v = store.string(forKey: Key.shuffle).flatMap({ Bool($0) }) { shuffle = v }
        if let v = store.string(forKey: Key.repeatMode).flatMap(RepeatMode.init(rawValue:)) { repeatMode = v }
        if let v = store.string(forKey: Key.albumArt).flatMap(AlbumArt.init(rawValue:)) { albumArt = v }
        if let v = store.string(forKey: Key.deviceColor).flatMap(DeviceColor.init(rawValue:)) { deviceColor = v }
        if let v = store.string(forKey: Key.clicker).flatMap({ Bool($0) }) { clicker = v }
        if let v = store.string(forKey: Key.nowPlayingBar).flatMap({ Bool($0) }) { nowPlayingBar = v }
        if let v = store.string(forKey: Key.service).flatMap(MusicService.init(rawValue:)) { service = v }
        if let v = store.string(forKey: Key.setupDone).flatMap({ Bool($0) }) { setupDone = v }
        if let v = store.string(forKey: Key.hintsDone) {  // the raw values, with commas; unknown ones are dropped
            hintsDone = Set(v.split(separator: ",").compactMap { Hint(rawValue: String($0)) })
        }
        if let v = store.string(forKey: Key.tourOn).flatMap({ Bool($0) }) { tourOn = v }
        if let v = store.string(forKey: Key.tourHides) {  // "tour.play:2,tour.next:1"; unknown ones are dropped
            for pair in v.split(separator: ",") {
                let kv = pair.split(separator: ":")
                if kv.count == 2, let hint = Hint(rawValue: String(kv[0])), let n = Int(kv[1]) { tourHides[hint] = n }
            }
        }
    }

    public func save(to store: some SettingsStore) {
        store.set(String(shuffle), forKey: Key.shuffle)
        store.set(repeatMode.rawValue, forKey: Key.repeatMode)
        store.set(albumArt.rawValue, forKey: Key.albumArt)
        store.set(deviceColor.rawValue, forKey: Key.deviceColor)
        store.set(String(clicker), forKey: Key.clicker)
        store.set(String(nowPlayingBar), forKey: Key.nowPlayingBar)
        store.set(service.rawValue, forKey: Key.service)
        store.set(String(setupDone), forKey: Key.setupDone)
        store.set(hintsDone.map(\.rawValue).sorted().joined(separator: ","), forKey: Key.hintsDone)
        store.set(String(tourOn), forKey: Key.tourOn)
        store.set(tourHides.map { "\($0.key.rawValue):\($0.value)" }.sorted().joined(separator: ","), forKey: Key.tourHides)
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
            v.nowPlayingBar = nowPlayingBar
            v.service = service
            v.setupDone = setupDone
            v.hintsDone = hintsDone
            (v.tourOn, v.tourHides) = (tourOn, tourHides)
            return v
        }
        set {
            (shuffle, repeatMode, albumArt, deviceColor, clicker) =
                (newValue.shuffle, newValue.repeatMode, newValue.albumArt, newValue.deviceColor, newValue.clicker)
            nowPlayingBar = newValue.nowPlayingBar
            service = newValue.service
            setupDone = newValue.setupDone
            hintsDone = newValue.hintsDone
            (tourOn, tourHides) = (newValue.tourOn, newValue.tourHides)
        }
    }
}
