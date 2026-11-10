import ClasifyCore
import ClasifySkins
import SwiftUI

/// Picks the window style. All window code that needs macOS 15 is in `PlainWindowApp`.
@main
enum Launcher {
    @MainActor static func main() {
        if #available(macOS 15, *) {
            PlainWindowApp.main()
        } else {
            FramedWindowApp.main()
        }
    }
}

/// macOS 15: only the device shows. The window has no frame and a clear background,
/// and it moves when you drag the device.
@available(macOS 15, *)
struct PlainWindowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Clasify") {
            AppContent(model: model)
                // Room for the device's shadow, which the window would cut off.
                .padding(EdgeInsets(top: 10, leading: 30, bottom: 50, trailing: 30))
                .containerBackground(.clear, for: .window)
                .gesture(WindowDragGesture())
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .windowBackgroundDragBehavior(.enabled)
        .commands { DebugCommands(model: model) }
    }
}

/// macOS 14: the device in a normal window frame.
struct FramedWindowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Clasify") {
            AppContent(model: model)
                .padding(24)
                .background(Color(red: 0xc9 / 255, green: 0xd3 / 255, blue: 0xdc / 255))  // the mockup's page
        }
        .windowResizability(.contentSize)
        .commands { DebugCommands(model: model) }
    }
}

/// A Dock click brings the device window to the front, also when Clasify is active and the
/// window is behind another app's window (CLA-47). With no window, SwiftUI opens one.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        !DeviceWindow.raise()
    }
}

@MainActor
enum DeviceWindow {
    /// Puts the device window in front and makes Clasify active: back from the Dock when it
    /// is minimized. Returns false when there is no such window, for example after a close.
    @discardableResult static func raise() -> Bool {
        // Not a panel, the menu bar or a menu. The plain window may not say that it can be
        // key, so a window that can is only preferred.
        let windows = NSApp.windows.filter {
            !($0 is NSPanel) && $0.level == .normal && ($0.isVisible || $0.isMiniaturized)
        }
        guard let window = windows.first(where: { $0.canBecomeKey }) ?? windows.first else { return false }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        return true
    }
}

/// The skin, or the temporary test window while the skin is new.
struct AppContent: View {
    let model: AppModel

    var body: some View {
        if model.showsTestWindow || model.store == nil {
            TestWindow(store: model.store)
                .background(Color(nsColor: .windowBackgroundColor))
        } else if let store = model.store {
            PocketSkin(state: store.state) { store.send($0) }
                .environment(\.artwork, model.artwork.artwork)
        }
    }
}

/// TEMPORARY: a View menu item that switches to the test window. Remove it with TestWindow.swift.
struct DebugCommands: Commands {
    @Bindable var model: AppModel

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Toggle("Show Test Window", isOn: $model.showsTestWindow)
                .keyboardShortcut("t", modifiers: [.command, .option])
        }
    }
}

/// Builds the app's one store. The library and the player share one librespot client,
/// so they use one bridge and one Spotify session.
@MainActor @Observable
final class AppModel {
    let store: Store?
    /// TEMPORARY: shows TestWindow in place of the skin.
    var showsTestWindow = false
    /// The album covers that the skin draws.
    let artwork = ArtworkLoader()
    @ObservationIgnored private var ticker: Task<Void, Never>?
    /// TEST: trackpad ticks that follow the wheel.
    @ObservationIgnored private var haptics: Haptics?
    /// Logs in again in the background when the librespot session drops.
    @ObservationIgnored private var keeper: SessionKeeper?
    /// Sends the Mac's battery to the store, for the title bar.
    @ObservationIgnored private var battery: BatteryWatcher?

    init() {
        guard let client = LibrespotClient() else {
            store = nil
            return
        }
        let library = LibrespotLibrary(client: client)
        let player = SpotifyConnectPlayer(client: client, library: library)
        let store = Store(player: player, library: library, settings: UserDefaults.standard)
        player.send = { [weak store] action in store?.send(action) }
        self.store = store
        let haptics = Haptics(store: store)
        store.onWheelStep = { [weak haptics] in haptics?.step() }
        // Card BB: "Get Spotify App" opens Spotify's download page in the browser.
        store.onGetSpotifyApp = {
            if let url = URL(string: "https://www.spotify.com/download/mac/") { NSWorkspace.shared.open(url) }
        }
        // Card AX, screen 135: "Get Premium" opens Spotify's Premium page in the browser.
        store.onGetPremium = {
            if let url = URL(string: "https://www.spotify.com/premium/") { NSWorkspace.shared.open(url) }
        }
        self.haptics = haptics
        let keeper = SessionKeeper(client: client, library: library, player: player, store: store)
        player.reconnect = { [weak keeper] in await keeper?.reconnect() ?? false }
        self.keeper = keeper
        battery = BatteryWatcher(store: store)
        // A change made in the Spotify app shows when the user comes back to Clasify.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak store] _ in
            // The queue is .main, so this runs on the main actor.
            MainActor.assumeIsolated { store?.send(.activated) }
        }
        // Setup shows the Spotify App screen (card BB) only when the app is missing.
        store.send(.spotifyAppFound(Self.spotifyAppInstalled))
        store.send(.launch)  // restores the stored login
        // The reducer's toast, overlay, scroll bar, cover and Cover Flow letter timers run on .tick. Each .tick redraws the skin,
        // so send it only when a timer has run out.
        // The same loop starts the player's pre-warm when a sign-in or a restore succeeds,
        // and resets the player when the session signs out.
        ticker = Task { [weak store, weak player, artwork] in
            var signedIn = false
            var spotifyCheck = 0.0  // when the Spotify App screen last looked for the app
            var beat = false
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let state = store?.state else { return }
                if state.signedIn && !signedIn { player?.prewarm() }
                if !state.signedIn && signedIn { player?.reset() }
                signedIn = state.signedIn
                artwork.prefetchNext(in: state)
                let now = Dependencies.live.now()
                // While the Spotify App screen shows, look for the app every 3 s, quietly (change 174).
                if state.top.screen == .spotifyApp, now - spotifyCheck >= 3 {
                    spotifyCheck = now
                    store?.send(.spotifyAppFound(Self.spotifyAppInstalled))
                }
                let toastDone = state.toastUntil > 0 && now > state.toastUntil
                let overlayDone = state.overlayUntil > 0 && now > state.overlayUntil
                let scrollDone = state.scrollUntil > 0 && now > state.scrollUntil
                let artDone = state.artUntil > 0 && now > state.artUntil
                let letterDone = state.letterUntil > 0 && now > state.letterUntil
                // "You’re in" (card AX, change 175) goes on after its beat.
                let beatDone = state.beatUntil > 0 && now >= state.beatUntil
                // The first read waits until every playlist name has shown (card AY, change 191).
                let namesDone = state.namesHold > 0 && now >= state.namesHold
                if toastDone || overlayDone || scrollDone || artDone || letterDone || beatDone || namesDone { store?.send(.tick) }
                // When the browser login works (change 170) or the Spotify app is found (174),
                // Clasify comes to the front.
                // Not for "You’re all set": the library read may take long, and the person may work elsewhere.
                let raises = state.beatUntil > 0 && state.top.screen != .yourMusic
                if raises && !beat { DeviceWindow.raise() }
                beat = raises
            }
        }
    }

    /// The Spotify desktop app is on this Mac. Launch Services finds it by its bundle ID; this
    /// does not start it.
    static var spotifyAppInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: SpotifyConnectPlayer.bundleID) != nil
    }
}
