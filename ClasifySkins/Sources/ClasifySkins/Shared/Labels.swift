import ClasifyCore
import Foundation

/// The words and numbers that skins show. It only formats state. The reducer holds all logic.
/// The strings come from the mockup, with "Clasify" for its old name.
enum Labels {
    /// A first-time hint's tip (card BA, change 195): the words, the wheel mark drawn in them
    /// as on the wheel, the words after it, and the words for VoiceOver.
    static func hintTip(_ hint: Hint) -> (lead: String, mark: Icon?, rest: String, spoken: String) {
        switch hint {
        case .menu: ("Press MENU to go back", nil, "", "Press MENU to go back")  // change 139
        case .playPause: ("Press", .playPause, "to pause", "Press play/pause to pause")  // change 176
        case .next: ("Press", .next, "for the next song", "Press next for the next song")  // change 177
        }
    }

    static func title(_ screen: Screen, in state: AppState) -> String {
        switch screen {
        case .login where state.restoring: "Clasify"
        case .main: "Clasify"
        case .login, .auth, .loginFailed, .loggedIn, .premium: "Log In"  // card AX
        case .playlists: "Playlists"
        case .albums: "Albums"
        case .coverFlow, .albumPanel: "Cover Flow"
        case .tracks(let id) where Album.isID(id): state.album(id)?.name ?? ""
        case .tracks(let id): state.library.first { $0.id == id }?.name ?? (id == Playlist.likedSongsID ? "Liked Songs" : "")
        case .settings: "Settings"
        case .confirm: "Log out?"
        case .about: "About"
        case .now: "Now Playing"
        // Setup (Round 13). Hello shows no title bar text.
        case .hello: ""
        case .color: "Pick Your Color"
        case .spotifyApp: "Spotify App"
        case .yourMusic: "Your Music"
        }
    }

    /// A list row: its label, the value on its right, and a chevron if it opens a screen.
    struct RowText: Equatable {
        var label: String
        var value = ""
        /// A second line under the label: the artist on a song row.
        var detail = ""
        /// The playing track's row shows a speaker, whether it plays or is paused.
        var playing = false
        var opens = false
    }

    static func row(_ row: Row, on screen: Screen, in state: AppState) -> RowText {
        func onOff(_ on: Bool) -> String { on ? "On" : "Off" }
        switch row {
        case .logIn: return RowText(label: "Log in with Spotify")  // card AX: no chevron
        case .nowPlaying: return RowText(label: "Now Playing", opens: true)
        case .playlists: return RowText(label: "Playlists", opens: true)
        case .albums: return RowText(label: "Albums", opens: true)
        case .coverFlow: return RowText(label: "Cover Flow", opens: true)
        case .likedSongs: return RowText(label: "Liked Songs", opens: true)
        case .shuffleSongs: return RowText(label: "Shuffle Songs")
        case .settings: return RowText(label: "Settings", opens: true)
        case .playlist(let id):
            return RowText(label: state.library.first { $0.id == id }?.name ?? "", opens: true)
        case .album(let id):
            // Two lines, like a song row: the album, then its artist.
            let album = state.album(id)
            return RowText(label: album?.name ?? "", detail: album?.artist ?? "")
        case .track(let id):
            guard let playlist = screen.songList else { return RowText(label: "") }
            let ref = TrackRef(playlist: playlist, track: id)
            let track = state.track(ref)
            return RowText(label: track?.title ?? "", detail: track?.artist ?? "", playing: state.current == ref)
        case .shuffle: return RowText(label: "Shuffle", value: state.shuffle ? "Songs" : "Off")
        case .repeatMode: return RowText(label: "Repeat", value: state.repeatMode.rawValue)
        case .skin: return RowText(label: "Skin", value: state.skin.rawValue)
        case .albumArt: return RowText(label: "Album Art", value: state.albumArt.rawValue)
        case .deviceColor: return RowText(label: "Color", value: state.deviceColor.rawValue)  // change 169
        case .clicker: return RowText(label: "Clicker", value: onOff(state.clicker))
        case .nowPlayingBar: return RowText(label: "Now Playing Bar", value: onOff(state.nowPlayingBar))
        case .about: return RowText(label: "About", opens: true)
        case .logOut: return RowText(label: "Log out", opens: true)
        case .cancel: return RowText(label: "Cancel")
        case .confirmLogOut: return RowText(label: "Log out")
        case .color(let color): return RowText(label: color.rawValue)
        case .openBrowser: return RowText(label: "Open browser again")
        case .tryAgain: return RowText(label: "Try again")
        case .getSpotifyApp: return RowText(label: "Get Spotify App")  // card BB: no chevron
        // Card AX, screen 135: no chevrons.
        case .checkPremium: return RowText(label: "Check again")
        case .getPremium: return RowText(label: "Get Premium")
        case .premiumLogOut: return RowText(label: "Log out")
        }
    }

    /// The text of a screen that shows no list: loading, an error, an empty list, the login wait.
    struct Message: Equatable {
        var title: String
        var body = ""
        var spinner = false
    }

