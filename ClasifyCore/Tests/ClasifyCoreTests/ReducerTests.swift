import Testing
@testable import ClasifyCore

func tracks(_ p: String, _ n: Int, _ d: Double) -> [Track] {
    (0..<n).map { Track(id: "\(p)\($0)", title: "\(p)\($0)", artist: "x", duration: d) }
}

let liked = Playlist(id: Playlist.likedSongsID, name: "Liked Songs", tracks: tracks("l", 2, 10))
let focus = Playlist(id: "focus", name: "Focus", tracks: tracks("f", 8, 30))
let library = [liked, focus]
/// Focus as the playlist list has it: a name and a count, no tracks.
let focusInfo = Playlist(id: "focus", name: "Focus", tracks: [], trackCount: 8)

/// Opens Playlists (under Cover Flow), then Focus, with fresh reads that use tokens `first` and `first + 1`.
func openFocus(_ first: Int) -> [Action] {
    [.wheel(1), .select, .playlistsLoaded(token: first, playlists: [focusInfo]),
     .select, .tracksLoaded(token: first + 1, playlist: "focus", tracks: focus.tracks)]
}

@discardableResult
func send(_ s: inout AppState, _ actions: Action..., now: Double = 100) -> [Effect] {
    let e = Dependencies(now: { now }, random: { _ in 0 })
    return actions.flatMap { reduce(&s, $0, e) }
}

@discardableResult
func send(_ s: inout AppState, _ actions: [Action]) -> [Effect] {
    let e = Dependencies(now: { 100 }, random: { _ in 0 })
    return actions.flatMap { reduce(&s, $0, e) }
}

/// A later launch: the first launch setup ended before, so the login screen shows first.
func afterSetup() -> AppState {
    var s = AppState()
    s.setupDone = true
    return s
}

/// Signed in on the main menu. Nothing of the library is read yet. A press on "You’re in"
/// goes on at once.
func mainMenu() -> AppState {
    var s = afterSetup()
    send(&s, .select, .authDone(token: 1, ok: true), .select)
    return s
}

/// Playing Focus track `i` on the Now Playing screen.
func playing(_ i: Int = 0) -> AppState {
    var s = mainMenu()
    send(&s, openFocus(1))
    send(&s, .wheel(i), .select)
    return s
}

@Suite struct ReducerTests {
    /// CLA-48: a trackpad scroll moves a list with the fingers, and a bar the other way.
    @Test func theWheelMovesABarOnlyOnNowPlaying() {
        var s = playing()
        #expect(s.top.screen == .now && s.wheelMovesBar)
        send(&s, .select)  // the time bar
        #expect(s.nowMode == .scrub && s.wheelMovesBar)
        send(&s, .menu, .menu)  // the time bar ends, then the song list
        #expect(s.top.screen == .tracks(playlist: "focus") && !s.wheelMovesBar)
        #expect(!mainMenu().wheelMovesBar && !afterSetup().wheelMovesBar)
    }

    @Test func wheelMovesSelectionScrollsAndSetsVolume() {
        var s = mainMenu()
        send(&s, .wheel(-3))
        #expect(s.top.sel == 0)
        send(&s, .wheel(99))
        #expect(s.top.sel == 5)  // clamped to last row

        s = playing()
        send(&s, .menu, .wheel(7))  // back to Focus tracks: 5 rows, with the bar too
        #expect(s.top.sel == 7 && s.top.off == 3)
        send(&s, .menu, .menu)
        #expect(s.rows(for: s.top)[s.top.sel] == .playlists)  // the row picked before the song played
        send(&s, .wheel(-2), .select)  // Now Playing, at the top
        #expect(send(&s, .wheel(-2)) == [.setVolume(50)])
        #expect(s.overlayUntil == 101.5)
        #expect(send(&s, .select, .wheel(2)) == [.seek(10, generation: 2)])  // scrub
    }

    @Test func listKeepsTheSelectionInTheRowsThatShow() {
        var s = mainMenu()
        send(&s, openFocus(1))
        send(&s, .wheel(7))
        #expect(s.shownRows == 5 && s.top.sel == 7 && s.top.off == 3)
        send(&s, .select, .menu)  // play track 7, then back: the bar shows, the rows stay
        #expect(s.showsBar && s.shownRows == 5 && s.top.sel == 7 && s.top.off == 3)
        send(&s, .wheel(-1))  // the selection moves up, the rows stay
        #expect(s.top.sel == 6 && s.top.off == 3)
        send(&s, .wheel(-6))
        #expect(s.top.sel == 0 && s.top.off == 0)
    }

    @Test func selectPushesScreensAndTogglesSettings() {
        var s = mainMenu()
        send(&s, .wheel(5), .select)
        #expect(s.top.screen == .settings)
        send(&s, .select, .wheel(1), .select, .select)
        #expect(s.shuffle && s.repeatMode == .one)
        send(&s, .wheel(1), .select)
        #expect(s.albumArt == .nowPlaying && s.skin == .pocket && s.toast.isEmpty)  // All, then Now Playing
        #expect(!s.isHalf(.main) && !s.isHalf(.playlists) && s.showsNowPlayingArt)
        send(&s, .select)
        #expect(s.albumArt == .off && !s.isHalf(.main) && !s.showsNowPlayingArt)
        send(&s, .select)
        #expect(s.albumArt == .all && s.isHalf(.main) && s.isHalf(.playlists) && s.showsNowPlayingArt)
        #expect(!s.rows(for: s.top).contains(.skin))  // only the Pocket skin in 1.0
        #expect(s.rows(for: s.top).count == 7)  // no Playback engine, EQ or Skin row in 1.0
    }

    @Test func deviceColorGoesSilverBlackSilver() {
        var s = mainMenu()
        send(&s, .wheel(5), .select)
        #expect(s.rows(for: s.top) == [.shuffle, .repeatMode, .albumArt, .deviceColor, .clicker, .about, .logOut])
        #expect(s.deviceColor == .silver)  // the default
        send(&s, .wheel(3), .select)
        #expect(s.deviceColor == .black && s.top.screen == .settings)
        send(&s, .select)
        #expect(s.deviceColor == .silver)
        s.deviceColor = .black
        send(&s, .reset)
        #expect(s.deviceColor == .black)  // a saved setting: a reset keeps it
    }

    @Test func aboutShowsTheNextSceneEachTimeItOpens() {
        var s = mainMenu()
        send(&s, .wheel(5), .select, .wheel(5))  // Settings, on the About row
        #expect(s.rows(for: s.top)[s.top.sel] == .about && s.aboutScene == 0)
        var scenes: [Int] = []
        for _ in 0..<4 {
            send(&s, .select)
            #expect(s.top.screen == .about)
            scenes.append(s.aboutScene)
            send(&s, .menu)
        }
        #expect(scenes == [0, 1, 2, 0])  // the castle, the takoyaki, Dotonbori, then the castle again
        send(&s, .reset)
        #expect(s.aboutOpens == 4)  // a reset keeps the count
    }

    @Test func batteryChangedSetsTheBatteryAndAResetKeepsIt() {
        var s = mainMenu()
        #expect(s.battery == nil)  // not read yet, or a Mac with no battery
        let half = Battery(level: 0.5, charging: true, onPower: true)
        #expect(send(&s, .batteryChanged(half)).isEmpty)
        #expect(s.battery == half && !half.low)
        send(&s, .reset)
        #expect(s.battery == half)  // the Mac's battery does not change on a reset
        send(&s, .batteryChanged(nil))
        #expect(s.battery == nil)
        #expect(Battery(level: 0.19, charging: false, onPower: false).low)
        #expect(Battery(level: 1.3, charging: false, onPower: true).level == 1)  // kept in 0...1
    }

    @Test func selectTrackLoadsAndPlays() {
        var s = mainMenu()
        send(&s, openFocus(1))
        send(&s, .wheel(3))
        let load: [Effect] = [.setShuffle(false), .setRepeat(.off), .load(trackID: "f3", context: "focus", autoplay: true, generation: 1)]
        #expect(send(&s, .select) == load)
        #expect(s.top.screen == .now && s.isPlaying && s.current == TrackRef(playlist: "focus", track: "f3"))
    }

