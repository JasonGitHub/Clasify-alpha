import SwiftUI

/// Test window for the librespot spike. Throwaway: the Pocket skin replaces it.
struct SpikeView: View {
    @State private var model = SpikeModel()
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Clasify spike, build \(SpikeModel.build)").font(.title2.bold())
                step1
                Divider()
                step2
                Divider()
                connectSection
                Divider()
                HStack {
                    Button("4. Copy report") {
                        model.copyReport()
                        copied = true
                    }
                    if copied { Text("Copied. Paste it in the project chat.").foregroundStyle(.secondary) }
                }
                Divider()
                eventLog
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 600, height: 760)
        .textSelection(.enabled)
    }

    private var step1: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("1. Log in with Spotify") { model.logIn() }
                .disabled(model.isLoggingIn)
            Text("Result: \(model.oauthStatus)")
            if let oauth = model.oauth {
                detail("Client ID: \(oauth.clientID)")
                detail("Redirect URI: \(oauth.redirectURI)")
                detail("Scopes: \(oauth.scopes.joined(separator: " "))")
                detail("Refresh token returned: \(oauth.hasRefreshToken ? "yes" : "no")")
                detail("Expires in: \(oauth.expiresInSeconds) s")
            }
        }
    }

    private var step2: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("2. Read library (librespot)") { model.readLibraryWithLibrespot() }
                .disabled(!model.hasToken)
            detail("Bridge login: \(model.bridgeStatus)")
            ForEach(model.librespotLibrary, id: \.self) { line in detail(line) }
        }
    }

    private var connectSection: some View {
        let probe = model.connect
        return VStack(alignment: .leading, spacing: 6) {
            Text("3. Spotify app through Connect commands only").font(.headline)
            Text("Run 1 and 2 first. No AppleScript is used here.").font(.caption).foregroundStyle(.secondary)
            Text("a. Quit Spotify, then click one. Do the other after quitting Spotify again.").font(.caption)
            HStack {
                Button("Cold start (NSWorkspace)") { Task { await probe.coldStart(model: model, useOpenCommand: false) } }
                Button("Cold start (open -g -j)") { Task { await probe.coldStart(model: model, useOpenCommand: true) } }
            }
            Text("b. Open the Spotify window, then click on Clasify so Spotify is behind it.").font(.caption)
            Button("Play, next, Liked Songs with Spotify behind") { Task { await probe.behind(model: model) } }
            Text("c. While music plays:").font(.caption)
            HStack {
                Button("Test controls") { Task { await probe.controls(model: model) } }
                Button("Wait for track end") { Task { await probe.trackEnd(model: model) } }
            }
            ForEach(probe.results) { line in detail("\(line.name): \(line.value)") }
        }
        .disabled(probe.isBusy)
    }

    private var eventLog: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Event log").font(.headline)
            ForEach(model.log) { line in
                Text(line.text).font(.system(.caption, design: .monospaced))
            }
        }
    }

    private func detail(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
    }
}
