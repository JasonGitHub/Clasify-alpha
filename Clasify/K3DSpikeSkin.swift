import ClasifyCore
import ClasifySkins
import SwiftUI

/// SPIKE (CLA-101): the skin with the K.3D.1 flip. Shows only when the hidden switch
/// `spike.k3d` is on (`defaults write app.clasify.Clasify spike.k3d -bool true`, then
/// relaunch). The 2D device draws card BL's look. In About, Play/Pause turns the device over
/// to its steel back and back again. While the 3D body shows, Space or a click on it turns it
/// back. Leaving About shows the front.
struct K3DSpikeSkin: View {
    let store: Store
    let artwork: Artwork
    @State private var flip = K3DFlip()

    /// Read once at launch.
    static let isOn = UserDefaults.standard.bool(forKey: K3DSpike.key)

    var body: some View {
        K3DFlipView(flip: flip, margin: DeviceWindow.margin, onTap: turn) {
            PocketSkin(state: store.state) { action in
                if case .play = action, store.state.top.screen == .about {
                    turn()
                } else {
                    store.send(action)
                }
            }
            .environment(\.artwork, artwork)
        }
        // K.3D spike 2: with the switch on, the 2D device draws card BL's look.
        .environment(\.pocketLook, .bl)
        .onChange(of: store.state.top.screen) { _, screen in
            if screen != .about { flip = K3DFlip() }
        }
    }

    private func turn() {
        // The 3D front shows the screen as it is now.
        flip.toggle(at: .now, screen: flip.toBack ? nil : K3DSpike.snapshot(store.state, artwork: artwork))
    }
}
