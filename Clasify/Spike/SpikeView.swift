import SwiftUI

/// Test window for the librespot spike. Throwaway: the Pocket skin replaces it.
struct SpikeView: View {
    @State private var model = SpikeModel()
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Clasify librespot spike").font(.title2.bold())
                step1
                Divider()
                step2
                Divider()
                step3
                Divider()
                HStack {
                    Button("4. Copy report") {
                        model.copyReport()
                        copied = true
                    }
                    if copied { Text("Copied. Paste it in the project chat.").foregroundStyle(.secondary) }
                }
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
            HStack {
                Button("2. Play test track") { model.playTestTrack() }
                    .disabled(!model.hasToken)
                Button(model.isPlaying ? "Pause" : "Resume") { model.togglePause() }
                    .disabled(model.trackURI == nil)
            }
            Text("Result: \(model.playbackStatus)")
            detail("Bridge login: \(model.bridgeStatus)")
            if let uri = model.trackURI { detail("Track: \(uri) (\(model.trackSource))") }
            Picker("Do you hear audio?", selection: $model.heardAudio) {
                Text("Not answered").tag(Bool?.none)
                Text("Yes").tag(Bool?.some(true))
                Text("No").tag(Bool?.some(false))
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)
            Text("Event log").font(.headline)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(model.log) { line in
                    Text(line.text).font(.system(.caption, design: .monospaced))
                }
            }
        }
    }

    private var step3: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("3. Read library") { Task { await model.readLibrary() } }
                .disabled(!model.hasToken || model.isReadingLibrary)
            ForEach(model.library) { result in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(result.passed ? "PASS" : "FAIL") GET \(result.path)")
                    detail("Status: \(result.status.map(String.init) ?? "none"), items: \(result.count.map(String.init) ?? "-"), total: \(result.total.map(String.init) ?? "-")")
                    if let error = result.error { detail(error) }
                    if let body = result.body { detail("Body: \(body)") }
                    if !result.names.isEmpty { detail(result.names.prefix(10).joined(separator: " · ")) }
                }
            }
            Text("Tip: run step 3 before step 2 to play your first Liked Songs track.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func detail(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
    }
}
