import ClasifyCore
import ClasifySkins
import SwiftUI

/// CLA-101: the skin with the K.3D.8 flip, in every build. The 2D device draws card BL's
/// look. In About, Play/Pause turns the device over to its steel back and back again. While
/// the 3D body shows, Space or a click on it turns it back. Leaving About shows the front.
///
/// Card BR, change 288: at the first launch ever, the device arrives in 3D before Hello. Then
/// it sends `.arrived`, which the reducer saves, as the 2D device fades in. With Reduce Motion, or with no Metal device,
/// it sends `.arrived` at once and shows nothing. Input waits in the reducer until then.
struct K3DSpikeSkin: View {
    let store: Store
    let artwork: Artwork
    @State private var flip = K3DFlip()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            if screen != .about && !flip.arriving { flip = K3DFlip() }
        }
        .task { await arrive() }
    }

    /// Change 288: the arrival, once ever. The 3D front shows the screen as it is at the start,
    /// Hello's first frame. Hello waits in the reducer, so `.arrived` goes as the 2D device
    /// starts to fade in: the live 2D device then starts Hello on the same frame.
    private func arrive() async {
        guard !store.state.arrived else { return }
        if !reduceMotion && K3DFlip.canDraw {
            flip = K3DFlip.arrive { K3DSpike.snapshot(store.state, artwork: artwork) }
            try? await Task.sleep(for: .seconds(K3DFlip.arriveTurn + K3DFlip.arriveHold))
            store.send(.arrived)
            try? await Task.sleep(for: .seconds(K3DFlip.arriveFade))
            flip = K3DFlip()  // at rest on the front, as before
        } else {
            store.send(.arrived)
        }
    }

    private func turn() {
        guard !flip.arriving else { return }  // change 288: no input during the arrival
        // The 3D front shows the screen as it is now. The snapshot is made before the turn starts.
        flip.turn { K3DSpike.snapshot(store.state, artwork: artwork) }
    }
}
