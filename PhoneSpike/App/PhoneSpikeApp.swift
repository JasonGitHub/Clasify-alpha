import SwiftUI

/// CLA-202: the iPhone test app "myPod Test". It runs the Mac's Apple Music player and library on an iPhone.
@main
struct PhoneSpikeApp: App {
    @State private var model = SpikeModel()

    var body: some Scene {
        WindowGroup { SpikeView(model: model) }
    }
}
