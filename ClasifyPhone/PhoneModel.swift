import ClasifyAppleMusic
import ClasifyCore
import ClasifyShell
import Foundation
import UIKit

/// Builds the iPhone app's one store: Apple Music through MusicKit, the same shared code as
/// the Mac. No Spotify, no On This Mac, no activation, no beta notices (`Features` for `.phone`).
/// No analytics: nothing sets `onBetaEvent`.
@MainActor @Observable
final class PhoneModel {
    let store: Store
    /// The album covers that the skin draws. No library covers on the phone: MusicKit Artwork
    /// URLs only, memory only.
    let artwork = ArtworkLoader()
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var haptics: PhoneHaptics?
    @ObservationIgnored private var battery: PhoneBattery?

    init() {
        // The phone volume stays with iOS: its buttons only (plan decision 4).
        let player = AppleMusicPlayer(volume: nil)
        let library = AppleMusicLibrary(covers: NoLibraryCovers())
        let store = Store(player: player, library: library, settings: UserDefaults.standard, platform: .phone)
        player.send = { [weak store] action in store?.send(action) }
        player.setActive(true)  // the one service, so it is always the active one
        // "Get Apple Music" opens Apple's page; "Open Settings" opens this app's page in Settings.
        store.onGetPremium = { Self.open("https://www.apple.com/apple-music/") }
        store.onOpenPrivacy = { Self.open(UIApplication.openSettingsURLString) }
        // Card CX: About's Report a Problem. A new mail with no body; with no mail app, a message.
        store.onOpenMail = { [weak store] in
            guard let url = URL(string: "mailto:feedback@getmypod.app") else { return }
            Task { @MainActor in
                if !(await UIApplication.shared.open(url)) { store?.send(.mailFailed) }
            }
        }
        self.store = store
        store.send(.launch)  // restores the stored login
        // The reducer's timers run on .tick, which this loop sends when `AppState.tickDue(at:)` says so.
        ticker = Task { [weak store, artwork] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let state = store?.state else { return }
                artwork.prefetchNext(in: state)
                if state.tickDue(at: Dependencies.live.now()) { store?.send(.tick) }
            }
        }
    }

    /// Starts the haptic tick and the battery reading, once, when the first scene is active.
    /// UIKit's device and feedback objects want a running app, not the `App` initializer.
    func startDevice() {
        guard haptics == nil else { return }
        let haptics = PhoneHaptics(store: store)
        store.onWheelStep = { [weak haptics] in haptics?.step() }
        self.haptics = haptics
        battery = PhoneBattery(store: store)
    }

    private static func open(_ page: String) {
        if let url = URL(string: page) { UIApplication.shared.open(url) }
    }
}
