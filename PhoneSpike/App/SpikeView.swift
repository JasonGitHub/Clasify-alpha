import ClasifyCore
import SwiftUI

/// CLA-202 spike screen. Plain system controls: the look is not part of the spike.
struct SpikeView: View {
    @Bindable var model: SpikeModel
    @Environment(\.scenePhase) private var phase

    var body: some View {
        NavigationStack {
            List {
                Section("Apple Music") {
                    Text("Access: \(model.auth)")
                    Text("Subscription: \(model.subscription)")
                    Button("Ask for access and read lists") { Task { await model.start() } }
                }
                Section("Now") {
                    if let cover = model.cover {
                        Image(uiImage: cover).resizable().scaledToFit().frame(width: 160, height: 160)
                    }
                    Text(model.nowTitle.isEmpty ? "Nothing plays" : model.nowTitle)
                    HStack {
                        Button("Prev") { model.prev() }.buttonStyle(.bordered)
                        Spacer()
                        Button(model.playing ? "Pause" : "Play") { model.playPause() }.buttonStyle(.bordered)
                        Spacer()
                        Button("Next") { model.next() }.buttonStyle(.bordered)
                    }
                }
                Section("Lists (tap to play from the first song)") {
                    ForEach(model.lists, id: \.id) { list in
                        Button(list.name) { Task { await model.play(list) } }
                    }
                }
                Section("Report (no names)") {
                    Button("Run reducer check") { Task { await model.reducerCheck() } }
                    Button("Copy report") { model.copyReport() }
                    ForEach(Array(model.report.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption.monospaced())
                    }
                }
            }
            .navigationTitle("myPod spike")
        }
        .onChange(of: phase) { _, new in model.phaseChanged(new) }
    }
}