    /// Nil when the screen shows a list, Now Playing or About.
    static func message(for frame: Frame, in state: AppState) -> Message? {
        if frame.screen == .yourMusic && !frame.error { return nil }  // card AY draws its own words
        if frame.loading { return Message(title: "Loading…", spinner: true) }
        if frame.error {
            return Message(title: "Can’t reach Spotify", body: "Check your connection, then press center to retry.")
        }
        switch frame.screen {
        case .login where state.restoring:
            return Message(title: "Signing in…", spinner: true)
        case .tracks(let id) where Album.isID(id) && state.rows(for: frame).isEmpty:
            return Message(title: "No songs", body: "Spotify has no songs for this album. Press MENU to go back.")
        case .albumPanel where state.rows(for: frame).isEmpty:
            return Message(title: "No songs", body: "Spotify has no songs for this album. Press MENU to go back.")
        case .tracks where state.rows(for: frame).isEmpty:
            return Message(title: "No songs", body: "Add songs to this playlist in Spotify. Press MENU to go back.")
        case .albums where state.rows(for: frame).isEmpty, .coverFlow where state.rows(for: frame).isEmpty:
            return Message(title: "No albums", body: "Like songs in Spotify to see their albums. Press MENU to go back.")
        case .now where state.current == nil:
            return Message(title: "")
        default:
            return nil
        }
    }

    /// The words over the rows of a login screen (card AX, changes 134, 170, 171 and 175): a
    /// headline, a line, and on the first screen a footnote at the bottom.
    struct SetupWords: Equatable {
        var headline: String
        var line: String
        var footnote = ""
    }

    /// Also the Spotify App screen's words (card BB, change 131). Nil on other screens, and
    /// while a stored login is restored.
    static func setupWords(for frame: Frame, in state: AppState) -> SetupWords? {
        switch frame.screen {
        case .login where !state.restoring && state.sessionEnded:  // card AX, change 181
            SetupWords(
                headline: "Log in again", line: "Your Spotify session ended.",
                footnote: "We never see your password.")
        case .login where !state.restoring:
            SetupWords(
                headline: "Your music is on Spotify", line: "We’ll open your browser.",
                footnote: "We never see your password.")
        case .auth: SetupWords(headline: "Take your time", line: "Your browser is open.\nLog in there.")
        case .loginFailed: SetupWords(headline: "That didn’t work", line: "No problem, it happens.")
        case .loggedIn: SetupWords(headline: "You’re in", line: "Nice to meet you.")
        case .premium: SetupWords(headline: "Premium needed", line: "To play music, we need Spotify Premium.")  // 135
        case .spotifyApp: SetupWords(headline: "One more thing", line: "We also need the Spotify app on this Mac.")
        case .yourMusic where frame.loading: SetupWords(headline: "Getting your music", line: "This may take a minute.")
        case .yourMusic: SetupWords(headline: "You’re all set", line: ready)
        default: nil
        }
    }

    /// The line under "You’re all set" (card AY, change 189): always the same, with no song count.
    static let ready = "Enjoy your music."

    /// The About screen's fine print (card E). "Not affiliated with Spotify" moves to the macOS
    /// About window later (Jason, 11-07 17:08 JST).
    static var aboutVersion: String { "Version \(version)" }

