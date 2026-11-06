import AppKit
// Spike: MusicKit response types are not Sendable in the macOS 15.5 SDK. The responses are only read on the main actor.
@preconcurrency import MusicKit
import SwiftUI
import WebKit

@main
struct AppleMusicSpikeApp: App {
    @State private var pathA = PathA()
    @State private var pathB = PathB()
    @State private var pathC = PathC()

    var body: some Scene {
        WindowGroup("Apple Music Spike") {
            ContentView(pathA: pathA, pathB: pathB, pathC: pathC)
                .onAppear {
                    FlashWatcher.shared.start()
                    let version = ProcessInfo.processInfo.operatingSystemVersionString
                    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
                    SpikeLog.shared.add("app", "spike build \(build), macOS \(version)")
                }
        }
    }
}

struct ContentView: View {
    let pathA: PathA
    let pathB: PathB
    let pathC: PathC

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                PathAView(path: pathA)
                PathBView(path: pathB)
                PathCView(path: pathC, model: pathC.model)
            }
            .frame(height: 380)
            LogView(log: SpikeLog.shared)
        }
        .padding(12)
        .frame(minWidth: 1100, minHeight: 720)
    }
}

struct Column<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.12)))
    }
}

struct PathAView: View {
    let path: PathA
    @State private var selection: MusicItemID?

    var body: some View {
        Column(title: "A. MusicKit ApplicationMusicPlayer") {
            HStack {
                Button("1 Authorize") { Task { await path.authorize() } }
                Button("2 Load playlists") { Task { await path.loadPlaylists() } }
            }
            List(path.playlists, id: \.id, selection: $selection) { Text($0.name) }
            HStack {
                Button("Play selected") {
                    guard let playlist = path.playlists.first(where: { $0.id == selection }) else { return }
                    Task { await path.play(playlist) }
                }
                Button("Play catalog song") { Task { await path.playCatalogSong() } }
            }
            HStack {
                Button("Prev") { Task { await path.previous() } }
                Button("Play/Pause") { Task { await path.togglePause() } }
                Button("Next") { Task { await path.next() } }
                Button("+30 s") { path.seekForward() }
            }
            Text(path.status).font(.caption).lineLimit(2)
        }
    }
}

struct PathBView: View {
    let path: PathB
    @State private var selection: String?

    var body: some View {
        Column(title: "B. Music app hidden + AppleScript") {
            HStack {
                Button("1 Launch hidden") { path.launchHidden() }
                Button("Quit Music") { path.quitMusic() }
            }
            HStack {
                Button("2 Load (ITLibrary)") { path.loadWithITLibrary() }
                Button("Load (AppleScript)") { path.loadWithAppleScript() }
            }
            List(path.playlists, selection: $selection) { Text($0.name) }
            Button("Play selected") {
                guard let playlist = path.playlists.first(where: { $0.id == selection }) else { return }
                path.play(playlist)
            }
            HStack {
                Button("Prev") { path.previous() }
                Button("Play/Pause") { path.togglePause() }
                Button("Next") { path.next() }
                Button("+30 s") { path.seekForward() }
            }
            Text(path.status).font(.caption).lineLimit(2)
        }
    }
}

struct PathCView: View {
    let path: PathC
    let model: PathCModel
    @State private var token = ""
    @State private var selection: String?

    var body: some View {
        Column(title: "C. MusicKit JS in a hidden web view") {
            HStack {
                SecureField(model.hasToken ? "Token saved in Keychain" : "Paste developer token", text: $token)
                Button("Save") { path.saveToken(token); token = "" }
                Button("Delete") { path.deleteToken() }
            }
            HStack {
                Button("1 Configure") { Task { await path.configure() } }
                Button("2 Sign in") { Task { await path.authorize() } }
                Button("3 Load playlists") { Task { await path.loadPlaylists() } }
            }
            List(model.playlists, selection: $selection) { Text($0.name) }
            HStack {
                Button("Play selected") {
                    guard let playlist = model.playlists.first(where: { $0.id == selection }) else { return }
                    Task { await path.play(playlist) }
                }
                Button("Play catalog song") { Task { await path.playCatalogSong() } }
            }
            HStack {
                Button("Play/Pause") { Task { await path.togglePause() } }
                Button("Next") { Task { await path.next() } }
                Button("+30 s") { Task { await path.seekForward() } }
            }
            Text(model.status).font(.caption).lineLimit(2)
            HiddenWebView(webView: path.webView).frame(width: 1, height: 1)
        }
    }
}

struct HiddenWebView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct LogView: View {
    let log: SpikeLog

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Log (lines marked FLASH? show another app's window or activation)").font(.headline)
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
    }
}
