import Foundation

/// The music service that Clasify plays from. One service is active at a time (CLA-103): no
/// mixed lists or queues.
public enum MusicService: String, CaseIterable, Sendable {
    case spotify = "Spotify", appleMusic = "Apple Music"

    /// The other service: the Settings "Service" row flips between the two (card BM, change 256).
    public var other: MusicService { self == .spotify ? .appleMusic : .spotify }
}

/// The settings that stay after a restart: Shuffle, Repeat, Album Art, Color (the device color),
/// Clicker, Now Playing Bar, Menu Bar and Service, whether the first launch setup ended, and the first-time hints
/// that ended (card BA).
public struct Settings: Equatable, Sendable {
    public var shuffle = false
    public var repeatMode = RepeatMode.off
    public var albumArt = AlbumArt.all
    public var deviceColor = DeviceColor.silver
    public var clicker = true
    public var nowPlayingBar = false
    /// Card AN.1 (CLA-43, change 346): the menu bar icon that shows and hides myPod. On by default.
    public var menuBar = true
    public var service = MusicService.spotify
    public var setupDone = false
    public var hintsDone: Set<Hint> = []
    public var tourOn = false
    public var tourHides: [Hint: Int] = [:]
    /// The beta whose warning showed, by its signing time (card BI v2, change 233).
    public var betaWarned: Double?
    /// The newest beta build that a check found, and the newest whose notice showed (card BV).
    public var newBeta: Int?, betaNoticed: Int?
    /// CLA-128: setup has the Activate step. Off until the server is live.
    public var activateOn = false
    /// CLA-140: this Mac activated (`AppState.activated`).
    public var activated = false
    /// The device arrived once, at the first launch ever (card BR, change 288). True by default;
    /// a store with no saved value gives false, so a new Mac sees the arrival once.
    public var arrived = true
    /// CLA-97: `AppState.firstLaunchAt` and `AppState.firstSongSent`.
    public var firstLaunchAt: Double?
    public var firstSongSent = false
    /// CLA-97: `AppState.lastBuild`.
    public var lastBuild: Int?

    public init() {}

    /// The keys in the settings store. Each value is a string: "true" or "false", or a raw value.
    enum Key {
        static let shuffle = "settings.shuffle"
        static let repeatMode = "settings.repeat"
        static let albumArt = "settings.albumArt"
        static let deviceColor = "settings.deviceColor"
        static let clicker = "settings.clicker"
        static let nowPlayingBar = "settings.nowPlayingBar"
        static let menuBar = "settings.menuBar"
        static let service = "settings.service"
        static let setupDone = "setup.done"
        static let hintsDone = "hints.done"
        static let tourOn = "hints.tour"
        static let tourHides = "hints.hides"
        static let betaWarned = "beta.warned"
        static let newBeta = "beta.newest"
        static let betaNoticed = "beta.noticed"
        // CLA-128: NOT for testers. `defaults write ... activate.on false` turns the gate off.
        // Before the beta build it becomes a build setting, or it goes away.
        static let activateOn = "activate.on"
        static let activated = "activate.done"
        // CLA-145: NOT for testers; removed before the real beta (CLA-134), when the hardware ID
        // is always on. Read only; the app never writes it. See `DeviceID.current`.
        static let activateHardwareID = "activate.hardwareID"
        static let arrived = "arrive.done"
        static let firstLaunchAt = "analytics.firstLaunch"
        static let firstSongSent = "analytics.firstSong"
        static let lastBuild = "analytics.lastBuild"
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
        if let v = store.string(forKey: Key.menuBar).flatMap({ Bool($0) }) { menuBar = v }
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
        betaWarned = store.string(forKey: Key.betaWarned).flatMap { Double($0) }
        newBeta = store.string(forKey: Key.newBeta).flatMap { Int($0) }
        betaNoticed = store.string(forKey: Key.betaNoticed).flatMap { Int($0) }
        if let v = store.string(forKey: Key.activateOn).flatMap({ Bool($0) }) { activateOn = v }
        activated = store.string(forKey: Key.activated).flatMap { Bool($0) } ?? false
        arrived = store.string(forKey: Key.arrived).flatMap { Bool($0) } ?? false
        firstLaunchAt = store.string(forKey: Key.firstLaunchAt).flatMap { Double($0) }
        firstSongSent = store.string(forKey: Key.firstSongSent).flatMap { Bool($0) } ?? false
        lastBuild = store.string(forKey: Key.lastBuild).flatMap { Int($0) }
    }

