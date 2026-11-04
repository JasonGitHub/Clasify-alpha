import ClasifyCore
import SwiftUI

@main
struct ClasifyApp: App {
    var body: some Scene {
        WindowGroup("Clasify") {
            PlaceholderView()
        }
        .windowResizability(.contentSize)
    }
}

/// Temporary window until the Pocket skin exists. It reads `AppState` so the build proves that ClasifyCore links.
struct PlaceholderView: View {
    private let state = AppState()

    var body: some View {
        VStack(spacing: 8) {
            Text("Clasify").font(.largeTitle)
            Text("First screen: \(String(describing: state.stack[0].screen))")
                .foregroundStyle(.secondary)
        }
        .frame(width: 320, height: 240)
    }
}
