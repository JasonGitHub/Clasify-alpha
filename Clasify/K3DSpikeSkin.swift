import ClasifyCore
import ClasifySkins
import SwiftUI

/// CLA-101: the skin with the K.3D.8 flip, in every build. The 2D device draws card BL's
/// look. In About, Play/Pause turns the device over to its steel back and back again. While
/// the 3D body shows, Space or a click on it turns it back. Leaving About shows the front.
struct K3DSpikeSkin: View {
    let store: Store
    let artwork: Artwork
    @State private var flip = K3DFlip()

    var body: some View {
        K3DFlipView(flip: flip, black: store.state.shownColor == .black, margin: DeviceWindow.margin, onTap: turn) {
            PocketSkin(state: store.state) { action in
                if case .play = action, store.state.top.screen == .about {
                    turn()
                } else {
                    store.send(action)
                }
            }
            .environment(\.artwork, artwork)
        }
        .onChange(of: store.state.top.screen) { _, screen in
            if screen != .about { flip = K3DFlip() }
        }
    }

    private func turn() {
        // The 3D front shows the screen as it is now. The snapshot is made before the turn starts.
        flip.turn { K3DSpike.snapshot(store.state, artwork: artwork) }
    }
}
