import ClasifyCore
import Foundation

/// The words and numbers that skins show. It only formats state. The reducer holds all logic.
/// The strings come from the mockup, with "Clasify" for its old name.
enum Labels {
    static func title(_ screen: Screen, in state: AppState) -> String {
        switch screen {
        case .login, .main: "Clasify"
        case .auth: "Sign in"
        case .playlists: "Playlists"
        case .tracks(let id): state.library.first { $0.id == id }?.name ?? (id == Playlist.likedSongsID ? "Liked Songs" : "")
        case .settings: "Settings"
        case .confirm: "Log out?"
        case .about: "About"
        case .now: "Now Playing"
        }
    }

    /// A list row: its label, the value on its right, and a chevron if it opens a screen.
    struct RowText: Equatable {
        var label: String
        var value = ""
        /// The play or pause mark of the playing track's row.
        var mark: PlayMark?
        var opens = false
    }

    static func row(_ row: Row, on screen: Screen, in state: AppState) -> RowText {
        func onOff(_ on: Bool) -> String { on ? "On" : "Off" }
        switch row {
        case .logIn: return RowText(label: "Log in with Spotify", opens: true)
        case .nowPlaying: return RowText(label: "Now Playing", opens: true)
        case .playlists: return RowText(label: "Playlists", opens: true)
        case .likedSongs: return RowText(label: "Liked Songs", opens: true)
        case .shuffleSongs: return RowText(label: "Shuffle Songs")
        case .settings: return RowText(label: "Settings", opens: true)
        case .playlist(let id):
            return RowText(label: state.library.first { $0.id == id }?.name ?? "", opens: true)
        case .track(let id):
            guard case .tracks(let playlist) = screen else { return RowText(label: "") }
            let ref = TrackRef(playlist: playlist, track: id)
            let mark = state.current == ref ? playMark(in: state) : nil
            return RowText(label: state.track(ref)?.title ?? "", mark: mark)
        case .shuffle: return RowText(label: "Shuffle", value: state.shuffle ? "Songs" : "Off")
        case .repeatMode: return RowText(label: "Repeat", value: state.repeatMode.rawValue)
        case .skin: return RowText(label: "Skin", value: state.skin.rawValue)
        case .albumArt: return RowText(label: "Album Art", value: onOff(state.showArt))
        case .clicker: return RowText(label: "Clicker", value: onOff(state.clicker))
        case .about: return RowText(label: "About", opens: true)
        case .logOut: return RowText(label: "Log out", opens: true)
        case .cancel: return RowText(label: "Cancel")
        case .confirmLogOut: return RowText(label: "Log out")
        }
    }

    /// The text of a screen that shows no list: loading, an error, an empty list, the login wait, About.
    struct Message: Equatable {
        var title: String
        var body = ""
        var spinner = false
    }

    /// Nil when the screen shows a list or Now Playing.
    static func message(for frame: Frame, in state: AppState) -> Message? {
        if frame.loading { return Message(title: "Loading…", spinner: true) }
        if frame.error {
            return Message(title: "Can’t reach Spotify", body: "Check your connection, then press center to retry.")
        }
        switch frame.screen {
        case .login where state.restoring:
            return Message(title: "Signing in…", spinner: true)
        case .tracks where state.rows(for: frame).isEmpty:
            return Message(title: "No songs", body: "Add songs to this playlist in Spotify. Press MENU to go back.")
        case .auth:
            return Message(
                title: "Waiting for browser…", body: "Approve Clasify in your browser. Spotify Premium required.",
                spinner: true)
        case .about:
            return Message(title: "Clasify \(version)", body: "Open source · MIT. Not affiliated with Spotify.")
        case .now where state.current == nil:
            return Message(title: "")
        default:
            return nil
        }
    }

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
    }

    static func now(in state: AppState) -> NowText? {
        guard let ref = state.current else { return nil }
        let tracks = state.tracks(in: ref.playlist)
        let index = tracks.firstIndex { $0.id == ref.track }
        let track = index.map { tracks[$0] }
        return NowText(
            title: track?.title ?? ref.track,  // a track that is not in the list shows by its ID
            artist: track?.artist ?? "",
            list: title(.tracks(playlist: ref.playlist), in: state),
            count: index.map { "\($0 + 1) of \(tracks.count)" } ?? "",
            duration: track?.duration ?? 0)
    }

    /// The mark beside the playing track: ▶ while it plays, two bars while it is paused.
    enum PlayMark: Equatable { case playing, paused }

    /// Nil when no track is current.
    static func playMark(in state: AppState) -> PlayMark? {
        state.current == nil ? nil : state.isPlaying ? .playing : .paused
    }

    /// "SHUFFLE", "REPEAT" and "REPEAT 1", as Now Playing shows them.
    static func flags(in state: AppState) -> String {
        var flags: [String] = []
        if state.shuffle { flags.append("SHUFFLE") }
        switch state.repeatMode {
        case .off: break
        case .all: flags.append("REPEAT")
        case .one: flags.append("REPEAT 1")
        }
        return flags.joined(separator: " ")
    }

    /// "m:ss".
    static func time(_ seconds: Double) -> String {
        let s = max(Int(seconds.isFinite ? seconds : 0), 0)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// The mockup's cover colors. A hash of the artist picks one, so an artist keeps one color.
    static let covers: [UInt32] = [0x6a54b0, 0x2f6f99, 0xb5583a, 0x3a8a5c, 0xa8832a, 0x8a3f6e, 0x2f7f7a, 0x5a6b8c]

    static func cover(for artist: String) -> UInt32 {
        var h: UInt32 = 0
        for unit in artist.utf16 { h = h &* 31 &+ UInt32(unit) }  // the mockup's hash, over UTF-16 like JavaScript
        return covers[Int(h % UInt32(covers.count))]
    }
}
