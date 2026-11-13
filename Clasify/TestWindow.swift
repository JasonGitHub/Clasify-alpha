import ClasifyCore
import SwiftUI

// TEMPORARY: a plain test window. It drives the real Store. View > Show Test Window switches
// to it from the Pocket skin. It only sends actions and formats state for display.
// Delete this file, and DebugCommands in ClasifyApp.swift, once the skin works on Jason's Mac.

/// Shows the store's state and sends the skin's input actions.
struct TestWindow: View {
    let store: Store?

    var body: some View {
        Group {
            if let store {
                TestPanel(store: store)
            } else {
                Text("Can’t start the Spotify bridge").foregroundStyle(.secondary).padding()
            }
        }
        .frame(width: 420, height: 560)
    }
}

private struct TestPanel: View {
    let store: Store

    private var state: AppState { store.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title(state.top.screen)).font(.title2.bold())
            if let status = status() {
                Text(status).foregroundStyle(.secondary)
            }
            rowList
            if !state.toast.isEmpty {
                Text(state.toast).padding(6).frame(maxWidth: .infinity).background(.yellow.opacity(0.3))
            }
            Divider()
            nowPanel
            controls
        }
        .padding()
    }

    private var rowList: some View {
        let rows = state.rows(for: state.top)
        return ScrollViewReader { proxy in
            List(Array(rows.enumerated()), id: \.offset) { index, row in
                Button {
                    // Move the selection with the wheel, then select, as the skin will.
                    store.send(.wheel(index - state.top.sel))
                    store.send(.select)
                } label: {
                    Text(label(row)).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(index == state.top.sel ? Color.accentColor.opacity(0.25) : Color.clear)
            }
            // A new list for each screen, so rows and scrolling do not carry over.
            .id("\(state.stack.count) \(String(describing: state.top.screen))")
            .onChange(of: state.top.sel) { _, sel in proxy.scrollTo(sel) }
        }
        .frame(minHeight: 200)
    }

    private var nowPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let ref = state.current {
                // A track that is not in Clasify's copy of the playlist shows by its ID.
                let track = state.track(ref)
                Text(track.map { "\($0.title) — \($0.artist)" } ?? ref.track).bold()
                Text("\(time(state.t)) / \(time(track?.duration ?? 0))   \(state.isPlaying ? "Playing" : "Paused")")
            } else {
                Text("Nothing playing").foregroundStyle(.secondary)
            }
            Text("Shuffle \(state.shuffle ? "On" : "Off") · Repeat \(state.repeatMode.rawValue) · Volume \(state.volume)")
            Text("Wheel on Now Playing: \(String(describing: state.nowMode))\(state.offline ? " · Offline" : "")")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    private var controls: some View {
        VStack(spacing: 6) {
            HStack {
                button("Menu", .menu)
                button("Wheel −", .wheel(-1))
                button("Select", .select)
                button("Wheel +", .wheel(1))
            }
            HStack {
                button("Prev", .prev)
                button(state.isPlaying ? "Pause" : "Play", .play)
                button("Next", .next)
            }
        }
    }

    private func button(_ name: String, _ action: Action) -> some View {
        Button(name) { store.send(action) }
    }

    private func status() -> String? {
        let top = state.top
        if top.loading { return "Loading…" }
        if top.error { return "Can’t load. Press Select to try again." }
        switch top.screen {
        case .login where state.restoring: return "Signing in…"
        case .auth: return "Your browser is open. Log in there."
        case .loginFailed: return "That didn’t work. No problem, it happens."
        case .loggedIn: return "You’re in. Nice to meet you."
        case .premium: return state.premiumFound ? "Premium." : "\(state.words.needPlan). \(state.words.needPlanLine)"
        case .accessOff: return "Access is off. Turn it on in System Settings."
        case .now: return "Select switches the wheel between volume and scrub."
        case .about: return "Clasify test build"
        case .hello: return "Press Select to begin."
        case .spotifyApp: return state.spotifyApp == true ? "Linked." : "We also need the Spotify app on this Mac."
        default: return nil
        }
    }

    private func title(_ screen: Screen) -> String {
        switch screen {
        case .login, .main: "Clasify"
        case .auth, .loginFailed, .loggedIn, .premium, .accessOff: "Log In"
        case .pickMusic: "Pick Your Music"
        case .playlists: "Playlists"
        case .albums: "Albums"
        case .coverFlow, .albumPanel: "Cover Flow"
        case .tracks(let id): state.library.first { $0.id == id }?.name ?? state.album(id)?.name ?? "Tracks"
        case .settings: "Settings"
        case .confirm: "Log out?"
        case .about: "About"
        case .licenses: "Licenses"
        case .license(let i): License.all.indices.contains(i) ? License.all[i].name : "License"
        case .now: "Now Playing"
        case .hello: "Hello"
        case .color: "Pick Your Color"
        case .spotifyApp: "Spotify App"
        case .yourMusic: "Your Music"
        }
    }

    private func label(_ row: Row) -> String {
        switch row {
        case .logIn: "Log in with Spotify"
        case .nowPlaying: "Now Playing"
        case .playlists: "Playlists"
        case .albums: "Albums"
        case .coverFlow: "Cover Flow"
        case .likedSongs: "Liked Songs"
        case .shuffleSongs: "Shuffle Songs"
        case .settings: "Settings"
        case .playlist(let id): state.library.first { $0.id == id }?.name ?? id
        case .album(let id): state.album(id)?.name ?? id
        case .track(let id): trackLabel(id)
        case .service: "Service: \((state.pendingService ?? state.service).rawValue)"
        case .shuffle: "Shuffle: \(state.shuffle ? "On" : "Off")"
        case .repeatMode: "Repeat: \(state.repeatMode.rawValue)"
        case .skin: "Skin: \(state.skin.rawValue)"
        case .albumArt: "Album Art: \(state.albumArt.rawValue)"
        case .deviceColor: "Color: \(state.deviceColor.rawValue)"
        case .clicker: "Clicker: \(state.clicker ? "On" : "Off")"
        case .nowPlayingBar: "Now Playing Bar: \(state.nowPlayingBar ? "On" : "Off")"
        case .about: "About"
        case .logOut: "Log Out"
        case .cancel: "Cancel"
        case .openBrowser: "Open browser again"
        case .tryAgain: "Try again"
        case .getSpotifyApp: "Get Spotify App"
        case .checkPremium: "Check again"
        case .getPremium: state.words.getPlan
        case .pickService(let service): service.rawValue
        case .openPrivacy: "Open Settings"
        case .useSpotify: "Use Spotify"
        case .premiumLogOut: "Log out"
        case .confirmLogOut: "Log Out"
        case .color(let color): color.rawValue
        case .license(let i): License.all.indices.contains(i) ? License.all[i].name : "License"
        }
    }

    private func trackLabel(_ id: String) -> String {
        guard let playlist = state.top.screen.songList,
            let track = state.track(TrackRef(playlist: playlist, track: id))
        else { return id }
        return "\(track.title) — \(track.artist)"
    }

    private func time(_ seconds: Double) -> String {
        let s = max(Int(seconds), 0)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