    /// The app's version, or the mockup's when the bundle has none, as in tests.
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
    }

    /// The playing track, for Now Playing and the bottom bar.
    struct NowText: Equatable {
        var title: String
        var artist: String
        var list: String
        /// "3 of 12", or empty when the track is not in Clasify's copy of the list.
        var count: String
        var duration: Double
        /// The album cover's ID, nil when the track has none.
        var coverID: String? = nil
    }

    static func now(in state: AppState) -> NowText? {
        guard let ref = state.current else { return nil }
        let tracks = state.tracks(in: ref.playlist)
        let index = tracks.firstIndex { $0.id == ref.track }
        // A track from outside the list shows its details once `.trackRead` has them.
        let track = index.map { tracks[$0] } ?? state.track(ref)
        return NowText(
            // A track that is not in our copy of the list, such as Spotify's autoplay after the
            // list ends, shows as "Spotify" with no artist. Never show a raw track ID.
            title: track?.title ?? "Spotify",
            artist: track?.artist ?? "",
            list: title(.tracks(playlist: ref.playlist), in: state),
            count: index.map { "\($0 + 1) of \(tracks.count)" } ?? "",
            duration: track?.duration ?? 0,
            coverID: track?.coverID)
    }

    /// Cover Flow's song panel (card AF): the album, its artist, and its songs with their lengths.
    struct PanelText: Equatable {
        struct Song: Equatable {
            var title: String
            var length: String
        }
        var album: String
        var artist: String
        var songs: [Song]
    }

    static func panel(_ album: String, in state: AppState) -> PanelText {
        let info = state.album(album)
        return PanelText(
            album: info?.name ?? "", artist: info?.artist ?? "",
            songs: state.tracks(in: album).map { .init(title: $0.title, length: time($0.duration)) })
    }

    /// The mark beside the playing track: ▶ while it plays, two bars while it is paused.
    enum PlayMark: Equatable { case playing, paused }

    /// Nil when no track is current.
    static func playMark(in state: AppState) -> PlayMark? {
        state.current == nil ? nil : state.isPlaying ? .playing : .paused
    }

    /// The title bar battery: how full it is, red below 20%, and its mark. A bolt while it
    /// charges; a plug when the Mac is on power and not charging (full, or macOS holds the
    /// charge); no mark on battery power.
    struct BatteryText: Equatable {
        enum Mark: Equatable { case bolt, plug }
        var level: Double
        var red: Bool
        var mark: Mark?
        /// For VoiceOver.
        var label: String
    }

    /// Nil when the Mac has no battery: the title bar shows none.
    static func battery(in state: AppState) -> BatteryText? {
        guard let b = state.battery else { return nil }
        let mark: BatteryText.Mark? = b.charging ? .bolt : b.onPower ? .plug : nil
        let percent = Int((b.level * 100).rounded())
        let label = "Battery \(percent)%" + (mark == .bolt ? ", charging" : mark == .plug ? ", on power" : "")
        return BatteryText(level: b.level, red: b.low, mark: mark, label: label)
    }

    /// The shuffle or repeat slider on Now Playing: its name, its stops and the stop that is on.
    struct Slider: Equatable {
        var name: String
        var stops: [String]
        var index: Int
    }

    /// Nil unless the wheel sets shuffle or repeat.
    static func slider(in state: AppState) -> Slider? {
        switch state.nowMode {
        case .shuffle:
            return Slider(name: "Shuffle", stops: ["Off", "Songs"], index: state.shuffle ? 1 : 0)
        case .repeatMode:
            let order = RepeatMode.sliderOrder
            return Slider(name: "Repeat", stops: order.map(\.rawValue), index: order.firstIndex(of: state.repeatMode) ?? 0)
        case .volume, .scrub:
            return nil
        }
    }

    /// "m:ss".
    static func time(_ seconds: Double) -> String {
        let s = max(Int(seconds.isFinite ? seconds : 0), 0)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// The mockup's estimate of a 13 point label's width: 7.4 points a character, 13 for a CJK character.
    static func estimatedWidth(_ label: String) -> Double {
        let wide: (Unicode.Scalar) -> Bool = {
            (0x3000...0x9FFF).contains($0.value) || (0xAC00...0xD7AF).contains($0.value) || (0xFF00...0xFFEF).contains($0.value)
        }
        return label.unicodeScalars.reduce(0.0) { $0 + (wide($1) ? 13 : 7.4) }
    }

    /// The seconds of one loop of the mockup's marquee: max(5, round(width / 28 + 3)), with the estimated width.
    /// The row itself measures if the label fits, so only a label that is cut scrolls.
    static func marqueeLoop(_ label: String) -> Double { max(5, (estimatedWidth(label) / 28 + 3).rounded()) }

    /// Now Playing's long lines (round 8, card AA): the room for the title, artist and playlist.
    static func nowRoom(art: Bool) -> Double { art ? 141.4 : 284 }

    /// Which Now Playing line scrolls at time `t`, and how far. The lines wider than `room` take
    /// turns, in order. In its turn a line waits 1.5 s, scrolls once at 28 points a second until
    /// its start comes back, and stops. Then all lines rest for 8 s, and the next turn starts.
    /// Nil when no line is long.
    struct NowScroll: Equatable {
        /// The line whose turn it is: 0 title, 1 artist, 2 playlist.
        var line: Int
        /// How far it has moved, as a part of one copy's width (the text and the 28 point gap).
        var shift: Double
    }

    static let nowHold = 1.5, nowRest = 8.0

    /// The seconds a line takes to scroll once: its width and the gap, at 28 points a second.
    static func nowScrollSeconds(width: Double) -> Double { (width + 28) / 28 }

    /// The seconds of a line's whole turn: the wait, the scroll and the rest.
    static func nowTurn(width: Double) -> Double { nowHold + nowScrollSeconds(width: width) + nowRest }

    /// `widths` are the lines' widths in points, as the skin measures them.
    static func nowScroll(widths: [Double], room: Double, at t: Double) -> NowScroll? {
        let long = widths.enumerated().filter { $0.element > room }
        let total = long.reduce(0) { $0 + nowTurn(width: $1.element) }
        guard total > 0 else { return nil }
        var m = max(0, t).truncatingRemainder(dividingBy: total)
        for (line, width) in long {
            let turn = nowTurn(width: width)
            if m < turn {
                let scroll = nowScrollSeconds(width: width)
                let moving = m >= nowHold && m < nowHold + scroll
                return NowScroll(line: line, shift: moving ? (m - nowHold) / scroll : 0)
            }
            m -= turn
        }
        return nil
    }
}