    /// CLA-61: Play with nothing to resume plays Liked Songs and opens Now Playing, with no toast.
    @Test func playWithNothingToResumePlaysLikedSongs() {
        // Shuffle off, Liked Songs not read yet: it loads, then the first song plays in order.
        var s = mainMenu()
        #expect(send(&s, .play) == [.fetchTracks(token: 1, playlist: Playlist.likedSongsID)])
        #expect(s.top.screen == .tracks(playlist: Playlist.likedSongsID) && s.toast == "")
        let first: [Effect] = [.setShuffle(false), .setRepeat(.off), .load(trackID: "l0", context: "liked", autoplay: true, generation: 1)]
        #expect(send(&s, .tracksLoaded(token: 1, playlist: Playlist.likedSongsID, tracks: liked.tracks)) == first)
        #expect(s.top.screen == .now && s.isPlaying && !s.shuffle && s.current == TrackRef(playlist: "liked", track: "l0"))

        // Shuffle on, Liked Songs read: it shuffles at once, as Shuffle Songs does.
        s = mainMenu()
        send(&s, .toggleShuffle, .wheel(3), .select, .tracksLoaded(token: 1, playlist: Playlist.likedSongsID, tracks: liked.tracks), .menu, .menu)
        #expect(s.top.screen == .main && s.current == nil && s.shuffle)
        let shuffled: [Effect] = [.setShuffle(true), .setRepeat(.off), .load(trackID: "l0", context: "liked", autoplay: true, generation: 1)]
        #expect(send(&s, .play) == shuffled)
        #expect(s.top.screen == .now && s.isPlaying && s.toast == "")

        // Shuffle Songs after an in-order Play still shuffles.
        s = mainMenu()
        send(&s, .play, .menu, .wheel(4), .select)
        send(&s, .tracksLoaded(token: 2, playlist: Playlist.likedSongsID, tracks: liked.tracks))
        #expect(s.top.screen == .now && s.shuffle)

        // No songs in Liked Songs: nothing plays, quietly.
        s = mainMenu()
        let none = Playlist(id: Playlist.likedSongsID, name: "Liked Songs", tracks: [])
        send(&s, .play, .tracksLoaded(token: 1, playlist: Playlist.likedSongsID, tracks: none.tracks))
        #expect(s.current == nil && s.top.screen == .tracks(playlist: Playlist.likedSongsID) && s.toast == "")

        // Offline: the usual toast, no read.
        s = mainMenu()
        send(&s, .offline(true))
        #expect(send(&s, .play) == [] && s.toast == "Offline. Can’t start playback")

        // A Play in the adopt window wins: the late .adopted is dropped.
        s = mainMenu()
        send(&s, .wheel(3), .select, .tracksLoaded(token: 1, playlist: Playlist.likedSongsID, tracks: liked.tracks), .menu, .play)
        send(&s, .adopted(track: "x9", playlist: nil, playing: true, position: 30, generation: 0))
        #expect(s.current == TrackRef(playlist: "liked", track: "l0"))

        // Not during setup or at login.
        s = afterSetup()
        #expect(send(&s, .play) == [] && s.current == nil)
    }

    @Test func shuffleSongsLoadsLikedSongsFirst() {
        var s = mainMenu()  // fresh sign-in: nothing read yet
        #expect(send(&s, .wheel(4), .select) == [.fetchTracks(token: 1, playlist: Playlist.likedSongsID)])
        #expect(s.top.screen == .tracks(playlist: Playlist.likedSongsID) && s.top.loading)
        let load: [Effect] = [.setShuffle(true), .setRepeat(.off), .load(trackID: "l0", context: "liked", autoplay: true, generation: 1)]
        #expect(send(&s, .tracksLoaded(token: 1, playlist: Playlist.likedSongsID, tracks: liked.tracks)) == load)
        #expect(s.top.screen == .now && s.shuffle && s.shuffleToken == nil)
        send(&s, .menu, .menu)  // back to Shuffle Songs, one row lower under Now Playing
        #expect(s.rows(for: s.top)[s.top.sel] == .shuffleSongs)
        // Liked Songs is read now, so the next shuffle starts at once.
        #expect(send(&s, .select).contains(.load(trackID: "l0", context: "liked", autoplay: true, generation: 2)))

        s = mainMenu()
        send(&s, .wheel(4), .select, .tracksLoaded(token: 1, playlist: Playlist.likedSongsID, tracks: nil))  // read fails
        #expect(s.top.error)
        send(&s, .select, .tracksLoaded(token: 2, playlist: Playlist.likedSongsID, tracks: liked.tracks))  // retry succeeds and still shuffles
        #expect(s.top.screen == .now && s.shuffle && s.current?.track == "l0")
    }

    @Test func selectOnErrorRetriesWithNewToken() {
        var s = mainMenu()
        #expect(send(&s, .wheel(1), .select) == [.fetchPlaylists(token: 1)])
        send(&s, .playlistsLoaded(token: 1, playlists: nil))
        #expect(s.top.error && !s.playlistsLoaded)
        #expect(send(&s, .select) == [.fetchPlaylists(token: 2)])
        #expect(s.top.loading && !s.top.error && s.top.token == 2)
        send(&s, .playlistsLoaded(token: 2, playlists: [focusInfo]), .select)
        send(&s, .tracksLoaded(token: 3, playlist: "focus", tracks: nil))
        #expect(send(&s, .select) == [.fetchTracks(token: 4, playlist: "focus")])
    }

    @Test func menuPopsButNotFromRoot() {
        var s = afterSetup()
        send(&s, .menu)
        #expect(s.stack.count == 1)

        s = playing()
        send(&s, .select, .menu)  // leave scrub first
        #expect(s.top.screen == .now && s.nowMode == .volume)
        send(&s, .menu)
        #expect(s.top.screen == .tracks(playlist: "focus"))
    }

    @Test func playTogglesAndBlocksResumeOffline() {
        var s = playing()
        #expect(send(&s, .play) == [.pause] && !s.isPlaying)
        send(&s, .offline(true))
        #expect(send(&s, .play) == [] && s.toast == "Offline. Can’t resume")
    }

    @Test func nextAndPrevSkipInTheEngine() {
        var s = playing(6)
        #expect(send(&s, .next) == [.next(generation: 2)] && s.current?.track == "f6")  // moves on `.trackChanged`
        send(&s, .position(130, generation: 1))  // from before the skip
        send(&s, .trackChanged("f7", playing: true, generation: 2))
        #expect(s.current?.track == "f7" && s.t == 0)
        #expect(send(&s, .prev) == [.prev(generation: 3)])
        s.repeatMode = .all; s.shuffle = true
        #expect(send(&s, .next) == [.next(generation: 4)])  // the engine applies shuffle and repeat
        s = playing(3)
        send(&s, .offline(true))
        #expect(send(&s, .next, .prev) == [] && s.current?.track == "f3" && s.toast == "Offline. Can’t start playback")
    }

    @Test func shuffleAndRepeatSettingsGoToEngine() {
        var s = mainMenu()
        send(&s, .wheel(5), .select)  // Settings
        #expect(send(&s, .select) == [.setShuffle(true)])
        #expect(send(&s, .wheel(1), .select) == [.setRepeat(.all)])
        #expect(send(&s, .select) == [.setRepeat(.one)])
        #expect(send(&s, .select) == [.setRepeat(.off)])
    }

    @Test func centerStepsThroughTheNowPlayingSliders() {
        var s = playing()
        send(&s, .select)
        #expect(s.nowMode == .scrub && s.overlayUntil == 106)
        send(&s, .select)
        #expect(s.nowMode == .shuffle)
        #expect(send(&s, .wheel(1)) == [.setShuffle(true)] && s.shuffle)
        #expect(send(&s, .wheel(2)) == [])  // already at Songs
        #expect(send(&s, .wheel(-1)) == [.setShuffle(false)] && !s.shuffle)
        send(&s, .select)
        #expect(s.nowMode == .repeatMode)
        #expect(send(&s, .wheel(1)) == [.setRepeat(.one)])  // the slider goes Off, One, All
        #expect(send(&s, .wheel(3)) == [.setRepeat(.all)])  // one stop for each step
        #expect(send(&s, .wheel(1)) == [])
        #expect(send(&s, .wheel(-1)) == [.setRepeat(.one)])
        send(&s, .select)
        #expect(s.nowMode == .volume && s.overlayUntil == 101.5)  // the volume bar shows briefly
    }

    @Test func slidersGoBackToTheProgressBarAfterSixSeconds() {
        var s = playing()
        send(&s, .select, .select)  // the shuffle slider, until 106
        send(&s, .tick, now: 105)
        #expect(s.nowMode == .shuffle)
        send(&s, .wheel(1), now: 105)  // a turn starts the 6 seconds again
        send(&s, .tick, now: 110)
        #expect(s.nowMode == .shuffle && s.overlayUntil == 111)
        send(&s, .tick, now: 111.5)
        #expect(s.nowMode == .volume && s.overlayUntil == 0)
        send(&s, .select, .select, .select, .menu)  // MENU leaves the repeat slider at once
        #expect(s.nowMode == .volume && s.overlayUntil == 0 && s.top.screen == .now)
    }

    @Test func shuffleAndRepeatKeysWorkOnEveryScreen() {
        var s = mainMenu()
        #expect(send(&s, .toggleShuffle) == [.setShuffle(true)] && s.shuffle)
        #expect(send(&s, .cycleRepeat) == [.setRepeat(.all)])
        #expect(send(&s, .cycleRepeat) == [.setRepeat(.one)])
        #expect(send(&s, .cycleRepeat) == [.setRepeat(.off)])
        s = playing()
        #expect(send(&s, .toggleShuffle) == [.setShuffle(true)] && s.top.screen == .now)
    }

    @Test func fastWheelStepsMoveMoreRows() {
        var speed = WheelSpeed()
        let quick = (0..<16).map { speed.rows(at: Double($0) * 0.1) }
        #expect(quick == [1, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 4])
        #expect(speed.rows(at: 10) == 1)  // a pause ends the streak

        var s = mainMenu()
        send(&s, openFocus(1))
        for i in 0..<6 { send(&s, .wheel(1), now: 200 + Double(i) * 0.05) }
        #expect(s.top.sel == 7)  // five steps of 1, then one of 2
        s = playing()
        for i in 0..<8 { send(&s, .wheel(1), now: 200 + Double(i) * 0.05) }
        #expect(s.volume == 100)  // 60 + 8 x 5: on Now Playing each step stays one step
    }

