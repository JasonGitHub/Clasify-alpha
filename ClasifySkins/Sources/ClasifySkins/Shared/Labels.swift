import ClasifyCore
import Foundation

/// The words and numbers that skins show. It only formats state. The reducer holds all logic.
/// The strings come from the mockup, with "myPod" for its old names (card BP).
enum Labels {
    /// A first-time hint's tip (card BA, change 195): the words, the wheel mark drawn in them
    /// as on the wheel, the words after it, and the words for VoiceOver.
    static func hintTip(_ hint: Hint) -> (lead: String, mark: Icon?, rest: String, spoken: String) {
        switch hint {
        case .menu: ("Press MENU to go back", nil, "", "Press MENU to go back")  // change 139
        case .playPause: ("Press", .playPause, "to pause", "Press play/pause to pause")  // change 176
        case .next: ("Press", .next, "for the next song", "Press next for the next song")  // change 177
        // Card BA.1, change 199: words only; the buttons are named as MENU is on the wheel.
        case .tourPlay: ("Press Play to start your music", nil, "", "Press Play to start your music")
        case .tourNext: ("Press Next for the next song", nil, "", "Press Next for the next song")
        case .tourMenu: ("Press MENU to go back", nil, "", "Press MENU to go back")
        case .tourTurn: ("", nil, "", "")  // CLA-163, card CE.1: the app draws it, not the device
        // CLA-163, card CE look A: the menu bar hint's words on the device.
        case .tourMenuBar: ("The menu bar icon shows or hides myPod", nil, "", "The menu bar icon shows or hides myPod")
        }
    }

