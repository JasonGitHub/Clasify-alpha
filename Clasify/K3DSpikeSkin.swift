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
///
/// Card BR, changes 289 and 290: a color change on Pick Your Color, or on the Settings Color
/// row, spins the device once in 3D, in place of the color fade. With Reduce Motion it fades.
///
/// CLA-117, a trial: at each later launch of the app (not a window reopen), the device arrives
/// in 3D too, as the UserDefaults string `arrive.cold` says. Missing or "short" is change 303,
/// a 1.0 s turn that input hurries. "full" is change 288 with no Hello, and input waits until it
/// lands. "off" or any other value: no arrival. Reduce Motion or no Metal: no arrival.
struct K3DSpikeSkin: View {
    let store: Store
    let artwork: Artwork
    @State private var flip: K3DFlip

    /// CLA-117: the cold-start arrival, read once at launch.
    enum Cold: Equatable {
        case short, full, off

        init(_ value: String?) {
            switch value {
            case nil, "short": self = .short
            case "full": self = .full
            default: self = .off
            }
        }
    }

    static let cold = Cold(UserDefaults.standard.string(forKey: "arrive.cold"))
    /// This launch's arrival has started, or was skipped. A window opened later shows at once.
    @MainActor private static var launched = false

    /// Change 288: at the first launch, the very first frame already waits for the arrival, so
    /// the 2D device does not flash before the turn. The cold-start arrival waits the same way.
    init(store: Store, artwork: Artwork) {
        self.store = store
        self.artwork = artwork
        let arrives = !store.state.arrived || (!Self.launched && Self.cold != .off)
        _flip = State(initialValue: arrives ? .waiting : K3DFlip())
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        K3DFlipView(flip: flip, black: store.state.shownColor == .black, margin: DeviceWindow.margin, onTap: turn) {
            PocketSkin(state: store.state) { action in
                // CLA-117: the full arrival takes no input until it lands. The short one lands in
                // 0.25 s at most, and the input still does its job.
                if flip.holdsInput(at: .now) { return }
                flip.hurry(at: .now)
                if case .play = action, store.state.top.screen == .about, !flip.arriving {
                    turn()
                } else {
                    store.send(action)
                }
            }
            .environment(\.artwork, artwork)
        }
        .onChange(of: store.state.top.screen) { _, screen in
            if screen != .about && !flip.arriving && !flip.isSpinning(at: .now) { flip = K3DFlip() }
        }
        .onChange(of: ColorCue(top: store.state.top, black: store.state.shownColor == .black)) { old, new in
            colorChanged(from: old, to: new)
        }
        .task { await arrive() }
    }

    /// The first launch ever has its arrival with Hello (change 288). A later launch has the
    /// cold-start trial (CLA-117), once per launch.
    private func arrive() async {
        let first = !Self.launched
        Self.launched = true
        guard !store.state.arrived else { return await arriveFirst() }
        guard first, Self.cold != .off else {
            if flip.arriving { flip = K3DFlip() }  // never stay waiting
            return
        }
        await arriveCold()
    }

    /// CLA-117: the arrival at a later launch, on the screen the app opens on, with no Hello.
    private func arriveCold() async {
        guard !reduceMotion && K3DFlip.canDraw else {
            flip = K3DFlip()  // Reduce Motion or no Metal: the 2D device shows at once
            return
        }
        let state = store.state
        if Self.cold == .short {
            flip = K3DFlip.arriveShort { K3DSpike.snapshot(state, artwork: artwork) }
            // Input can hurry the turn: wait for its end as it is now.
            while flip.arriving, flip.ends > .now {
                do { try await Task.sleep(for: .seconds(flip.ends.timeIntervalSinceNow)) } catch { break }
            }
        } else {
            flip = K3DFlip.arrive { K3DSpike.snapshot(state, artwork: artwork) }
            try? await Task.sleep(for: .seconds(K3DFlip.arriveTurn + K3DFlip.arriveFade))
        }
        flip = K3DFlip()  // at rest on the front
    }

    /// Change 288: the arrival, once ever. The 3D front shows the screen as it is at the start,
    /// Hello's first frame, with nothing written. Hello waits until `.arrived`, which goes 0.2 s
    /// (Hello's own wait) before the turn ends: so the first stroke lands as the turn ends and
    /// the 2D device starts to fade in. Nothing is written before that.
    private func arriveFirst() async {
        if !reduceMotion && K3DFlip.canDraw {
            // Hello's clock is pinned to its start: a slow launch must not show a half-written word.
            let state = store.state
            let time = state.top.screen == .hello ? state.helloAt : nil
            flip = K3DFlip.arrive { K3DSpike.snapshot(state, artwork: artwork, time: time) }
            try? await Task.sleep(for: .seconds(K3DFlip.arriveTurn - K3DFlip.arriveHelloLead))
            store.send(.arrived)
            try? await Task.sleep(for: .seconds(K3DFlip.arriveHelloLead + K3DFlip.arriveFade))
            flip = K3DFlip()  // at rest on the front, as before
        } else {
            flip = K3DFlip()  // Reduce Motion or no Metal: the 2D device shows at once
            store.send(.arrived)
        }
    }

    /// Changes 289 and 290: a new color on the same screen spins the device. During a spin the
    /// 3D screen stays live, and the spin lands on the last color: there is no second spin.
    private func colorChanged(from old: ColorCue, to new: ColorCue) {
        // During a spin or the short arrival (CLA-117), any new row, color or screen shows on the 3D front.
        if flip.takesInput(at: .now) {
            flip.show(screen: K3DSpike.snapshot(store.state, artwork: artwork))
            return
        }
        guard old.black != new.black, old.top.screen == new.top.screen else { return }
        let turn: Double
        switch new.top.screen {
        case .color: turn = K3DFlip.spinPick
        case .settings: turn = K3DFlip.spinSettings
        default: return
        }
        guard !reduceMotion, K3DFlip.canDraw, flip.restsOnFront(at: .now) else { return }
        flip = K3DFlip.spin(turn: turn, fromBlack: old.black) { K3DSpike.snapshot(store.state, artwork: artwork) }
    }

    private func turn() {
        guard !flip.arriving, !flip.isSpinning(at: .now) else { return }  // no flip during an arrival or a spin
        // The 3D front shows the screen as it is now. The snapshot is made before the turn starts.
        flip.turn { K3DSpike.snapshot(store.state, artwork: artwork) }
    }
}

/// What a color spin starts from: the screen, its rows, and the device's color (changes 289
/// and 290). During a spin, any change of it takes a new picture for the 3D front.
private struct ColorCue: Equatable {
    let top: Frame
    let black: Bool
}