    @Test func theBarShowsOnlyOnSongLists() {
        var s = playing()
        #expect(!s.showsBar && s.shownRows == 9)  // Now Playing
        send(&s, .menu)
        #expect(s.showsBar && s.shownRows == 5)  // five two-line song rows over the bar
        send(&s, .menu)
        #expect(!s.showsBar && s.shownRows == 9)  // Playlists: 9 rows, no bar
        send(&s, .menu)
        #expect(!s.showsBar && s.shownRows == 9)  // the main menu
        s = mainMenu()
        send(&s, openFocus(1))  // a song list with nothing playing: 5 taller rows
        #expect(s.top.screen == .tracks(playlist: "focus") && !s.showsBar && s.shownRows == 5)
    }

    @Test func prevRestartsAfterThreeSecondsElseGoesBack() {
        var s = playing(2)
        send(&s, .position(5, generation: 1))
        #expect(send(&s, .prev) == [.seek(0, generation: 2)] && s.current?.track == "f2")
        #expect(send(&s, .trackEnded(generation: 1)) == [])  // queued before the restart
        #expect(send(&s, .prev) == [.prev(generation: 3)] && s.current?.track == "f2")
    }

    @Test func theScrollBarShowsAfterAStepOrAScreenChange() {
        var s = mainMenu()
        send(&s, .tick, now: 102)
        #expect(s.scrollUntil == 0)
        send(&s, .wheel(3))
        #expect(s.scrollUntil == 100 + scrollBarTime)
        send(&s, .tick, now: 101)
        #expect(s.scrollUntil == 101.5)  // still showing
        send(&s, .tick, now: 102)
        #expect(s.scrollUntil == 0)
        send(&s, .select, now: 200)  // Liked Songs opens, and loads first: no list yet
        #expect(s.top.loading && s.scrollUntil == 0)
        send(&s, .tracksLoaded(token: s.top.token, playlist: Playlist.likedSongsID, tracks: liked.tracks), now: 203)
        #expect(s.scrollUntil == 204.5)  // the list shows
        send(&s, .tick, now: 205)
        send(&s, .menu, now: 300)  // back to the main menu
        #expect(s.scrollUntil == 301.5)
        s = playing()
        send(&s, .tick, now: 200)
        send(&s, .wheel(1), now: 300)  // volume on Now Playing: no scroll bar
        #expect(s.scrollUntil == 0)
    }

    /// 20 Liked Songs on 10 albums, and 12 Focus tracks, each on its own album.
    static let likedCovers = Playlist(id: Playlist.likedSongsID, name: "Liked Songs", tracks: (0..<20).map {
        Track(id: "l\($0)", title: "", artist: "x", duration: 30, coverID: "lc\($0 / 2)")
    })
    static let focusCovers = Playlist(id: "focus", name: "Focus", tracks: (0..<12).map {
        Track(id: "f\($0)", title: "", artist: "x", duration: 30, coverID: "fc\($0)")
    })

    @Test func theMainMenuCoversAreRandomAlbumsEachOnce() {
        var s = mainMenu()
        #expect(s.mainArt.isEmpty)
        s.library = library  // no covers in these lists
        s.refreshArt()
        #expect(s.mainArt.isEmpty)
        s.library = [Self.likedCovers, Self.focusCovers]
        s.refreshArt()  // the Playlists row, before any playlist is read: Liked Songs
        let art = s.mainArt
        #expect(art.count == mainArtCount && art.allSatisfy { $0.id.hasPrefix("l") })
        #expect(Set(art.compactMap(\.coverID)).count == art.count)  // each album once
        s.refreshArt()
        #expect(s.mainArt == art)  // the same each time
        s.artSeed = 12345
        s.refreshArt()
        #expect(s.mainArt != art)  // another seed, another order
    }

    @Test func theMainMenuCoversFollowTheSelectedRow() {
        var s = playing(3)
        s.library = [Self.likedCovers, Self.focusCovers]
        s.loadedTracks = ["focus"]
        let e = Dependencies(now: { 100 }, random: { _ in 777 })
        for _ in 0..<3 { reduce(&s, .menu, e) }  // Now Playing, Focus, Playlists, then the main menu
        #expect(s.top.screen == .main && s.artSeed == 777 && s.artRow == s.mainRow)  // new random covers
        s.top.sel = 0; s.artRow = .nowPlaying; s.refreshArt()
        #expect(s.mainArt.map(\.id) == ["f3"])  // Now Playing: the playing cover only
        send(&s, .wheel(2), now: 200)  // past Cover Flow to Playlists
        #expect(s.mainArt.map(\.id) == ["f3"] && s.artUntil == 200 + artDelay)  // not yet
        send(&s, .wheel(1), now: 200.2)  // Albums: a fast scroll waits again
        send(&s, .tick, now: 200.4)
        #expect(s.mainArt.map(\.id) == ["f3"])
        send(&s, .tick, now: 200.6)
        #expect(s.artRow == .albums && s.artUntil == 0)
        #expect(s.mainArt.count == mainArtCount && s.mainArt.allSatisfy { $0.id.hasPrefix("l") })
        send(&s, .wheel(-1), now: 300)
        send(&s, .tick, now: 301)
        #expect(s.artRow == .playlists && s.mainArt.allSatisfy { $0.id.hasPrefix("f") })  // read playlists

        // A track from outside the library: its cover shows when its read comes back.
        s.current = TrackRef(playlist: "radio", track: "zz")
        s.artRow = .nowPlaying; s.refreshArt()
        #expect(s.mainArt.isEmpty)
        s.trackReads.insert("zz")  // the read was asked for
        send(&s, .trackRead("zz", Track(id: "zz", title: "", artist: "x", duration: 30, coverID: "zc")), now: 302)
        #expect(s.mainArt.map(\.id) == ["zz"])
    }

    @Test func thePlaylistsCoversFollowTheSelectedPlaylist() {
        var s = mainMenu()
        let mix = Playlist(id: "mix", name: "Mix", tracks: [], trackCount: 12)
        send(&s, .wheel(1), .select, .playlistsLoaded(token: 1, playlists: [focusInfo, mix]), now: 200)
        #expect(s.top.screen == .playlists && s.halfRow == .playlist("focus"))
        let shown = Self.likedCovers.tracks
        s.mainArt = shown  // the main menu's covers
        #expect(s.artUntil == 200 + artDelay)
        #expect(send(&s, .tick, now: 200.2).isEmpty)  // not yet
        let focusRead = send(&s, .tick, now: 200.4)
        #expect(focusRead == [.readArtTracks(token: s.artTok, playlist: "focus")])
        #expect(s.artRow == .playlist("focus") && s.mainArt == shown)  // the covers stay while it loads
        #expect(send(&s, .tick, now: 201).isEmpty)  // read once
        send(&s, .artTracksRead(token: s.artTok, playlist: "focus", tracks: nil), now: 202)  // the read failed
        #expect(s.mainArt == shown && !s.loadedTracks.contains("focus") && s.artReads["focus"] == nil)
        #expect(send(&s, .tick, now: 203).isEmpty)  // not read again on each tick

        send(&s, .wheel(1), now: 210)  // Mix
        #expect(s.mainArt == shown)
        let mixRead = send(&s, .tick, now: 210.4)
        #expect(mixRead == [.readArtTracks(token: s.artTok, playlist: "mix")])
        send(&s, .artTracksRead(token: s.artTok, playlist: "mix", tracks: Self.focusCovers.tracks), now: 211)
        #expect(s.loadedTracks.contains("mix") && s.readAt["mix"] == 211)
        let mixArt = s.mainArt
        #expect(mixArt.count == mainArtCount && mixArt.allSatisfy { $0.coverID?.hasPrefix("fc") == true })

        send(&s, .wheel(-1), now: 220)  // Focus again: its failed read is tried again
        let againRead = send(&s, .tick, now: 220.4)
        #expect(againRead == [.readArtTracks(token: s.artTok, playlist: "focus")])
        #expect(s.mainArt == mixArt)
        send(&s, .wheel(1), now: 230)  // Mix again: from memory, with no read
        #expect(send(&s, .tick, now: 230.4).isEmpty && s.mainArt == mixArt)
        send(&s, .select, now: 231)  // and it opens with no read
        #expect(s.top.screen == .tracks(playlist: "mix") && !s.top.loading)

        // Offline, or with Album Art off, nothing is read.
        send(&s, .menu, now: 240)
        s.offline = true
        send(&s, .wheel(-1), now: 241)
        s.artReads = [:]
        #expect(send(&s, .tick, now: 241.4).isEmpty && s.artRow == .playlist("focus"))
        let onlineRead = send(&s, .offline(false), now: 242)
        #expect(onlineRead.contains(.readArtTracks(token: s.artTok, playlist: "focus")))  // online again
        s.albumArt = .off
        send(&s, .wheel(1), .wheel(-1), now: 250)
        #expect(send(&s, .tick, now: 251).isEmpty && s.halfRow == nil)
    }

