import Testing
@testable import ClasifyCore

/// CLA-202: the core knows its platform. The Mac keeps everything; the phone turns Mac things off.
@Suite struct PlatformTests {
    func on(_ platform: Platform, _ s: AppState) -> AppState {
        var s = s
        s.platform = platform
        return s
    }

    @Test func theMacIsTheDefaultAndHasEverything() {
        #expect(AppState().platform == .mac && AppState().features == Features(.mac))
        let f = Features(.mac)
        #expect(f.services == [.spotify, .appleMusic, .local] && f.serviceChoice)
        #expect(f.menuBar && f.views3D && f.wheelVolume && f.search)
        let phone = Features(.phone)
        #expect(phone.services == [.appleMusic] && !phone.serviceChoice)
        #expect(!phone.menuBar && !phone.views3D && !phone.wheelVolume && !phone.search)
    }

    @Test func theMacKeepsTodaysRows() {
        var s = mainMenu()
        s.searchOn = true
        #expect(s.rows(for: Frame(screen: .settings))
            == [.service, .shuffle, .repeatMode, .albumArt, .deviceColor, .clicker, .menuBar, .about, .logOut])
        #expect(s.rows(for: Frame(screen: .main)).suffix(2) == [.search, .settings])
        s.hintsTrial = true
        #expect(s.tourSteps == [.tourPlay, .tourNext, .tourMenu, .tourTurn, .tourMenuBar])
    }

    @Test func thePhoneHasNoServiceMenuBarOrSearchRow() {
        var s = on(.phone, mainMenu())
        s.searchOn = true
        #expect(s.rows(for: Frame(screen: .settings)) == [.shuffle, .repeatMode, .albumArt, .deviceColor, .clicker, .about, .logOut])
        #expect(!s.rows(for: Frame(screen: .main)).contains(.search))
    }

    @Test func thePhoneTourHasNoTurnOrMenuBarStep() {
        var s = on(.phone, mainMenu())
        s.hintsTrial = true
        #expect(s.tourSteps == [.tourPlay, .tourNext, .tourMenu])
    }

    @Test func theMacMenuBarClick3DAndVolumeWorkAsToday() {
        var s = mainMenu()
        #expect(send(&s, .menuBarClick(shown: true)) == [.hideWindow])
        send(&s, .deviceTurned(true))
        #expect(s.deviceTurned)
        send(&s, .deviceTurned(false), .view3D(.turn, open: true))
        #expect(s.viewOpen[.turn] != nil)
    }

    @Test func thePhoneIgnoresMenuBarClicksAnd3D() {
        var s = on(.phone, mainMenu())
        let before = s
        #expect(send(&s, .menuBarClick(shown: true), .menuBarClick(shown: false)).isEmpty)
        #expect(send(&s, .deviceTurned(true), .view3D(.turn, open: true), .view3D(.apart, open: true)).isEmpty)
        #expect(s == before && !s.deviceTurned && s.viewOpen.isEmpty && s.today == nil)
    }

    @Test func thePhoneWheelOnNowPlayingSetsNoVolume() {
        var mac = playing()
        send(&mac, .menu, .wheel(-1), .select)  // Now Playing
        #expect(mac.top.screen == .now && send(&mac, .wheel(-2)) == [.setVolume(50)])
        var s = on(.phone, playing())
        send(&s, .menu, .wheel(-1), .select)
        let volume = s.volume
        #expect(s.top.screen == .now && send(&s, .wheel(-2)).isEmpty && s.volume == volume)
    }

    @Test func aResetAndTheSettingsKeepThePlatform() {
        var s = on(.phone, mainMenu())
        s.settings = AppState().settings
        #expect(s.platform == .phone)
        send(&s, .reset)
        #expect(s.platform == .phone)
    }

    @MainActor @Test func theStoreTakesThePlatform() {
        #expect(Store(player: FakePlayer(), library: FakeLibrary()).state.platform == .mac)
        #expect(Store(player: FakePlayer(), library: FakeLibrary(), platform: .phone).state.platform == .phone)
    }
}
