import ClasifyCore
import SwiftUI

@main
struct ClasifyApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Clasify") {
            PlaceholderView(store: model.store)
        }
        .windowResizability(.contentSize)
    }
}

/// Builds the app's one store. The library and the player share one librespot client,
/// so they use one bridge and one Spotify session.
@MainActor
final class AppModel {
    let store: Store?

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
    }
}

/// Temporary window until the Pocket skin exists. It shows the store's first screen.
struct PlaceholderView: View {
    let store: Store?

    var body: some View {
        VStack(spacing: 8) {
            Text("Clasify").font(.largeTitle)
            if let store {
                Text("Screen: \(String(describing: store.state.top.screen))")
                    .foregroundStyle(.secondary)
            } else {
                Text("Can’t start the Spotify bridge").foregroundStyle(.secondary)
            }
        }
        .frame(width: 320, height: 240)
    }
}