    /// At first open, nothing has read Liked Songs into the state yet, so the main menu reads it
    /// for its covers. The Playlists list keeps one row per playlist.
    @Test func theMainMenuReadsLikedSongsForItsCoversAtFirstOpen() {
        var s = afterSetup()
        #expect(send(&s, .launch, .restored(token: 1, ok: true)).last == .readArtTracks(token: 1, playlist: Playlist.likedSongsID))
        #expect(s.artRow == .coverFlow && s.mainArt.isEmpty)
        #expect(send(&s, .wheel(3), .tick, now: 101).isEmpty)  // Liked Songs: the read already runs
        send(&s, .artTracksRead(token: 1, playlist: Playlist.likedSongsID, tracks: Self.likedCovers.tracks), now: 102)
        #expect(s.loadedTracks == [Playlist.likedSongsID] && s.library.map(\.id) == [Playlist.likedSongsID])
        #expect(s.mainArt.count == mainArtCount && s.mainArt.allSatisfy { $0.id.hasPrefix("l") })
        send(&s, .select, now: 103)  // Liked Songs opens with no read
        #expect(s.top.screen == .tracks(playlist: Playlist.likedSongsID) && !s.top.loading)
        send(&s, .menu, .wheel(-2), .select, .playlistsLoaded(token: s.tok + 1, playlists: [focusInfo]), now: 104)
        #expect(s.library.map(\.id) == [Playlist.likedSongsID, "focus"] && s.rows(for: s.top) == [.playlist("focus")])
        #expect(s.tracks(in: Playlist.likedSongsID) == Self.likedCovers.tracks)  // the list load keeps the read
        // Offline at first open, nothing is read.
        s = afterSetup()
        send(&s, .offline(true))
        send(&s, .launch, .restored(token: 1, ok: true))
        #expect(s.artReads.isEmpty)
    }

    /// A cover read from before a logout or reset must not end the new session's read,
    /// and must not put the old account's tracks in the new session.
    @Test func aCoverReadFromBeforeALogoutIsIgnored() {
        var s = afterSetup()
        #expect(send(&s, .launch, .restored(token: 1, ok: true)).last == .readArtTracks(token: 1, playlist: Playlist.likedSongsID))
        send(&s, .expire, .select, .authDone(token: s.authAttempt + 1, ok: true), .select)  // log in again while read 1 runs
        #expect(s.top.screen == .main && s.artReads == [Playlist.likedSongsID: 2])
        send(&s, .artTracksRead(token: 1, playlist: Playlist.likedSongsID, tracks: nil), now: 102)  // late, from the old session
        send(&s, .artTracksRead(token: 1, playlist: Playlist.likedSongsID, tracks: Self.focusCovers.tracks), now: 102)
        #expect(s.artReads == [Playlist.likedSongsID: 2] && s.library.isEmpty && s.loadedTracks.isEmpty)
        send(&s, .artTracksRead(token: 2, playlist: Playlist.likedSongsID, tracks: Self.likedCovers.tracks), now: 103)
        #expect(s.artReads.isEmpty && s.tracks(in: Playlist.likedSongsID) == Self.likedCovers.tracks)
        #expect(s.mainArt.allSatisfy { $0.id.hasPrefix("l") } && !s.mainArt.isEmpty)
        send(&s, .reset)  // a reset keeps the counter, so read 2 is stale after it
        #expect(s.artTok == 2)
    }

    @Test func screenChangesSlideInFromTheRightOrTheLeft() {
        var s = afterSetup()
        send(&s, .select)  // the login wait opens
        #expect(s.navSeq == 1 && s.navForward)
        send(&s, .authDone(token: 1, ok: true))  // "You’re in" replaces the login: still forward
        #expect(s.navSeq == 2 && s.navForward)
        send(&s, .select)  // the main menu replaces it: forward
        #expect(s.navSeq == 3 && s.navForward)
        send(&s, .wheel(3))  // no screen change
        #expect(s.navSeq == 3)
        send(&s, .select)  // Liked Songs opens
        #expect(s.navSeq == 4 && s.navForward)
        send(&s, .menu)  // back
        #expect(s.navSeq == 5 && !s.navForward)
        send(&s, .reset)
        #expect(s.navSeq == 5)  // the same screen identity, so no slide
    }

    @Test func onlyMovesBetweenAHalfScreenAndAFullOnePushTheWholeScreen() {
        var s = mainMenu()
        func move(_ actions: Action...) -> Int {  // how many whole-screen pushes the moves made
            let seq = s.wholeSeq
            send(&s, actions)
            return s.wholeSeq - seq
        }
        // Selects a row directly: quick wheel steps move more than one row.
        func pick(_ row: Row) { s.top.sel = s.rows(for: s.top).firstIndex(of: row) ?? -1 }
        // Half to half, and full to full: only the content.
        pick(.playlists)
        #expect(move(.select, .playlistsLoaded(token: 1, playlists: [focusInfo])) == 0)  // main to Playlists
        #expect(s.top.screen == .playlists)
        #expect(move(.select, .tracksLoaded(token: 2, playlist: "focus", tracks: focus.tracks)) == 1)  // to a playlist: push
        #expect(move(.select) == 0 && s.top.screen == .now)  // a track to Now Playing
        #expect(move(.menu) == 0)
        #expect(move(.menu) == 1 && s.top.screen == .playlists)  // back to Playlists: push
        #expect(move(.menu) == 0 && s.top.screen == .main)
        // The main menu to a full screen and back: push both ways.
        pick(.settings)
        #expect(move(.select) == 1 && s.top.screen == .settings)
        #expect(move(.menu) == 1)
        pick(.likedSongs)
        #expect(move(.select) == 1 && s.top.screen == .tracks(playlist: Playlist.likedSongsID))
        #expect(move(.menu) == 1)
        pick(.nowPlaying)
        #expect(move(.select) == 1 && s.top.screen == .now)
        #expect(move(.menu) == 1)
        // With Album Art off, no screen is a half screen: only the content slides.
        s.albumArt = .off
        pick(.playlists)
        #expect(move(.select) == 0 && s.top.screen == .playlists)
        pick(.playlist("focus"))
        #expect(move(.select) == 0 && s.top.screen == .tracks(playlist: "focus"))
        #expect(move(.menu, .menu) == 0 && s.top.screen == .main)
        pick(.nowPlaying)
        #expect(move(.select, .menu) == 0)
        #expect(move(.reset) == 0)  // the reset keeps it, so the skin does not push
    }

    @Test func tickExpiresToastAndOverlay() {
        var s = playing()
        s.toast = "hi"; s.toastUntil = 101; s.overlayUntil = 101
        send(&s, .tick)
        #expect(s.toast == "hi" && s.t == 0)  // tick no longer moves playback
        send(&s, .tick, now: 102)
        #expect(s.toast == "" && s.overlayUntil == 0)
    }

    @Test func positionAndTrackEndedComeFromEngine() {
        var s = playing()
        send(&s, .position(12.5, generation: 1))
        #expect(s.t == 12.5)
        #expect(send(&s, .position(20, generation: 0)) == [] && s.t == 12.5)  // from an earlier load
        #expect(send(&s, .trackEnded(generation: 0)) == [] && s.isPlaying)
        #expect(send(&s, .trackEnded(generation: 1)) == [])  // the engine stopped at the end of the context
        #expect(!s.isPlaying && s.t == 0 && s.current?.track == "f0")
        #expect(send(&s, .trackEnded(generation: 1)) == [] && !s.isPlaying)
    }

    /// A fast scrub: the engine still reports the position of an earlier seek, with the new generation.
    @Test func positionFromAnEarlierSeekIsIgnoredForAShortTime() {
        var s = playing()
        send(&s, .select, .wheel(1), .wheel(1), .wheel(1))  // scrub to 5, 10, then 15
        #expect(s.t == 15 && s.playGen == 4)
        send(&s, .position(5, generation: 4), now: 100.2)  // from the seek to 5
        #expect(s.t == 15)
        #expect(send(&s, .wheel(1), now: 100.3) == [.seek(20, generation: 5)])  // the next step starts from 15
        send(&s, .position(19.8, generation: 5), now: 100.5)  // near the target: taken
        #expect(s.t == 19.8)
        send(&s, .position(25, generation: 5), now: 103.4)  // 3 s after the seek: any position is taken
        #expect(s.t == 25)
        send(&s, .wheel(-1), now: 104)  // seek to 20
        send(&s, .position(60, generation: 6), now: 104.1)
        #expect(s.t == 20)
        send(&s, .position(22.5, generation: 6), now: 104.5)  // 2 s plus the time since the seek: still taken
        #expect(s.t == 22.5)
    }

    /// A position from a later load or skip is not held back by an earlier seek.
    @Test func seekFilterAppliesOnlyToItsOwnGeneration() {
        var s = playing()
        send(&s, .select, .wheel(2))  // seek to 10, generation 2
        send(&s, .next)  // generation 3
        send(&s, .position(0.5, generation: 3), now: 100.1)
        #expect(s.t == 0.5)

        s = playing()
        send(&s, .select, .wheel(5))  // seek to 25, near the end of the track
        send(&s, .trackChanged("f1", playing: true, generation: 2), .position(0.4, generation: 2), now: 100.5)
        #expect(s.current?.track == "f1" && s.t == 0.4)  // the next track's position is taken

        s = playing()
        s.repeatMode = .one
        send(&s, .select, .wheel(6))  // seek to 29, the end of the 30 s track
        send(&s, .position(0.3, generation: 2), now: 100.5)  // Repeat One wrapped to the start
        #expect(s.current?.track == "f0" && s.t == 0.3)
        s.repeatMode = .off
        send(&s, .wheel(4), now: 101)  // seek to about 20: not near the end
        send(&s, .position(0.3, generation: 3), now: 101.2)
        #expect(s.t > 20)  // an old position, so ignored
    }

