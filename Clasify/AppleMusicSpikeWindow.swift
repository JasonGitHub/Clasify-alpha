// SPIKE: see AppleMusicSpike.swift.
@preconcurrency import MusicKit
import SwiftUI

/// SPIKE: the Apple Music Test window. It opens only from View › Apple Music Test, which shows
/// only when the hidden switch `spike.applemusic` is on.
struct AppleMusicSpikeWindow: Scene {
    static let id = "apple-music-spike"

    var body: some Scene {
        Window("Apple Music Test", id: Self.id) { AppleMusicSpikeView() }
            .defaultLaunchBehavior(.suppressed)
            // No Window-menu item: only the gated View menu button opens it.
            .commandsRemoved()
    }
}

/// SPIKE: View › Apple Music Test, only when the hidden switch is on.
struct AppleMusicSpikeCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            if AppleMusicSpike.isOn {
                Button("Apple Music Test") { openWindow(id: AppleMusicSpikeWindow.id) }
            }
        }
    }
}

struct AppleMusicSpikeView: View {
    @State private var player = AppleMusicSpikePlayer()
    @State private var selection: MusicItemID?
    private let log = AppleMusicSpikeLog.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("1 Authorize") { Task { await player.authorize() } }
                Button("2 Load playlists") { Task { await player.loadPlaylists() } }
                Button("Play selected") {
                    guard let playlist = player.playlists.first(where: { $0.id == selection }) else { return }
                    Task { await player.play(playlist) }
                }
                Button("Play catalog song") { Task { await player.playCatalogSong() } }
            }
            HStack {
                Button("Prev") { Task { await player.previous() } }
                Button("Play/Pause") { Task { await player.togglePause() } }
                Button("Next") { Task { await player.next() } }
                Button("+30 s") { player.seekForward() }
                Text(player.status).font(.caption).lineLimit(1)
            }
            List(player.playlists, id: \.id, selection: $selection) { Text($0.name) }
                .frame(height: 180)
            HStack {
                Text("Log: FLASH? lines show another app's window or activation").font(.headline)
                Spacer()
                Button("Copy log") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(log.text, forType: .string)
                }
                Button("Clear") { log.clear() }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(log.lines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(line.contains("FLASH?") ? Color.red : Color.primary)
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                }
                .onChange(of: log.lines.count) { _, count in proxy.scrollTo(count - 1, anchor: .bottom) }
            }
        }
        .padding(12)
        .frame(minWidth: 760, minHeight: 600)
        .onAppear {
            AppleMusicFlashWatcher.shared.start()
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
            log.add("app", "Clasify build \(build), macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        }
    }
}
