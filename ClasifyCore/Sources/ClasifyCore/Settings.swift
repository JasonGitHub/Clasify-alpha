import Foundation

/// The music service that Clasify plays from. One service is active at a time (CLA-103): no
/// mixed lists or queues.
public enum MusicService: String, CaseIterable, Sendable {
    case spotify = "Spotify", appleMusic = "Apple Music"
    /// CLA-179, card CR: the songs of the Music app library on this Mac. Only with `local.on`.
    case local = "On This Mac"

    /// The next value of the Settings "Service" row, in a loop (card BM, change 256; card CR):
    /// Spotify, Apple Music, then On This Mac when `localOn`.
    public func next(localOn: Bool) -> MusicService {
        switch self {
        case .spotify: .appleMusic
        case .appleMusic: localOn ? .local : .spotify
        case .local: .spotify
        }
    }
}

/// The settings that stay after a restart: Shuffle, Repeat, Album Art, Color (the device color),
/// Clicker, Now Playing Bar, Menu Bar and Service, whether the first launch setup ended, and the first-time hints
/// that ended (card BA).
public struct Settings: Equatable, Sendable {
    public var shuffle = false
    public var repeatMode = RepeatMode.off
    public var albumArt = AlbumArt.all
    /// Black by default (Jason 15:33 JST 11-22). A Mac that set up with no saved color keeps
    /// Silver, the default it set up on.
    public var deviceColor = DeviceColor.black
    public var clicker = true
    public var nowPlayingBar = false
    /// Card AN.1 (CLA-43, change 346): the menu bar icon that shows and hides myPod. On by default.
    public var menuBar = true
    public var service = MusicService.spotify
    /// CLA-179: the test switch for local music, UserDefaults `local.on`, off by default. Read
    /// only: Clasify never writes it. Off, a saved On This Mac service is Spotify.
    public var localOn = false
    /// CLA-183: the test switch for Search on the device, UserDefaults `search.on`, off by
    /// default. Read only, like `localOn`.
    public var searchOn = false
    public var setupDone = false
    public var hintsDone: Set<Hint> = []
    public var tourOn = false
    public var tourHides: [Hint: Int] = [:]
    /// The beta whose warning showed, by its signing time (card BI v2, change 233).
    public var betaWarned: Double?
    /// The newest beta build that a check found, and the newest whose notice showed (card BV).
    public var newBeta: Int?, betaNoticed: Int?
    /// CLA-140: this Mac activated (`AppState.activated`).
    public var activated = false
    /// The device arrived once, at the first launch ever (card BR, change 288). True by default;
    /// a store with no saved value gives false, so a new Mac sees the arrival once.
    public var arrived = true
    /// CLA-97: `AppState.firstLaunchAt` and `AppState.firstSongSent`.
    public var firstLaunchAt: Double?
    public var firstSongSent = false
    /// CLA-181: `AppState.hintStartSent`.
    public var hintStartSent = false
    /// CLA-97: `AppState.lastBuild`.
    public var lastBuild: Int?
    /// CLA-97: `AppState.today`.
    public var today: DayUse?

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
        static let localOn = "local.on"
        static let searchOn = "search.on"
        static let setupDone = "setup.done"
        static let hintsDone = "hints.done"
        static let tourOn = "hints.tour"
        static let tourHides = "hints.hides"
        static let betaWarned = "beta.warned"
        static let newBeta = "beta.newest"
        static let betaNoticed = "beta.noticed"
        static let activated = "activate.done"
        static let arrived = "arrive.done"
        static let firstLaunchAt = "analytics.firstLaunch"
        static let firstSongSent = "analytics.firstSong"
        static let hintStartSent = "analytics.hintStart"
        static let lastBuild = "analytics.lastBuild"
        static let today = "analytics.day"
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
        // `defaults write … local.on -bool YES` reads back as "1", `-string true` as "true".
        localOn = ["true", "1"].contains(store.string(forKey: Key.localOn))
        if service == .local && !localOn { service = .spotify }
        searchOn = ["true", "1"].contains(store.string(forKey: Key.searchOn))
        if let v = store.string(forKey: Key.setupDone).flatMap({ Bool($0) }) { setupDone = v }
        if setupDone && store.string(forKey: Key.deviceColor).flatMap(DeviceColor.init(rawValue:)) == nil { deviceColor = .silver }
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
        activated = store.string(forKey: Key.activated).flatMap { Bool($0) } ?? false
        arrived = store.string(forKey: Key.arrived).flatMap { Bool($0) } ?? false
        firstLaunchAt = store.string(forKey: Key.firstLaunchAt).flatMap { Double($0) }
        firstSongSent = store.string(forKey: Key.firstSongSent).flatMap { Bool($0) } ?? false
        hintStartSent = store.string(forKey: Key.hintStartSent).flatMap { Bool($0) } ?? false
        lastBuild = store.string(forKey: Key.lastBuild).flatMap { Int($0) }
        today = store.string(forKey: Key.today).flatMap { DayUse(saved: $0) }
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
        store.set(String(activated), forKey: Key.activated)
        store.set(String(arrived), forKey: Key.arrived)
        store.set(firstLaunchAt.map { String($0) }, forKey: Key.firstLaunchAt)
        store.set(firstSongSent ? "true" : nil, forKey: Key.firstSongSent)  // only once it went out
        store.set(hintStartSent ? "true" : nil, forKey: Key.hintStartSent)
        store.set(lastBuild.map { String($0) }, forKey: Key.lastBuild)
        store.set(today?.saved, forKey: Key.today)
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
            v.localOn = localOn
            v.searchOn = searchOn
            v.setupDone = setupDone
            v.hintsDone = hintsDone
            (v.tourOn, v.tourHides) = (tourOn, tourHides)
            v.betaWarned = betaWarned
            (v.newBeta, v.betaNoticed) = (newBeta, betaNoticed)
            v.activated = activated
            v.arrived = arrived
            (v.firstLaunchAt, v.firstSongSent, v.lastBuild, v.today) = (firstLaunchAt, firstSongSent, lastBuild, savedToday)
            v.hintStartSent = hintStartSent
            return v
        }
        set {
            (shuffle, repeatMode, albumArt, deviceColor, clicker) =
                (newValue.shuffle, newValue.repeatMode, newValue.albumArt, newValue.deviceColor, newValue.clicker)
            (nowPlayingBar, menuBar) = (newValue.nowPlayingBar, newValue.menuBar)
            service = newValue.service
            localOn = newValue.localOn
            searchOn = newValue.searchOn
            setupDone = newValue.setupDone
            hintsDone = newValue.hintsDone
            (tourOn, tourHides) = (newValue.tourOn, newValue.tourHides)
            betaWarned = newValue.betaWarned
            (newBeta, betaNoticed) = (newValue.newBeta, newValue.betaNoticed)
            activated = newValue.activated
            arrived = newValue.arrived
            (firstLaunchAt, firstSongSent, lastBuild, today) = (newValue.firstLaunchAt, newValue.firstSongSent, newValue.lastBuild, newValue.today)
            hintStartSent = newValue.hintStartSent
            savedToday = newValue.today
        }
    }
}