    @Test func trackChangedMovesCurrentWithoutLoading() {
        var s = playing()
        send(&s, .position(12.5, generation: 1))
        #expect(send(&s, .trackChanged("f1", playing: true, generation: 1)) == [])
        #expect(s.current == TrackRef(playlist: "focus", track: "f1") && s.t == 0 && s.isPlaying)
        send(&s, .trackChanged("f5", playing: false, generation: 0))  // from an earlier load
        #expect(s.current?.track == "f1" && s.isPlaying)
        send(&s, .trackChanged("zz", playing: false, generation: 1))  // not in our copy of the playlist
        #expect(s.current == TrackRef(playlist: "focus", track: "zz") && s.track(s.current!) == nil && !s.isPlaying)
        #expect(send(&s, .select, .wheel(1)) == [.seek(5, generation: 2)])  // scrub with no known duration
        s = playing()
        send(&s, .trackEnded(generation: 1))
        send(&s, .next, .trackChanged("f1", playing: true, generation: 2))  // Next after the end plays again
        #expect(s.isPlaying && s.current?.track == "f1")
        s = mainMenu()
        #expect(send(&s, .trackChanged("f1", playing: true, generation: 0)) == [] && s.current == nil)
    }

    @Test func trackChangedReadsAnUnknownTrackOnce() {
        var s = playing()
        let radio = "spotify:track:radio"
        #expect(send(&s, .trackChanged("f1", playing: true, generation: 1)) == [])  // in the list
        #expect(send(&s, .trackChanged("zz", playing: true, generation: 1)) == [])  // not a track URI
        #expect(send(&s, .trackChanged(radio, playing: true, generation: 1)) == [.readTrack(radio)])
        #expect(send(&s, .trackChanged("f1", playing: true, generation: 1), .trackChanged(radio, playing: true, generation: 1)) == [])  // in flight
        send(&s, .trackRead(radio, nil))  // failed
        #expect(send(&s, .trackChanged("f2", playing: true, generation: 1), .trackChanged(radio, playing: true, generation: 1)) == [])  // no retry
        #expect(s.track(s.current!) == nil)
    }

    @Test func trackReadKeepsTheTrackForTheSession() {
        var s = playing()
        let radio = Track(id: "spotify:track:radio", title: "Radio", artist: "Band", duration: 200, coverID: "ab")
        send(&s, .trackRead(radio.id, radio))  // not asked for: ignored
        #expect(s.extraTracks.isEmpty)
        send(&s, .trackChanged(radio.id, playing: true, generation: 1), .trackRead(radio.id, radio))
        #expect(s.track(s.current!) == radio && s.trackReads.isEmpty)
        #expect(send(&s, .trackChanged("f1", playing: true, generation: 1), .trackChanged(radio.id, playing: true, generation: 1)) == [])  // known now
        for i in 0..<extraTrackLimit {  // the oldest goes first
            let id = "spotify:track:\(i)"
            send(&s, .trackChanged(id, playing: true, generation: 1), .trackRead(id, Track(id: id, title: "", artist: "", duration: 1)))
        }
        #expect(s.extraTracks.count == extraTrackLimit && !s.extraTracks.contains(radio))
        send(&s, .trackChanged("spotify:track:late", playing: true, generation: 1))
        send(&s, .expire)  // signs out
        #expect(!s.signedIn && s.extraTracks.isEmpty && s.trackReads.isEmpty)
        send(&s, .trackRead("spotify:track:late", radio))  // from before the sign-out
        #expect(s.extraTracks.isEmpty)
    }

    @Test func adoptedShowsWhatSpotifyPlaysWithoutOpeningNowPlaying() {
        var s = mainMenu()
        send(&s, .wheel(3))  // Liked Songs
        #expect(send(&s, .adopted(track: "f2", playlist: "focus", playing: false, position: 12, generation: 0)) == [])
        #expect(s.current == TrackRef(playlist: "focus", track: "f2") && !s.isPlaying && s.t == 12)
        #expect(s.top.screen == .main && s.rows(for: s.top) == [.nowPlaying, .coverFlow, .playlists, .albums, .likedSongs, .shuffleSongs, .settings])
        #expect(s.top.sel == 4)  // still Liked Songs
        #expect(send(&s, .play) == [.resume] && s.isPlaying)  // Play works at once
        s = mainMenu()
        send(&s, .adopted(track: "zz", playlist: nil, playing: true, position: 3, generation: 0))  // a station
        #expect(s.current == TrackRef(playlist: "", track: "zz") && s.isPlaying)
        #expect(send(&s, .next) == [.next(generation: 1)])
        s = mainMenu()  // a track from outside the library: its details are read, as after `.trackChanged`
        let radio = "spotify:track:radio"
        #expect(send(&s, .adopted(track: radio, playlist: nil, playing: true, position: 0, generation: 0)) == [.readTrack(radio)])
        s = playing()  // a load is in flight: the load wins
        #expect(send(&s, .adopted(track: "f5", playlist: "focus", playing: true, position: 40, generation: 1)) == [])
        #expect(s.current?.track == "f0" && s.t == 0)
        s = mainMenu()
        s.playGen = 2
        send(&s, .adopted(track: "f1", playlist: "focus", playing: true, position: 0, generation: 1))  // stale
        #expect(s.current == nil)
    }

    @Test func loadFailedShowsWhatPlayedBeforeTheLoad() {
        var s = playing(2)
        send(&s, .position(40, generation: 1))
        send(&s, .menu, .wheel(3), .select)  // Focus track 5
        #expect(s.current?.track == "f5" && s.t == 0 && s.beforeLoad != nil)
        send(&s, .loadFailed("Old", generation: 1))  // from an earlier load
        #expect(s.current?.track == "f5")
        #expect(send(&s, .loadFailed("Can’t start Spotify playback", generation: 2)) == [])
        #expect(s.current == TrackRef(playlist: "focus", track: "f2") && s.t == 40 && s.isPlaying)
        #expect(s.toast == "Can’t start Spotify playback" && s.beforeLoad == nil)
        send(&s, .play)  // paused before the load: it stays paused after the failure
        send(&s, .menu, .wheel(1), .select, .loadFailed("x", generation: 3))
        #expect(s.current?.track == "f2" && !s.isPlaying)
        s = playing()  // the first load fails: nothing plays, so nothing shows
        #expect(send(&s, .loadFailed("Install the Spotify app to play music", generation: 1)) == [])
        #expect(s.current == nil && !s.isPlaying && s.t == 0 && s.toast == "Install the Spotify app to play music")
        #expect(s.top.screen == .tracks(playlist: "focus"))  // no empty Now Playing: back to the list
        #expect(s.stack[0].sel == 1 && s.rows(for: s.stack[0])[1] == .playlists)  // the main menu keeps its pick
        s = playing(2)
        send(&s, .menu, .wheel(1), .select, .position(1, generation: 2))  // the second load plays
        #expect(s.beforeLoad == nil && !s.loadPending)
        s = playing(2)  // a second pick while the first load is in flight
        send(&s, .position(40, generation: 1), .menu, .wheel(1), .select, .menu, .wheel(1), .select)
        send(&s, .loadFailed("x", generation: 3))
        #expect(s.current?.track == "f2" && s.t == 40)  // what still plays, not the first pick
    }

    @Test func openingAStaleListReadsItAgainInTheBackground() {
        var s = mainMenu()
        send(&s, openFocus(1))  // read at 100
        #expect(send(&s, .menu, .select, now: 219) == [])  // not stale yet: no read
        #expect(send(&s, .menu, .select, now: 220) == [.refreshTracks(playlist: "focus")])
        #expect(!s.top.loading && s.rows(for: s.top).count == 8)  // the old rows show at once
        #expect(send(&s, .menu, .select, now: 300) == [])  // one refresh at a time
        #expect(send(&s, .menu, .menu, .select, now: 300) == [.refreshPlaylists])  // the playlist list too
        s.refreshing = []
        send(&s, .offline(true))
        #expect(send(&s, .select, .menu, now: 400) == [])  // offline: no read
    }

    @Test func activatedReadsTheShownListsAgainAfter30s() {
        var s = mainMenu()
        #expect(send(&s, .activated) == [])  // nothing read yet
        send(&s, openFocus(1))  // read at 100
        #expect(send(&s, .activated, now: 129) == [])
        #expect(send(&s, .activated, now: 130) == [.refreshTracks(playlist: "focus"), .refreshPlaylists])
        #expect(send(&s, .activated, now: 200) == [])  // already running
        s.refreshing = []
        send(&s, .menu, .menu)  // the main menu: only the playlist list
        #expect(send(&s, .activated, now: 300) == [.refreshPlaylists])
        s = afterSetup()
        #expect(send(&s, .activated) == [])  // signed out
    }

    @Test func libraryStaleReadsTheShownListsAgainAtOnce() {
        var s = mainMenu()
        send(&s, openFocus(1))
        #expect(send(&s, .libraryStale, now: 101) == [.refreshTracks(playlist: "focus"), .refreshPlaylists])
        #expect(s.readAt.isEmpty)
        s.refreshing = []
        send(&s, .menu, .menu, .wheel(2), .select, now: 102)  // Liked Songs: not read yet, so it loads
        #expect(send(&s, .libraryStale, now: 103) == [.refreshPlaylists])  // the loading list is not read twice
    }