    /// CLA-145: `activate.hardwareID` "true" makes the device ID from the hardware. Off by
    /// default (Jason's choice, 18:30 JST 11-19): then the random Keychain ID stays in use.
    public static func hardwareIDOn(from store: some SettingsStore) -> Bool {
        store.string(forKey: Key.activateHardwareID).flatMap { Bool($0) } ?? false
    }

    public func save(to store: some SettingsStore) {
        store.set(String(shuffle), forKey: Key.shuffle)
        store.set(repeatMode.rawValue, forKey: Key.repeatMode)
        store.set(albumArt.rawValue, forKey: Key.albumArt)
        store.set(deviceColor.rawValue, forKey: Key.deviceColor)
        store.set(String(clicker), forKey: Key.clicker)
        store.set(String(nowPlayingBar), forKey: Key.nowPlayingBar)
        store.set(String(menuBar), forKey: Key.menuBar)
        store.set(service.rawValue, forKey: Key.service)
        store.set(String(setupDone), forKey: Key.setupDone)
        store.set(hintsDone.map(\.rawValue).sorted().joined(separator: ","), forKey: Key.hintsDone)
        store.set(String(tourOn), forKey: Key.tourOn)
        store.set(tourHides.map { "\($0.key.rawValue):\($0.value)" }.sorted().joined(separator: ","), forKey: Key.tourHides)
        store.set(betaWarned.map { String($0) }, forKey: Key.betaWarned)
        store.set(newBeta.map { String($0) }, forKey: Key.newBeta)
        store.set(betaNoticed.map { String($0) }, forKey: Key.betaNoticed)
        store.set(String(activateOn), forKey: Key.activateOn)
        store.set(String(activated), forKey: Key.activated)
        store.set(String(arrived), forKey: Key.arrived)
        store.set(firstLaunchAt.map { String($0) }, forKey: Key.firstLaunchAt)
        store.set(firstSongSent ? "true" : nil, forKey: Key.firstSongSent)  // only once it went out
        store.set(lastBuild.map { String($0) }, forKey: Key.lastBuild)
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
            (v.nowPlayingBar, v.menuBar) = (nowPlayingBar, menuBar)
            v.service = service
            v.setupDone = setupDone
            v.hintsDone = hintsDone
            (v.tourOn, v.tourHides) = (tourOn, tourHides)
            v.betaWarned = betaWarned
            (v.newBeta, v.betaNoticed) = (newBeta, betaNoticed)
            (v.activateOn, v.activated) = (activateOn, activated)
            v.arrived = arrived
            (v.firstLaunchAt, v.firstSongSent, v.lastBuild) = (firstLaunchAt, firstSongSent, lastBuild)
            return v
        }
        set {
            (shuffle, repeatMode, albumArt, deviceColor, clicker) =
                (newValue.shuffle, newValue.repeatMode, newValue.albumArt, newValue.deviceColor, newValue.clicker)
            (nowPlayingBar, menuBar) = (newValue.nowPlayingBar, newValue.menuBar)
            service = newValue.service
            setupDone = newValue.setupDone
            hintsDone = newValue.hintsDone
            (tourOn, tourHides) = (newValue.tourOn, newValue.tourHides)
            betaWarned = newValue.betaWarned
            (newBeta, betaNoticed) = (newValue.newBeta, newValue.betaNoticed)
            (activateOn, activated) = (newValue.activateOn, newValue.activated)
            arrived = newValue.arrived
            (firstLaunchAt, firstSongSent, lastBuild) = (newValue.firstLaunchAt, newValue.firstSongSent, newValue.lastBuild)
        }
    }
}
