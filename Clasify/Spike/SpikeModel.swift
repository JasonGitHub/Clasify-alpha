import AppKit
import Foundation
import LibrespotBridge
import Observation

/// One Web API call and what came back. Never holds the token.
struct LibraryResult: Sendable, Identifiable {
    var id: String { path }
    let path: String
    var status: Int?
    var count: Int?
    var total: Int?
    var names: [String] = []
    /// Response body, only for 403 and 429. `Retry-After` is added for 429.
    var body: String?
    var error: String?
    /// The first item's playlist ID or track URI, for the next step.
    var firstID: String?

    var passed: Bool { status == 200 }
}

struct LogLine: Identifiable {
    let id: Int
    var text: String
}

/// State and steps of the librespot spike window.
/// The access token lives only in memory, in `token`. It is never shown, logged or copied.
@MainActor
@Observable
final class SpikeModel {
    static let fixedTrackURI = "spotify:track:4uLU6hMCjMI75M1A2tKUQC"

    private(set) var oauth: OAuthResult?
    private(set) var oauthStatus = "Not run"
    private(set) var isLoggingIn = false
    private var token: String?

    private(set) var bridgeStatus = "Not run"
    private(set) var isBridgeLoggedIn = false
    private(set) var isPlaying = false
    private(set) var sawPlaying = false
    private(set) var sawFailure = false
    private(set) var trackURI: String?
    private(set) var trackSource = ""
    private(set) var log: [LogLine] = []
    var heardAudio: Bool?

    private(set) var library: [LibraryResult] = []
    private(set) var isReadingLibrary = false

    @ObservationIgnored private var audio: AudioOutput?
    @ObservationIgnored private var bridge: Bridge?
    @ObservationIgnored private var pendingTrack: String?
    @ObservationIgnored private var playStart = Date()
    @ObservationIgnored private var nextLogID = 0
    @ObservationIgnored private var lastLogWasPosition = false
    @ObservationIgnored private var positionCount = 0

    var hasToken: Bool { token != nil }

    // MARK: Step 1, OAuth login