    @Test func tracksRefreshedKeepsTheSelectedSong() {
        var s = mainMenu()
        send(&s, openFocus(1))
        send(&s, .wheel(6))  // f6
        let added = Track(id: "new", title: "New", artist: "x", duration: 30)
        send(&s, .tracksRefreshed(playlist: "focus", tracks: [added]))  // not asked for: ignored
        #expect(s.tracks(in: "focus").count == 8)
        s.refreshing = ["focus"]
        send(&s, .tracksRefreshed(playlist: "focus", tracks: [added] + focus.tracks), now: 500)
        #expect(s.top.sel == 7 && s.rows(for: s.top)[7] == .track("f6") && s.top.off == 7 - s.shownRows + 1)
        #expect(s.readAt["focus"] == 500 && s.refreshing.isEmpty)
        s.refreshing = ["focus"]
        send(&s, .tracksRefreshed(playlist: "focus", tracks: nil))  // failed: the old rows stay
        #expect(s.tracks(in: "focus").count == 9 && s.refreshing.isEmpty)
        s.refreshing = ["focus"]
        send(&s, .tracksRefreshed(playlist: "focus", tracks: Array(focus.tracks.prefix(3))))  // f6 left
        #expect(s.top.sel == 2)
    }

    @Test func tracksRefreshedKeepsThePlayingSongWhenItLeaves() {
        var s = playing(3)
        s.refreshing = ["focus"]
        send(&s, .tracksRefreshed(playlist: "focus", tracks: Array(focus.tracks.prefix(2))))
        #expect(s.current?.track == "f3" && s.track(s.current!) == focus.tracks[3])
    }

    @Test func playlistsRefreshedKeepsThePlayingSongWhenItsPlaylistLeaves() {
        var s = playing(3)
        s.refreshing = [""]
        send(&s, .playlistsRefreshed([Playlist(id: "mix", name: "Mix", tracks: [], trackCount: 3)]))
        #expect(s.tracks(in: "focus").isEmpty && s.track(s.current!) == focus.tracks[3])
    }

    @Test func playlistsRefreshedKeepsTheSelectedPlaylist() {
        var s = mainMenu()
        send(&s, openFocus(1) + [.menu])  // on Playlists, Focus selected
        let mix = Playlist(id: "mix", name: "Mix", tracks: [], trackCount: 3)
        s.refreshing = [""]
        send(&s, .playlistsRefreshed([mix, focusInfo]), now: 600)
        #expect(s.rows(for: s.top) == [.playlist("mix"), .playlist("focus")] && s.top.sel == 1)
        #expect(s.tracks(in: "focus").count == 8 && s.readAt[""] == 600)  // read tracks stay
        s.refreshing = [""]
        send(&s, .expire)  // signs out
        #expect(s.readAt.isEmpty && s.refreshing.isEmpty)
        send(&s, .playlistsRefreshed([mix]))  // from before the sign-out
        #expect(s.library.isEmpty)
    }

    @Test func playbackFailedPausesAndShowsToast() {
        var s = playing()
        send(&s, .playbackFailed("Old", generation: 0))  // stale load
        #expect(s.isPlaying && s.toast.isEmpty)  // unchanged
        #expect(send(&s, .playbackFailed("Install Spotify to play music", generation: 1)) == [])
        #expect(!s.isPlaying && s.toast == "Install Spotify to play music" && s.current?.track == "f0")
    }

    @Test func playlistsLoadedIgnoresStaleTokens() {
        var s = mainMenu()
        send(&s, .wheel(1), .select, .playlistsLoaded(token: 99, playlists: [focusInfo]))
        #expect(s.top.loading && !s.playlistsLoaded)
        send(&s, .playlistsLoaded(token: 1, playlists: [focusInfo]))
        #expect(!s.top.loading && !s.top.error && s.playlistsLoaded)
        #expect(s.rows(for: s.top) == [.playlist("focus")] && s.library[0].trackCount == 8)
    }

    @Test func tracksLoadedIgnoresStaleTokensAndFillsThePlaylist() {
        var s = mainMenu()
        send(&s, .wheel(1), .select, .playlistsLoaded(token: 1, playlists: [focusInfo]), .select)
        #expect(s.top.loading && s.rows(for: s.top) == [])
        send(&s, .tracksLoaded(token: 1, playlist: "focus", tracks: focus.tracks))  // stale
        #expect(s.top.loading && !s.loadedTracks.contains("focus"))
        send(&s, .tracksLoaded(token: 2, playlist: "focus", tracks: focus.tracks))
        #expect(!s.top.loading && s.rows(for: s.top).count == 8 && s.loadedTracks == ["focus"])
        send(&s, .menu, .menu, .wheel(2), .select, .tracksLoaded(token: 3, playlist: Playlist.likedSongsID, tracks: liked.tracks))
        #expect(s.library.map(\.id) == [Playlist.likedSongsID, "focus"])  // Liked Songs goes first
    }

    @Test func listsReadOnceOpenAtOnce() {
        var s = mainMenu()
        send(&s, openFocus(1))
        #expect(send(&s, .menu, .menu, .select) == [] && !s.top.loading && s.top.screen == .playlists)
        #expect(send(&s, .select) == [] && !s.top.loading && s.rows(for: s.top).count == 8)
    }

    @Test func playlistsReloadKeepsTracksAlreadyRead() {
        var s = mainMenu()
        send(&s, openFocus(1))
        let other = Playlist(id: "other", name: "Other", tracks: [], trackCount: 3)
        s.playlistsLoaded = false  // as if the list must be read again
        send(&s, .menu, .menu, .select, .playlistsLoaded(token: 3, playlists: [other, focusInfo]))
        #expect(s.tracks(in: "focus") == focus.tracks && s.rows(for: s.top) == [.playlist("other"), .playlist("focus")])
        s.playlistsLoaded = false
        send(&s, .menu, .select, .playlistsLoaded(token: 4, playlists: [other]))  // Focus is gone
        #expect(s.loadedTracks.isEmpty && s.library.map(\.id) == ["other"])
    }

    @Test func tracksReloadThatReordersKeepsCurrentTrack() {
        var s = playing(2)
        s.loadedTracks = []  // as if Focus must be read again
        send(&s, .menu, .menu, .select, .tracksLoaded(token: 3, playlist: "focus", tracks: focus.tracks.reversed()))
        #expect(s.track(s.current!)?.id == "f2")
    }

    @Test func loginAndRestorePrefetchTheLibrary() {
        var s = afterSetup()
        #expect(send(&s, .select, .authDone(token: 1, ok: true), .select) == [.logIn(token: 1), .prefetch, .readArtTracks(token: 1, playlist: Playlist.likedSongsID)])
        s = afterSetup()
        #expect(send(&s, .launch, .restored(token: 1, ok: true)) == [.restoreSession(token: 1), .prefetch, .readArtTracks(token: 1, playlist: Playlist.likedSongsID)])
        s = afterSetup()
        #expect(send(&s, .launch, .restored(token: 1, ok: false)) == [.restoreSession(token: 1)])
    }

    @Test func authDoneSignsInOrFailsOffline() {
        var s = afterSetup()
        #expect(send(&s, .select) == [.logIn(token: 1)])
        send(&s, .offline(true), .authDone(token: 1, ok: false))  // offline, the login fails
        #expect(s.top.screen == .loginFailed && !s.signedIn)
        #expect(send(&s, .offline(false), .select) == [.logIn(token: 2)])  // Try again
        send(&s, .authDone(token: 1, ok: true))  // late, from the first attempt
        #expect(s.top == Frame(screen: .auth, token: 2) && !s.signedIn)
        send(&s, .reset, .select, .authDone(token: 2, ok: true))  // from before the reset
        #expect(s.top.screen == .auth && !s.signedIn)
        send(&s, .offline(true), .authDone(token: 3, ok: true))  // a login that worked counts offline too
        #expect(s.stack == [Frame(screen: .loggedIn)] && s.signedIn && s.beatUntil == 101.5)
        send(&s, .tick, now: 101.4)  // "You’re in" shows for 1.5 s
        #expect(s.top.screen == .loggedIn)
        send(&s, .tick, now: 101.5)
        #expect(s.stack == [Frame(screen: .main)] && s.beatUntil == 0 && s.toast.isEmpty)
    }

    /// Card AX, change 171: a failed login says so, with Try again and Cancel. No toast.
    @Test func aFailedLoginOffersTryAgainAndCancel() {
        var s = afterSetup()
        send(&s, .select, .authDone(token: 1, ok: false))
        #expect(s.stack == [Frame(screen: .login), Frame(screen: .loginFailed)] && !s.signedIn && s.toast.isEmpty)
        #expect(s.rows(for: s.top) == [.tryAgain, .cancel] && s.top.sel == 0)
        #expect(send(&s, .wheel(1), .select).isEmpty)  // Cancel: back to the login
        #expect(s.stack == [Frame(screen: .login)] && !s.navForward)
        send(&s, .select, .authDone(token: 2, ok: false), .menu)  // MENU goes back to the login too
        #expect(s.stack == [Frame(screen: .login)])
    }

    /// Card AX, change 170: while the browser is open, the login can open it again or stop.
    @Test func theLoginWaitOpensTheBrowserAgainOrCancels() {
        var s = afterSetup()
        send(&s, .select)
        #expect(s.rows(for: s.top) == [.openBrowser, .cancel] && s.top.sel == 0)
        let seq = s.navSeq
        #expect(send(&s, .select) == [.logIn(token: 2)])  // the bridge stops the first login
        #expect(s.stack == [Frame(screen: .login), Frame(screen: .auth, token: 2)] && s.navSeq == seq)  // no slide
        send(&s, .authDone(token: 1, ok: false))  // the first login reports that it stopped
        #expect(s.top == Frame(screen: .auth, token: 2))
        #expect(send(&s, .wheel(1), .select) == [.cancelLogIn])  // Cancel
        #expect(s.stack == [Frame(screen: .login)])
    }

