import SwiftUI

@main
struct ClasifyApp: App {
    var body: some Scene {
        WindowGroup("Clasify") {
            SpikeView()
        }
        .windowResizability(.contentSize)
    }
}
