import SwiftUI

/// Test window for the librespot spike. Throwaway: the Pocket skin replaces it.
struct SpikeView: View {
    @State private var model = SpikeModel()
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Clasify librespot spike, build \(SpikeModel.build)").font(.title2.bold())
                step1
                Divider()
                step2
                Divider()
                step3
                Divider()
                spotifyAppSection
                Divider()
                goLibrespotSection
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
            Picker("Test track", selection: $model.selectedTrack) {
                ForEach(model.trackChoices, id: \.self) { track in
                    Text(track.label).tag(track)
                }
            }
            .frame(maxWidth: 480)
            TextField("Or type a track URI, like spotify:track:…", text: $model.typedURI)
                .frame(maxWidth: 480)
            Picker("Access point port", selection: $model.accessPointPort) {
                ForEach(SpikeModel.accessPointPorts, id: \.self) { port in
                    Text(port == 0 ? "Default" : String(port)).tag(port)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)
            detail("Access point: \(model.accessPoint). A new port logs in again on the next Play.")
            HStack {
                Button("2. Play test track") { model.playTestTrack() }
                    .disabled(!model.hasToken)
                Button(model.isPlaying ? "Pause" : "Resume") { model.togglePause() }
                    .disabled(model.attempts.isEmpty)
            }
            Text("Result: \(model.playbackStatus)")
            detail("Bridge login: \(model.bridgeStatus)")
            ForEach(model.attempts) { attempt in
                detail("\(attempt.result): \(attempt.label)")
            }
            Picker("Do you hear audio?", selection: $model.heardAudio) {
                Text("Not answered").tag(Bool?.none)
                Text("Yes").tag(Bool?.some(true))
                Text("No").tag(Bool?.some(false))
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)
        }
    }

    private var step3: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button("3a. Read library (librespot)") { model.readLibraryWithLibrespot() }
                    .disabled(!model.hasToken)
                Button("3b. Read library (Web API)") { Task { await model.readLibrary() } }
                    .disabled(!model.hasToken || model.isReadingLibrary)
                if model.isReadingLibrary { ProgressView().controlSize(.small) }
            }
            ForEach(model.librespotLibrary, id: \.self) { line in detail(line) }
            ForEach(model.library) { result in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(result.passed ? "PASS" : "FAIL") GET \(result.path)")
                    if let first = result.firstAttempt { detail("First attempt: \(first)") }
                    detail("Status: \(result.status.map(String.init) ?? "none"), items: \(result.count.map(String.init) ?? "-"), total: \(result.total.map(String.init) ?? "-")")
                    if let error = result.error { detail(error) }
                    if let body = result.body { detail("Body: \(body)") }
                    if !result.names.isEmpty { detail(result.names.prefix(10).joined(separator: " · ")) }
                }
            }
            Text("Tip: run 3a before 2, then pick \"First Liked Songs track\" in the track list.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var spotifyAppSection: some View {
        let app = model.spotifyApp
        return VStack(alignment: .leading, spacing: 6) {
            Text("Spotify app engine (build 4)").font(.headline)
            Text("Run 1 and 3a first. They give the playlist and Liked Songs to play.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Connect to Spotify app") { Task { await app.connect() } }
                Button("Play playlist") {
                    Task {
                        let uri = model.firstPlaylistURI
                        await app.play(context: uri, tracks: uri.flatMap { model.contexts[$0] }, name: "Playlist")
                    }
                }
                Button("Play Liked Songs") {
                    Task {
                        let uri = model.likedContextURI
                        await app.play(context: uri, tracks: uri.flatMap { model.contexts[$0] }, name: "Liked Songs")
                    }
                }
            }
            .disabled(app.isBusy)
            HStack {
                Button("Pause") { Task { await app.pause() } }
                Button("Resume") { Task { await app.resume() } }
                Button("Next") { Task { await app.next() } }
                Button("Prev") { Task { await app.previous() } }
                Button("Seek +30 s") { Task { await app.seekForward() } }
                Button("Volume 50") { Task { await app.volume50() } }
            }
            .disabled(!app.isConnected || app.isBusy)
            HStack {
                Button("Wait for track end") { Task { await app.trackEnd() } }
                Button("Measure memory") { app.memory() }
            }
            .disabled(!app.isConnected || app.isBusy)
            ForEach(app.results) { line in detail("\(line.name): \(line.value)") }
        }
    }

    private var goLibrespotSection: some View {
        let probe = model.goLibrespot
        return VStack(alignment: .leading, spacing: 6) {
            Text("go-librespot (build 6)").font(.headline)
            Text("Logs in through the browser, then plays the 3 test tracks. It runs alone and needs no other step.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Test go-librespot") {
                    Task { await probe.run(tracks: SpikeModel.fixedTracks.map { (name: $0.label, uri: $0.uri) }) }
                }
                .disabled(probe.isBusy)
                Text(probe.status).foregroundStyle(.secondary)
            }
            ForEach(probe.results) { line in detail("\(line.name): \(line.value)") }
        }
    }

    private var connectSection: some View {
        let probe = model.connect
        return VStack(alignment: .leading, spacing: 6) {
            Text("Build 8: Spotify app through Connect commands only").font(.headline)
            Text("Run 1 and 3a first. No AppleScript is used here.").font(.caption).foregroundStyle(.secondary)
            Text("1. Quit Spotify, then click one. Do the other after quitting Spotify again.").font(.caption)
            HStack {
                Button("Cold start (NSWorkspace)") { Task { await probe.coldStart(model: model, useOpenCommand: false) } }
                Button("Cold start (open -g -j)") { Task { await probe.coldStart(model: model, useOpenCommand: true) } }
            }
            Text("2. Open the Spotify window, then click on Clasify so Spotify is behind it.").font(.caption)
            Button("Play, next, Liked Songs with Spotify behind") { Task { await probe.behind(model: model) } }
            Text("3 and 4. While music plays:").font(.caption)
            HStack {
                Button("Test controls") { Task { await probe.controls(model: model) } }
                Button("Wait for track end") { Task { await probe.trackEnd(model: model) } }
            }
            ForEach(probe.results) { line in detail("\(line.name): \(line.value)") }
        }
        .disabled(probe.isBusy)
    }

    private var webPlayerSection: some View {
        let probe = model.webPlayer
        return VStack(alignment: .leading, spacing: 6) {
            Text("Build 7: Web Playback SDK and Spotify Connect").font(.headline)
            Text("Run 1 and 3a first.").font(.caption).foregroundStyle(.secondary)
            Text("A. Web Playback SDK in a hidden web view").font(.subheadline)
            HStack {
                Button("Load web player") { probe.loadSDK(model: model) }
                Button("Transfer to web player") { probe.transferToSDK() }
                Button("Play playlist on web player") { probe.playOnSDK() }
                Button("Try Web API play") { Task { await probe.playOnSDKWithWebAPI() } }
            }
            HStack {
                Text("Heard audio from the web player?")
                Button("Yes") { probe.heard("yes") }
                Button("No") { probe.heard("no") }
                Button("Measure memory") { probe.memory() }
            }
            Text("B. Spotify app started by a Connect command (no AppleScript play)").font(.subheadline)
            HStack {
                Button("Connect play: playlist") { probe.playOnSpotifyApp(model: model, liked: false) }
                Button("Connect play: Liked Songs") { probe.playOnSpotifyApp(model: model, liked: true) }
            }
            ForEach(probe.results) { line in detail("\(line.name): \(line.value)") }
        }
    }

    private var eventLog: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Event and librespot log").font(.headline)
            ForEach(model.log) { line in
                Text(line.text).font(.system(.caption, design: .monospaced))
            }
        }
    }

    private func detail(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
    }
}
