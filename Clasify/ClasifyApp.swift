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

    init() {
        guard let client = LibrespotClient() else {
            store = nil
            return
        }
        let library = LibrespotLibrary(client: client)
        let player = SpotifyConnectPlayer(client: client, library: library)
        let store = Store(player: player, library: library)
        player.send = { [weak store] action in store?.send(action) }
        self.store = store
        haptics = Haptics(store: store)
        let keeper = SessionKeeper(client: client, library: library, player: player, store: store)
        player.reconnect = { [weak keeper] in await keeper?.reconnect() ?? false }
        self.keeper = keeper
        // A change made in the Spotify app shows when the user comes back to Clasify.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak store] _ in
            // The queue is .main, so this runs on the main actor.
            MainActor.assumeIsolated { store?.send(.activated) }
        }
        store.send(.launch)  // restores the stored login
        // The reducer's toast, overlay and scroll bar timers run on .tick. Each .tick redraws the skin,
        // so send it only when a timer has run out.
        // The same loop starts the player's pre-warm when a sign-in or a restore succeeds,
        // and resets the player when the session signs out.
        ticker = Task { [weak store, weak player, artwork] in
            var signedIn = false
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let state = store?.state else { return }
                if state.signedIn && !signedIn { player?.prewarm() }
                if !state.signedIn && signedIn { player?.reset() }
                signedIn = state.signedIn
                artwork.prefetchNext(in: state)
                let now = Dependencies.live.now()
                let toastDone = state.toastUntil > 0 && now > state.toastUntil
                let overlayDone = state.overlayUntil > 0 && now > state.overlayUntil
                let scrollDone = state.scrollUntil > 0 && now > state.scrollUntil
                if toastDone || overlayDone || scrollDone { store?.send(.tick) }
            }
        }
    }
}