    /// Card AX, change 175: "You’re in" goes on after 1.5 s, or at once with a press. MENU does nothing.
    @Test func youreInGoesOnAfterABeatOrAPress() {
        var s = afterSetup()
        send(&s, .select, .authDone(token: 1, ok: true), now: 10)
        #expect(s.stack == [Frame(screen: .loggedIn)] && s.rows(for: s.top).isEmpty && s.beatUntil == 11.5)
        send(&s, .menu, .wheel(1), now: 10.5)
        #expect(s.stack == [Frame(screen: .loggedIn)])
        send(&s, .select, now: 10.6)
        #expect(s.stack == [Frame(screen: .main)] && s.beatUntil == 0)
        send(&s, .tick, now: 12)  // the beat ended already: nothing more
        #expect(s.stack == [Frame(screen: .main)])
    }

    @Test func menuCancelsLogin() {
        var s = afterSetup()
        send(&s, .select)
        #expect(send(&s, .menu) == [.cancelLogIn])
        #expect(s.stack == [Frame(screen: .login)])
        send(&s, .authDone(token: 1, ok: false))  // the cancelled login reports late
        #expect(s.stack == [Frame(screen: .login)] && s.toast == "")
    }

    @Test func launchRestoresTheStoredLogin() {
        var s = afterSetup()
        #expect(send(&s, .launch) == [.restoreSession(token: 1)])
        #expect(s.restoring && s.rows(for: s.top) == [])
        send(&s, .restored(token: 1, ok: true))
        #expect(s.stack == [Frame(screen: .main)] && s.signedIn && !s.restoring && s.toast == "")
        #expect(send(&s, .launch) == [])  // already signed in
    }

    @Test func failedRestoreOffersLogIn() {
        var s = afterSetup()
        send(&s, .launch, .restored(token: 1, ok: false))
        #expect(s.stack == [Frame(screen: .login)] && !s.signedIn && !s.restoring)
        #expect(s.rows(for: s.top) == [.logIn])
    }

    @Test func noLoginWhileRestoring() {
        var s = afterSetup()
        #expect(send(&s, .launch, .wheel(1), .select, .menu) == [.restoreSession(token: 1)])
        #expect(s.stack == [Frame(screen: .login)] && s.restoring)
        send(&s, .reset, .restored(token: 1, ok: true))  // from before the reset
        #expect(s.stack == [Frame(screen: .login)] && !s.signedIn)
    }

    @Test func offlinePausesPlayback() {
        var s = playing()
        #expect(send(&s, .offline(true)) == [.pause])
        #expect(s.offline && !s.isPlaying && s.toast == "Connection lost. Paused")
        send(&s, .menu, .select)  // Focus track 0
        #expect(s.top.screen == .tracks(playlist: "focus") && s.toast == "Offline. Can’t start playback")
    }

    @Test func expireSignsOut() {
        var s = afterSetup()
        #expect(send(&s, .expire) == [] && s.toast == "")
        s = playing()
        send(&s, .offline(true), .offline(false))  // a toast that still shows
        #expect(s.toast == "Connection lost. Paused")
        #expect(send(&s, .expire) == [.stop, .logOut])
        #expect(s.stack == [Frame(screen: .login)] && !s.signedIn && s.current == nil && s.library.isEmpty)
        #expect(!s.playlistsLoaded && s.loadedTracks.isEmpty)
        // Card AX, change 181: no toast. The login screen says "Log in again".
        #expect(s.toast == "" && s.sessionEnded)
        // The same login screens; after the login, the main menu with no library read (AY).
        send(&s, .select)
        #expect(s.top.screen == .auth && s.sessionEnded)
        send(&s, .authDone(token: s.authAttempt, ok: true))
        #expect(s.stack == [Frame(screen: .loggedIn)] && !s.sessionEnded)
        send(&s, .select)
        #expect(s.stack == [Frame(screen: .main)])
    }

    @Test func resetRestoresInitialState() {
        var s = playing()
        #expect(send(&s, .reset) == [.stop])
        var fresh = afterSetup()
        fresh.tok = s.tok; fresh.playGen = s.playGen; fresh.authAttempt = s.authAttempt; fresh.artTok = s.artTok
        (fresh.navSeq, fresh.wholeSeq) = (s.navSeq, s.wholeSeq)
        #expect(s == fresh && s.tok == 2 && s.navSeq > 0)  // the reset keeps the screen identity: no slide
        send(&s, .select, .authDone(token: 2, ok: true), .select, .wheel(1), .select, .playlistsLoaded(token: 1, playlists: [focusInfo]))  // late load from before reset
        #expect(s.top.loading && s.top.token == 3)
    }

    @Test func logOutGoesThroughConfirm() {
        var s = playing()
        send(&s, .menu, .menu, .menu, .wheel(5), .select, .wheel(6), .select)
        #expect(s.top.screen == .confirm)
        send(&s, .select)  // Cancel
        #expect(s.top.screen == .settings)
        #expect(send(&s, .select, .wheel(1), .select) == [.stop, .logOut])
        #expect(s.top.screen == .login && s.toast == "" && s.current == nil)  // change 181: no toast
        #expect(!s.sessionEnded)  // the normal login words
    }
}

@MainActor final class FakePlayer: Player {
    var calls: [String] = []
    func load(trackID: String, context: String?, autoplay: Bool, generation: Int) {
        calls.append("load \(trackID) \(context ?? "-") \(autoplay)")
    }
    func pause() { calls.append("pause") }
    func resume() { calls.append("resume") }
    func stop() { calls.append("stop") }
    func next(generation: Int) { calls.append("next") }
    func prev(generation: Int) { calls.append("prev") }
    func setShuffle(_ on: Bool) { calls.append("shuffle \(on)") }
    func setRepeat(_ mode: RepeatMode) { calls.append("repeat \(mode.rawValue)") }
    func seek(to seconds: Double, generation: Int) { calls.append("seek \(seconds)") }
    func setVolume(_ percent: Int) { calls.append("volume \(percent)") }
}

@MainActor @Test func storeRunsEffectsAgainstPlayer() {
    let player = FakePlayer()
    var s = playing()
    s.isPlaying = true
    let store = Store(player: player, library: FakeLibrary(), state: s, env: Dependencies(now: { 0 }, random: { _ in 0 }))
    store.send(.play)
    store.send(.wheel(1))
    store.send(.next)
    store.send(.prev)
    #expect(player.calls == ["pause", "volume 65", "next", "prev"])
}

/// The wheel clicks only when a step moves something. Past an end it is silent.
@MainActor @Test func wheelClicksOnlyWhenSomethingMoves() {
    var s = mainMenu()  // six rows
    let store = Store(player: FakePlayer(), library: FakeLibrary(), state: s, env: Dependencies(now: { 0 }, random: { _ in 0 }))
    var clicks = 0
    store.onWheelStep = { clicks += 1 }
    store.send(.wheel(-1))  // already at the top
    #expect(clicks == 0)
    for _ in 0..<5 { store.send(.wheel(1)) }
    #expect(clicks == 5 && store.state.top.sel == 5)
    store.send(.wheel(1))  // already at the bottom
    #expect(clicks == 5)
    store.send(.select)  // a button press is not a wheel step
    #expect(clicks == 5)

    s = playing()
    s.volume = 100
    #expect(!wheelMoved(from: s, to: { var n = s; send(&n, .wheel(1)); return n }()))  // the volume bar is full
    #expect(wheelMoved(from: s, to: { var n = s; send(&n, .wheel(-1)); return n }()))
    send(&s, .select)  // the scrub bar, at 0 s
    #expect(!wheelMoved(from: s, to: { var n = s; send(&n, .wheel(-1)); return n }()))
    #expect(wheelMoved(from: s, to: { var n = s; send(&n, .wheel(1)); return n }()))
}

/// The shuffle slider has two stops and the repeat slider three. Past the end stops, no click.
@Test func sliderEndsAreSilent() {
    var s = playing()
    send(&s, .select, .select)  // the shuffle slider, at Off
    func moves(_ d: Int) -> Bool {
        var n = s; send(&n, .wheel(d))
        defer { s = n }
        return wheelMoved(from: s, to: n)
    }
    #expect(!moves(-1))  // Off is the left end
    #expect(moves(1))  // Songs
    #expect(!moves(1))  // Songs is the right end
    send(&s, .select)  // the repeat slider: Off, One, All
    #expect(!moves(-1))
    #expect(moves(1) && moves(1))  // One, then All
    #expect(!moves(1))
    #expect(moves(-1))
}

