import SwiftUI

/// CLA-202 spike: the Mac's Apple Music player and library on an iPhone. Never merged.
@main
struct PhoneSpikeApp: App {
    @State private var model = SpikeModel()

    var body: some Scene {
        WindowGroup { SpikeView(model: model) }
    }
}
