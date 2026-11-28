import ClasifyCore
import SwiftUI

/// CLA-202, step 6: the iPhone app "myPod". Apple Music only, the 2D device only, portrait.
/// It shows only the device: the iOS status bar is hidden (card CX).
@main
struct PhoneApp: App {
    @State private var model = PhoneModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            PhoneDevice(store: model.store, artwork: model.artwork.artwork)
                .statusBarHidden(true)
        }
        // Back from the Settings app, Access is off checks again (as the Mac's didBecomeActive).
        .onChange(of: phase) { _, new in
            if new == .active { model.store.send(.activated) }
        }
    }
}