@MainActor final class FakeLibrary: Library {
    var fetches: [String] = []
    var loginResult = true
    var calls: [String] = []
    func playlists() async -> [Playlist]? { fetches.append("playlists"); return [focusInfo] }
    func tracks(of playlist: String) async -> [Track]? {
        fetches.append(playlist)
        onProgress?(playlist, 1, 2)  // how far, before the result, as the bridge reports it
        return library.first { $0.id == playlist }?.tracks
    }
    var extra: [String: Track] = [:]
    func rereadPlaylists() async -> [Playlist]? { fetches.append("reread playlists"); return [focusInfo] }
    func reread(_ playlist: String) async -> [Track]? {
        fetches.append("reread \(playlist)"); return library.first { $0.id == playlist }?.tracks
    }
    func track(_ id: String) async -> Track? { fetches.append(id); return extra[id] }
    func prefetch() async { calls.append("prefetch") }
    func logIn() async -> Bool { calls.append("logIn"); return loginResult }
    func cancelLogIn() async { calls.append("cancelLogIn") }
    func restoreSession() async -> Bool { calls.append("restoreSession"); return loginResult }
    func logOut() { calls.append("logOut") }
    var onProgress: (@MainActor (_ playlist: String, _ done: Int, _ total: Int) -> Void)?
}

@MainActor @Test func storeReadsAnUnknownTrack() async {
    let lib = FakeLibrary()
    let radio = Track(id: "spotify:track:radio", title: "Radio", artist: "Band", duration: 200)
    lib.extra[radio.id] = radio
    let store = Store(player: FakePlayer(), library: lib, state: playing(), env: Dependencies(now: { 0 }, random: { _ in 0 }))
    store.send(.trackChanged(radio.id, playing: true, generation: 1))
    while store.state.extraTracks.isEmpty { await Task.yield() }
    #expect(store.state.track(store.state.current!) == radio && lib.fetches.last == radio.id)
}

@MainActor @Test func storeRereadsAStaleList() async {
    let lib = FakeLibrary()
    var s = mainMenu()
    send(&s, openFocus(1))
    let store = Store(player: FakePlayer(), library: lib, state: s, env: Dependencies(now: { 1000 }, random: { _ in 0 }))
    store.send(.menu)
    store.send(.select)
    while !store.state.refreshing.isEmpty { await Task.yield() }
    #expect(lib.fetches == ["reread focus"] && store.state.readAt["focus"] == 1000)
}

@MainActor @Test func storeRunsLoginEffects() async {
    let lib = FakeLibrary()
    let store = Store(player: FakePlayer(), library: lib, state: afterSetup(), env: Dependencies(now: { 0 }, random: { _ in 0 }))
    lib.loginResult = false
    store.send(.launch)
    while store.state.restoring { await Task.yield() }
    store.send(.select)  // Log in
    while lib.calls.count < 2 { await Task.yield() }
    #expect(lib.calls == ["restoreSession", "logIn"])
    while store.state.top.screen == .auth { await Task.yield() }
    #expect(store.state.top.screen == .loginFailed)
    store.send(.select)  // Try again
    store.send(.menu)
    while lib.calls.count < 4 { await Task.yield() }
    #expect(lib.calls.suffix(2).sorted() == ["cancelLogIn", "logIn"])
}

@MainActor @Test func storeFetchesLibraryAndDeliversLoaded() async {
    let lib = FakeLibrary()
    var s = afterSetup()
    send(&s, .select, .authDone(token: 1, ok: true), .select)
    let store = Store(player: FakePlayer(), library: lib, state: s, env: Dependencies(now: { 0 }, random: { _ in 0 }))
    store.send(.wheel(1)); store.send(.select)  // Playlists
    #expect(store.state.top.loading)
    await store.settle()
    #expect(lib.fetches == ["playlists"] && !store.state.top.loading && store.state.library == [focusInfo])
    #expect(store.state.rows(for: store.state.top) == [.playlist("focus")])
    store.send(.select)  // Focus
    await store.settle()
    #expect(lib.fetches == ["playlists", "focus"] && store.state.tracks(in: "focus") == focus.tracks)
}

@MainActor @Test func storeRunsPrefetchAfterLogin() async {
    let lib = FakeLibrary()
    let store = Store(player: FakePlayer(), library: lib, state: afterSetup(), env: Dependencies(now: { 0 }, random: { _ in 0 }))
    store.send(.launch)
    while !lib.calls.contains("prefetch") { await Task.yield() }
    #expect(lib.calls == ["restoreSession", "prefetch"])
    // The main menu reads Liked Songs for its covers, once.
    while !store.state.loadedTracks.contains(Playlist.likedSongsID) { await Task.yield() }
    #expect(lib.fetches == [Playlist.likedSongsID] && store.state.tracks(in: Playlist.likedSongsID) == liked.tracks)
}

@Test func trackKeepsACoverIDAndDropsAnEmptyOne() {
    #expect(Track(id: "t", title: "T", artist: "A", duration: 1, coverID: "ab67").coverID == "ab67")
    #expect(Track(id: "t", title: "T", artist: "A", duration: 1, coverID: "").coverID == nil)
    #expect(Track(id: "t", title: "T", artist: "A", duration: 1).coverID == nil)
}

@Suite struct SpotifyAppDeviceTests {
    typealias D = SpotifyAppDevice.Candidate

    // From the spike build 9 log: the Spotify app's software string has no "osx".
    let mac = D(id: "a1", name: "Jason’s Macbook Air 15", type: "COMPUTER")
    let phone = D(id: "p1", name: "iPhone", type: "SMARTPHONE")

    @Test func picksThisMacByNameOrTheOnlyComputer() {
        func pick(_ devices: [D], _ name: String?) -> SpotifyAppDevice.Pick {
            SpotifyAppDevice.pick(devices, computerName: name)
        }
        #expect(pick([phone, mac], "jason's macbook air 15") == .found(id: "a1"))
        #expect(pick([phone, mac], "Other Mac") == .found(id: "a1"))
        #expect(pick([phone, mac], nil) == .found(id: "a1"))
        #expect(pick([phone], "Jason’s Macbook Air 15") == .none)
        let second = D(id: "a2", name: "Studio", type: "COMPUTER")
        #expect(pick([mac, second], "Studio") == .found(id: "a2"))
        #expect(pick([mac, second], "Laptop") == .ambiguous)
    }

    @Test func coldStartWaitsForThisMacInsteadOfAnotherComputer() {
        // Clasify just launched Spotify here. The work PC was in the list before the launch.
        let pc = D(id: "w1", name: "WORK-PC", type: "COMPUTER")
        let before: Set = ["w1", "p1"]
        func pick(_ devices: [D], _ name: String?) -> SpotifyAppDevice.Pick {
            SpotifyAppDevice.pick(devices, computerName: name, excluding: before)
        }
        #expect(pick([phone, pc], "Jason’s Macbook Air 15") == .none)  // keeps waiting
        #expect(pick([phone, pc], nil) == .none)
        #expect(pick([pc, mac], "Jason’s Macbook Air 15") == .found(id: "a1"))
        #expect(pick([pc, mac], "Renamed Mac") == .found(id: "a1"))  // the only new computer
        #expect(pick([pc], "WORK-PC") == .none)  // an excluded name match waits for a new computer
    }

    @Test func sameNameMacFromBeforeTheLaunchIsTakenOnlyAfterTheWait() {
        // A remote Mac with this Mac's name, or this Mac's own entry from before Spotify quit.
        let twin = D(id: "t1", name: "Jason’s Macbook Air 15", type: "COMPUTER")
        let before: Set = ["t1"]
        func pick(_ devices: [D], afterWait: Bool) -> SpotifyAppDevice.Pick {
            SpotifyAppDevice.pick(devices, computerName: mac.name, excluding: before, allowExcluded: afterWait)
        }
        #expect(pick([twin, mac], afterWait: false) == .found(id: "a1"))  // the new device wins
        #expect(pick([twin, mac], afterWait: true) == .found(id: "a1"))
        #expect(pick([twin], afterWait: false) == .none)  // keep waiting for a new device
        #expect(pick([twin], afterWait: true) == .found(id: "t1"))  // this Mac back with its old ID
    }
}

@Test func backoffDoublesUpToTheLimitAndResets() {
    var backoff = Backoff()
    #expect((0..<7).map { _ in backoff.failed() } == [2, 4, 8, 16, 32, 60, 60])
    backoff.reset()
    #expect(backoff.failed() == 2)
}

private struct Dropped: Error {}
private struct Other: Error {}

@MainActor @Test func aCommandRetriesOnceAfterTheSessionComesBack() async {
    var tries = 0, reconnects = 0
    let dropped: (any Error) -> Bool = { $0 is Dropped }
    /// Runs one retryOnce, and returns its value or the type of its error.
    func run(reconnectWorks: Bool, failures: Int, error: any Error = Dropped()) async -> String {
        tries = 0
        do {
            return try await retryOnce(after: { reconnects += 1; return reconnectWorks }, when: dropped) {
                tries += 1
                if tries <= failures { throw error }
                return "sent"
            }
        } catch {
            return "\(type(of: error))"
        }
    }
    // Fails with a dropped session, the reconnect works, and the retry goes out.
    #expect(await run(reconnectWorks: true, failures: 1) == "sent")
    #expect(tries == 2 && reconnects == 1)
    // A failed reconnect sends nothing more.
    #expect(await run(reconnectWorks: false, failures: 1) == "Dropped")
    #expect(tries == 1 && reconnects == 2)
    // The retry runs only once.
    #expect(await run(reconnectWorks: true, failures: 2) == "Dropped")
    #expect(tries == 2 && reconnects == 3)
    // Another failure does not log in again.
    #expect(await run(reconnectWorks: true, failures: 1, error: Other()) == "Other")
    #expect(tries == 1 && reconnects == 3)
}
