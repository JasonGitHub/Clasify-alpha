/// CLA-202: the device that the app runs on. The app gives it to the `Store` at start; it is not
/// saved, and a reset or a log out keeps it. ClasifyCore has no `#if os`, so Linux CI tests both.
public enum Platform: Sendable {
    case mac, phone
}

/// CLA-202: what the platform has. The Mac has everything. The first iPhone version is Apple
/// Music with the 2D device only (plan "What changes on a phone"). Computed, never stored.
public struct Features: Equatable, Sendable {
    /// The services a person can use, in no order. More than one: the Service row and Pick Your Music.
    public var services: [MusicService]
    /// The menu bar icon: the Settings Menu Bar row, the tour's menu bar step, `.menuBarClick`.
    public var menuBar: Bool
    /// The 3D device: the tour's turn step, `.view3D` and `.deviceTurned`.
    public var views3D: Bool
    /// The Now Playing wheel sets the output volume (`.setVolume`).
    public var wheelVolume: Bool
    /// The main menu's Search row (with `search.on`).
    public var search: Bool
    /// Activate (card BW) and its server checks. TestFlight and the App Store do this on the phone.
    public var activation: Bool
    /// The beta's end, its warning and the new-beta notice (Beta Soon, Ended, New; Get New Beta).
    public var betaNotices: Bool

    public init(_ platform: Platform) {
        let mac = platform == .mac
        services = mac ? MusicService.allCases : [.appleMusic]
        (menuBar, views3D, wheelVolume, search, activation, betaNotices) = (mac, mac, mac, mac, mac, mac)
    }

    public var serviceChoice: Bool { services.count > 1 }
}

extension AppState {
    public init(platform: Platform) {
        self.init()
        self.platform = platform
    }

    public var features: Features { Features(platform) }

    /// The screen that the music service's login prompt shows over: Pick Your Music, or on the
    /// phone (one service, no pick) the color pick, whose press starts the Apple Music login.
    var promptScreen: Screen { features.serviceChoice ? .pickMusic : .color }
}