    func logIn() {
        isLoggingIn = true
        oauthStatus = "Waiting for the browser…"
        let status = Bridge.oauthLogin { result in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.receive(result) }
            }
        }
        if status != LSB_OK {
            isLoggingIn = false
            oauthStatus = "FAIL: lsb_oauth_login returned \(status)"
        }
    }

    private func receive(_ result: OAuthResult) {
        isLoggingIn = false
        oauth = result
        token = result.accessToken
        // A new token needs a new bridge login before the next Play.
        isBridgeLoggedIn = false
        oauthStatus = result.accessToken != nil ? "PASS" : "FAIL: \(result.message ?? "no token")"
    }

    // MARK: Step 2, playback

    func playTestTrack() {
        guard let token else { return }
        if bridge == nil {
            let audio = AudioOutput()
            if let error = audio.start() {
                append("AVAudioEngine did not start: \(error)")
                sawFailure = true
            }
            self.audio = audio
            bridge = Bridge(ring: audio.ring) { event in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self.receive(event) }
                }
            }
            if bridge == nil {
                bridgeStatus = "FAIL: lsb_new returned NULL"
                return
            }
        }
        guard let bridge else { return }
        let liked = library.first { $0.path.hasPrefix("/v1/me/tracks") }?.firstID
        let uri = liked ?? Self.fixedTrackURI
        trackURI = uri
        trackSource = liked != nil ? "first Liked Songs track" : "fixed URI"
        playStart = Date()
        lastLogWasPosition = false
        if isBridgeLoggedIn {
            load(uri, on: bridge)
        } else {
            pendingTrack = uri
            bridgeStatus = "Logging in…"
            let status = bridge.login(accessToken: token)
            append("lsb_login -> \(status)")
        }
    }

    func togglePause() {
        guard let bridge else { return }
        if isPlaying {
            audio?.ring.clear()
            append("lsb_pause -> \(bridge.pause())")
        } else {
            append("lsb_play -> \(bridge.play())")
        }
    }

    private func load(_ uri: String, on bridge: Bridge) {
        append("lsb_load \(uri) -> \(bridge.load(uri))")
    }

    private func receive(_ event: BridgeEvent) {
        switch Int32(event.kind) {
        case LSB_EVENT_LOGGED_IN:
            isBridgeLoggedIn = true
            bridgeStatus = "PASS: LOGGED_IN after \(elapsedMs) ms"
            if let pendingTrack, let bridge {
                self.pendingTrack = nil
                load(pendingTrack, on: bridge)
            }
        case LSB_EVENT_ERROR:
            sawFailure = true
            if !isBridgeLoggedIn { bridgeStatus = "FAIL: \(event.message ?? "")" }
        case LSB_EVENT_PLAYING:
            isPlaying = true
            sawPlaying = true
        case LSB_EVENT_PAUSED, LSB_EVENT_TRACK_ENDED:
            isPlaying = false
        case LSB_EVENT_UNAVAILABLE:
            isPlaying = false
            sawFailure = true
        default:
            break
        }
        var text = event.name
        if event.playRequestID != 0 { text += " id=\(event.playRequestID)" }
        if [LSB_EVENT_PLAYING, LSB_EVENT_PAUSED, LSB_EVENT_POSITION].contains(Int32(event.kind)) {
            text += " pos=\(event.positionMs) ms"
        }
        if let uri = event.trackURI { text += " \(uri)" }
        if let message = event.message { text += " \"\(message)\"" }
        // POSITION comes every 500 ms. Keep one line for a run of them.
        if Int32(event.kind) == LSB_EVENT_POSITION {
            if lastLogWasPosition, !log.isEmpty {
                positionCount += 1
                log[log.count - 1].text = "+\(elapsedMs) ms \(text) (x\(positionCount))"
                return
            }
            positionCount = 1
            append(text)
            lastLogWasPosition = true
            return
        }
        append(text)
    }

    private var elapsedMs: Int { Int(Date().timeIntervalSince(playStart) * 1000) }

    private func append(_ text: String) {
        lastLogWasPosition = false
        log.append(LogLine(id: nextLogID, text: "+\(elapsedMs) ms \(text)"))
        nextLogID += 1
        if log.count > 300 { log.removeFirst(log.count - 300) }
    }

    // MARK: Step 3, library

    func readLibrary() async {
        guard let token else { return }
        isReadingLibrary = true
        defer { isReadingLibrary = false }
        library = []
        let playlists = await Self.get("/v1/me/playlists?limit=50", token: token, kind: .playlists)
        library.append(playlists)
        if let first = playlists.firstID {
            library.append(await Self.get("/v1/playlists/\(first)/tracks?limit=50", token: token, kind: .tracks))
        } else {
            library.append(LibraryResult(path: "/v1/playlists/{first}/tracks", error: "Skipped: no playlist ID"))
        }
        library.append(await Self.get("/v1/me/tracks?limit=50", token: token, kind: .tracks))
    }

    enum ItemKind { case playlists, tracks }

    nonisolated private static func get(_ path: String, token: String, kind: ItemKind) async -> LibraryResult {
        var result = LibraryResult(path: path)
        var request = URLRequest(url: URL(string: "https://api.spotify.com" + path)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            result.status = http?.statusCode
            if result.status == 403 || result.status == 429 {
                var body = String(decoding: data.prefix(1000), as: UTF8.self)
                if let retry = http?.value(forHTTPHeaderField: "Retry-After") { body += "\nRetry-After: \(retry)" }
                result.body = body
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else { return result }
            result.count = items.count
            result.total = json["total"] as? Int
            switch kind {
            case .playlists:
                result.names = items.compactMap { $0["name"] as? String }
                result.firstID = items.first?["id"] as? String
            case .tracks:
                // Spotify calls the field "track"; newer responses may call it "item".
                let tracks = items.compactMap { ($0["track"] ?? $0["item"]) as? [String: Any] }
                result.names = tracks.compactMap { $0["name"] as? String }
                result.firstID = tracks.first?["uri"] as? String
            }
        } catch {
            result.error = error.localizedDescription
        }
        return result
    }

    // MARK: Step 4, report

    func copyReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }

    var playbackStatus: String {
        if trackURI == nil { return "Not run" }
        if sawPlaying && !sawFailure { return "PASS" }
        if sawFailure { return "FAIL" }
        return "No PLAYING event yet"
    }

    /// Plain text for Jason to paste back. It has no token.
    var report: String {
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        var lines = [
            "Clasify librespot spike report",
            "App commit: \(BuildInfo.commit)",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString), \(arch)",
            "librespot: 0.8.0",
            "",
            "1. OAuth login: \(oauthStatus)",
        ]
        if let oauth {
            lines += [
                "   Client ID: \(oauth.clientID)",
                "   Redirect URI: \(oauth.redirectURI)",
                "   Scopes: \(oauth.scopes.joined(separator: " "))",
                "   Refresh token returned: \(oauth.hasRefreshToken ? "yes" : "no")",
                "   Expires in: \(oauth.expiresInSeconds) s",
            ]
        }
        lines += [
            "",
            "2. Playback: \(playbackStatus)",
            "   Bridge login: \(bridgeStatus)",
            "   Track: \(trackURI ?? "none") (\(trackSource))",
            "   Heard audio: \(heardAudio.map { $0 ? "yes" : "no" } ?? "not answered")",
            "   Events:",
        ]
        lines += log.map { "     \($0.text)" }
        lines += ["", "3. Library:"]
        if library.isEmpty { lines.append("   Not run") }
        for result in library {
            let verdict = result.passed ? "PASS" : "FAIL"
            var line = "   \(verdict) GET \(result.path): status \(result.status.map(String.init) ?? "none")"
            if let count = result.count { line += ", \(count) items" }
            if let total = result.total { line += " (total \(total))" }
            if let error = result.error { line += ", \(error)" }
            lines.append(line)
            if let body = result.body { lines.append("     Body: \(body)") }
        }
        return lines.joined(separator: "\n")
    }
}
