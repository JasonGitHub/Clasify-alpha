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
    @ObservationIgnored private var ticker: Task<Void, Never>?

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
        store.send(.launch)  // restores the stored login
        // The reducer's toast and overlay timers run on .tick. Send it only while one runs,
        // so an idle app does not redraw.
        ticker = Task { [weak store] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let store else { return }
                if store.state.toastUntil > 0 || store.state.overlayUntil > 0 { store.send(.tick) }
            }
        }
    }
}