    static func title(_ screen: Screen, in state: AppState) -> String {
        switch screen {
        case .login where state.restoring: "myPod"
        case .main: "myPod"  // card BP, change 283
        case .login, .auth, .loginFailed, .loggedIn, .premium, .accessOff: "Log In"  // cards AX, BM
        case .playlists: "Playlists"
        case .albums: "Albums"
        case .coverFlow, .albumPanel: "Cover Flow"
        case .tracks(let id) where Album.isID(id): state.album(id)?.name ?? ""
        case .tracks(let id): state.listName(id) ?? ""
        case .artists: "Artists"
        case .settings: "Settings"
        case .confirm: "Log out?"
        case .about: "About"
        case .licenses, .license: "Licenses"  // card BF, change 213: the text screen shows its name under the bar
        case .now: "Now Playing"
        // Setup (Round 13). Hello shows no title bar text.
        case .hello: ""
        case .color: "Pick Your Color"
        case .pickMusic: "Pick Your Music"  // card BM, change 257
        case .spotifyApp: "Spotify App"
        case .yourMusic: "Your Music"
        case .betaSoon, .betaEnded, .betaNew: "Beta"  // card BI v2, changes 233 and 234; card BV, 312
        case .activate: "Activate"  // CLA-128
        case .activation: "Activation"  // CLA-141, card BF.2
        case .noSongs: state.words.service  // card CR: "On This Mac"
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
        /// The value in gray, as "Not activated" (card BF.2).
        var grayValue = false
        /// Card CR: a local song whose file is missing. The whole row is gray.
        var missing = false
    }

    /// CLA-141, card BF.2 (change 360): About's Status row. It opens only with the server's info.
    static func statusRow(in state: AppState) -> RowText {
        switch state.aboutStatus {
        case .notActivated: RowText(label: "Status", value: "Not activated", grayValue: true)
        case .activated: RowText(label: "Status", value: "Activated", opens: state.aboutStatus.opens)
        }
    }

    static func row(_ row: Row, on screen: Screen, in state: AppState) -> RowText {
        func onOff(_ on: Bool) -> String { on ? "On" : "Off" }
        switch row {
        case .logIn: return RowText(label: "Log in with Spotify")  // card AX: no chevron
        case .nowPlaying: return RowText(label: "Now Playing", opens: true)
        case .playlists: return RowText(label: "Playlists", opens: true)
        case .albums: return RowText(label: "Albums", opens: true)
        case .coverFlow: return RowText(label: "Cover Flow", opens: true)
        case .likedSongs: return RowText(label: state.likedSongsName, opens: true)
        case .shuffleSongs: return RowText(label: "Shuffle Songs")
        case .settings: return RowText(label: "Settings", opens: true)
        case .playlist(let id):
            return RowText(label: state.listName(id) ?? "", opens: true)
        // Card BN: the main menu's Artists and Songs, and one line per artist.
        case .artists: return RowText(label: "Artists", opens: true)
        case .songs: return RowText(label: "Songs", opens: true)
        case .artist(let id): return RowText(label: state.listName(id) ?? "", opens: true)
        case .album(let id):
            // Two lines, like a song row: the album, then its artist.
            let album = state.album(id)
            return RowText(label: album?.name ?? "", detail: album?.artist ?? "")
        case .track(let id):
            guard let playlist = screen.songList else { return RowText(label: "") }
            let ref = TrackRef(playlist: playlist, track: id)
            let track = state.track(ref)
            return RowText(
                label: track?.title ?? "", detail: track?.artist ?? "", playing: state.current == ref,
                missing: track?.missing ?? false)
        // Change 256: the value flips on each Select; the switch happens on leaving Settings.
        case .service: return RowText(label: "Service", value: (state.pendingService ?? state.service).rawValue)
        case .shuffle: return RowText(label: "Shuffle", value: state.shuffle ? "Songs" : "Off")
        case .repeatMode: return RowText(label: "Repeat", value: state.repeatMode.rawValue)
        case .skin: return RowText(label: "Skin", value: state.skin.rawValue)
        case .albumArt: return RowText(label: "Album Art", value: state.albumArt.rawValue)
        case .deviceColor: return RowText(label: "Color", value: state.deviceColor.rawValue)  // change 169
        case .clicker: return RowText(label: "Clicker", value: onOff(state.clicker))
        case .menuBar: return RowText(label: "Menu Bar", value: onOff(state.menuBar))
        case .about: return RowText(label: "About", opens: true)
        case .logOut: return RowText(label: "Log out", opens: true)
        case .cancel: return RowText(label: "Cancel")
        case .confirmLogOut: return RowText(label: "Log out")
        case .color(let color): return RowText(label: color.rawValue)
        case .license(let i): return RowText(label: License.all.indices.contains(i) ? License.all[i].name : "", opens: true)
        case .openBrowser: return RowText(label: "Open browser again")
        case .tryAgain: return RowText(label: "Try again")
        case .getSpotifyApp: return RowText(label: "Get Spotify App")  // card BB: no chevron
        // Card AX, screen 135: no chevrons.
        case .checkPremium: return RowText(label: "Check again")
        case .getPremium: return RowText(label: state.words.getPlan)  // "Get Apple Music" (card BM, 259)
        case .premiumLogOut: return RowText(label: "Log out")
        // Card BM: no chevrons.
        case .pickService(let service): return RowText(label: service.rawValue)
        case .openPrivacy: return RowText(label: "Open Settings")
        case .useSpotify: return RowText(label: "Use Spotify")
        case .checkLibrary: return RowText(label: "Check again")  // card CR
        case .pickYourMusic: return RowText(label: "Pick Your Music")
        // Card BI v2: no chevrons.
        case .getNewBeta: return RowText(label: "Get New Beta")
        case .later: return RowText(label: "Later")
        case .quit: return RowText(label: "Quit")
        // CLA-128, card BW: the Activate rows.
        case .openActivate: return RowText(label: "Open browser")  // card BW
        case .openActivateAgain: return RowText(label: "Open browser again")
        case .cancelActivate: return RowText(label: "Cancel")
        case .sendAgain: return RowText(label: "Send again")
        case .useAnotherEmail: return RowText(label: "Use another email")
        case .checkMail: return RowText(label: "Check again")
        case .tryActivateAgain: return RowText(label: "Try again")
        // CLA-141, card BF.2 (changes 361, 362): the masked email, then the date and the Macs.
        case .activatedAs:
            guard case .activated(let info) = state.aboutStatus else { return RowText(label: "") }
            return RowText(label: info?.email ?? "", detail: info?.subtitle() ?? "")
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
        let words = state.words
        if frame.screen == .yourMusic && !frame.error { return nil }  // card AY draws its own words
        if frame.loading { return Message(title: "Loading…", spinner: true) }
        if frame.error {
            return Message(title: "Can’t reach \(words.service)", body: "Check your connection, then press center to retry.")
        }
        switch frame.screen {
        case .login where state.restoring:
            return Message(title: "Signing in…", spinner: true)
        case .tracks(let id) where Album.isID(id) && state.rows(for: frame).isEmpty:
            return Message(title: "No songs", body: "\(words.service) has no songs for this album. Press MENU to go back.")
        case .albumPanel where state.rows(for: frame).isEmpty:
            return Message(title: "No songs", body: "\(words.service) has no songs for this album. Press MENU to go back.")
        case .tracks(let id) where (id == Playlist.songsID || Playlist.isArtistID(id)) && state.rows(for: frame).isEmpty:
            return Message(title: "No songs", body: "Add songs to your library in \(words.service). Press MENU to go back.")
        case .tracks where state.rows(for: frame).isEmpty:
            return Message(title: "No songs", body: "Add songs to this playlist in \(words.service). Press MENU to go back.")
        case .artists where state.rows(for: frame).isEmpty:
            return Message(title: "No artists", body: "Add songs to your library in \(words.service). Press MENU to go back.")
        case .albums where state.rows(for: frame).isEmpty, .coverFlow where state.rows(for: frame).isEmpty:
            return Message(title: "No albums", body: "\(words.like) songs in \(words.service) to see their albums. Press MENU to go back.")
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
        /// Card BW, 321 and 322: the address the mail went to, on its own line. A long one fades at the end.
        var email = ""
    }

    /// Card BW, 319 to 327: the Activate screens' words. Calm, no tech words.
    static func activateWords(_ state: AppState) -> SetupWords {
        let address = if case .waiting(let email, _) = state.activation { email } else { "" }
        return switch state.activateStep {
        case .join:
            SetupWords(headline: "Join the beta", line: "Add your email\nin your browser.", footnote: "No password. One click in a mail.")
        case .browserOpen: SetupWords(headline: "Take your time", line: "Your browser is open.\nAdd your email there.")
        case .checkMail: SetupWords(headline: "Check your mail", line: "We sent a link to", email: address)
        case .stopped: SetupWords(headline: "Check your mail", line: "Click the link we sent to", email: address)
        case .confirmed: SetupWords(headline: "Welcome to the beta", line: "Thanks for joining us.")
        case .mailBusy: SetupWords(headline: "Mail is busy", line: "Many people are joining.\nPlease try again later.")
        case .full: SetupWords(headline: "The beta is full", line: "You’re on the list.\nWe’ll write to you.")
        case .off: SetupWords(headline: "Activation is off", line: "Write to us at\nfeedback@getmypod.app")
        case .offline:  // card BW.1: and where a VPN or filter can block us
            SetupWords(headline: "Can’t connect", line: "Check your internet,\nthen try again.",
                       footnote: "On a VPN or filter? Allow getmypod.app there.")
        }
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
        case .premium: SetupWords(headline: state.words.needPlan, line: state.words.needPlanLine)  // 135; card BM, 259
        case .accessOff: SetupWords(headline: "Access is off", line: "Turn it on in System Settings.")  // card BM, 258
        case .noSongs where state.localOnDrive:  // card CR: songs, but no file of them here
            SetupWords(headline: "Your music\nis on a drive", line: "Connect it to listen.")
        case .noSongs:  // card CR
            SetupWords(headline: "No songs yet", line: "Add songs to\nthe Music app.", footnote: "We play songs\nsaved on this Mac.")
        case .spotifyApp: SetupWords(headline: "One more thing", line: "We also need the Spotify app on this Mac.")
        case .yourMusic where frame.loading: SetupWords(headline: "Getting your music", line: "This may take a minute.")
        case .yourMusic: SetupWords(headline: "You’re all set", line: ready)
        // Card BI v2: one friendly warning (change 233), and the end (234). No countdown. Card
        // BI.1: one-line headlines, so the text has 3 lines like AX and BB (changes 317, 318).
        case .betaSoon: SetupWords(headline: "A fresh beta is out", line: "Get it any time before \(betaEnd(state.beta)).")
        case .betaEnded: SetupWords(headline: "Thanks for testing", line: "Get the new beta to keep listening.")
        // Card BV, change 312: the same headline, and this build's number.
        case .betaNew: SetupWords(headline: "A fresh beta is out", line: "You have Beta \(state.beta?.number ?? 0). Get the new one any time.")
        case .activate: activateWords(state)
        default: nil
        }
    }

    /// The beta's last day, as "14 Dec" (card BI v2, change 233). Empty for an ad-hoc build.
    static func betaEnd(_ beta: BetaBuild?) -> String {
        guard let beta else { return "" }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "d MMM"
        return format.string(from: Date(timeIntervalSinceReferenceDate: beta.endsAt))
    }

    /// The line at the bottom of Pick Your Music (card BM, change 257), as on Pick Your Color.
    static let pickMusicFootnote = "You can always change it in Settings."

    /// The line under "You’re all set" (card AY, change 189): always the same, with no song count.
    static let ready = "Enjoy your music."

    /// The app's version, or the mockup's when the bundle has none, as in tests.
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// About's version (card BI v2, change 235): "1.0 Beta 209" on a beta, with the bundle's
    /// build number. "1.0" on an ad-hoc build.
    static func aboutVersion(in state: AppState, build: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) -> String {
        guard state.beta != nil else { return version }
        return [version, "Beta", build].compactMap { $0 }.joined(separator: " ")
    }

    /// Change 279: the grey BETA pill shows on a beta, in the full-width title bars only: song
    /// lists, Now Playing and About. Never on the half screens or in setup.
    static func betaTag(on screen: Screen, in state: AppState) -> Bool {
        guard state.beta != nil else { return false }
        switch screen {
        case .tracks, .now, .about: return true
        default: return false
        }
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
        let waiting = track == nil ? state.waitingWords(ref) : nil  // CLA-170
        return NowText(
            // A track that is not in our copy of the list, such as Spotify's autoplay after the
            // list ends, shows as the service name with no artist. Never show a raw track ID.
            // While its details are read, the earlier song's words stay (CLA-170).
            title: track?.title ?? waiting?.title ?? state.words.service,
            artist: track?.artist ?? waiting?.artist ?? "",
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
