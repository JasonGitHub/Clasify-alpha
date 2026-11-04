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
    /// Summary of the first attempt when it got 429 and the call was retried.
    var firstAttempt: String?

    var passed: Bool { status == 200 }
}

struct LogLine: Identifiable {
    let id: Int
    var text: String
}

struct TestTrack: Hashable {
    let label: String
    let uri: String
}

/// One Play press and its outcome.
struct TrackAttempt: Identifiable {
    let id: Int
    let label: String
    let uri: String
    var result = "no result yet"
}

/// State and steps of the librespot spike window.
/// The access token lives only in memory, in `token`. It is never shown, logged or copied.
@MainActor
@Observable
final class SpikeModel {
    static let build = 5
    /// Access point port filters to try. 0 means librespot's default (no filter).
    static let accessPointPorts: [UInt16] = [0, 4070, 443, 80]
    /// Three tracks from different major labels, so one label's rights cannot explain a failure.
    static let fixedTracks = [
        TestTrack(label: "Rick Astley, Never Gonna Give You Up (Sony)", uri: "spotify:track:4uLU6hMCjMI75M1A2tKUQC"),
        TestTrack(label: "Queen, Bohemian Rhapsody (Universal)", uri: "spotify:track:4u7EnebtmKWzUH433cf5Qv"),
        TestTrack(label: "Ed Sheeran, Shape of You (Warner)", uri: "spotify:track:7qiZfU4dY1lWllzX7mPBI3"),
    ]

    private(set) var oauth: OAuthResult?
    private(set) var oauthStatus = "Not run"
    private(set) var isLoggingIn = false
    private var token: String?

    private(set) var bridgeStatus = "Not run"
    private(set) var isBridgeLoggedIn = false
    private(set) var isPlaying = false
    private(set) var attempts: [TrackAttempt] = []
    private(set) var log: [LogLine] = []
    var selectedTrack = fixedTracks[0]
    var typedURI = ""
    /// Port filter for the next bridge login. Changing it forces a new login.
    var accessPointPort: UInt16 = 0 {
        didSet { if accessPointPort != oldValue { isBridgeLoggedIn = false } }
    }
    /// The access point the current session connected to, read from the librespot log.
    private(set) var accessPoint = "unknown"
    var heardAudio: Bool?

    private(set) var library: [LibraryResult] = []
    private(set) var isReadingLibrary = false
    private(set) var librespotLibrary: [String] = []
    private(set) var likedViaLibrespot: String?
    /// Track URIs of contexts read through librespot, by context URI.
    private(set) var contexts: [String: [String]] = [:]
    private(set) var firstPlaylistURI: String?
    private(set) var likedContextURI: String?
    /// The Spotify app engine test (build 4).
    let spotifyApp = SpotifyAppProbe()

    @ObservationIgnored private var audio: AudioOutput?
    @ObservationIgnored private var bridge: Bridge?
    @ObservationIgnored private var afterLogin: [(Bridge) -> Void] = []
    @ObservationIgnored private var start = Date()
    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private var lastLogWasPosition = false
    @ObservationIgnored private var positionCount = 0

    var hasToken: Bool { token != nil }

    /// Fixed tracks plus the first Liked Songs track, when a library read found one.
    var trackChoices: [TestTrack] {
        var choices = Self.fixedTracks
        if let uri = likedViaLibrespot {
            choices.append(TestTrack(label: "First Liked Songs track (librespot)", uri: uri))
        }
        if let uri = library.first(where: { $0.path.hasPrefix("/v1/me/tracks") })?.firstID {
            choices.append(TestTrack(label: "First Liked Songs track (Web API)", uri: uri))
        }
        return choices
    }

    /// Wraps a main-actor handler for a bridge thread. Built in a nonisolated function, so
    /// the returned closure has no actor isolation and may run on any thread. It hops to
    /// the main queue in FIFO order, which keeps the event order.
    nonisolated private static func onMain<T: Sendable>(
        _ handler: @escaping @MainActor @Sendable (T) -> Void
    ) -> @Sendable (T) -> Void {
        { value in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { handler(value) }
            }
        }
    }

    // MARK: Step 1, OAuth login

    func logIn() {
        isLoggingIn = true
        oauthStatus = "Waiting for the browser…"
        let status = Bridge.oauthLogin(onResult: Self.onMain { [self] result in receive(result) })
        if status != LSB_OK {
            isLoggingIn = false
            oauthStatus = "FAIL: lsb_oauth_login returned \(status)"
        }
    }

    private func receive(_ result: OAuthResult) {
        isLoggingIn = false
        oauth = result
        token = result.accessToken
        // A new token needs a new bridge login before the next bridge call.
        isBridgeLoggedIn = false
        oauthStatus = result.accessToken != nil ? "PASS" : "FAIL: \(result.message ?? "no token")"
    }

    // MARK: Bridge login

    /// Runs `action` once the bridge is logged in with the current token.
    private func withBridge(_ action: @escaping (Bridge) -> Void) {
        guard let token else { return }
        if bridge == nil {
            let audio = AudioOutput()
            if let error = audio.start() {
                append("AVAudioEngine did not start: \(error)")
            }
            self.audio = audio
            bridge = Bridge(ring: audio.ring, onEvent: Self.onMain { [self] event in receive(event) })
            if bridge == nil {
                bridgeStatus = "FAIL: lsb_new returned NULL"
                return
            }
        }
        guard let bridge else { return }
        if isBridgeLoggedIn {
            action(bridge)
            return
        }
        afterLogin.append(action)
        if afterLogin.count == 1 {
            bridgeStatus = "Logging in…"
            accessPoint = "unknown"
            append("lsb_set_ap_port \(accessPointPort) -> \(bridge.setAccessPointPort(accessPointPort))")
            append("lsb_login -> \(bridge.login(accessToken: token))")
        }
    }

    // MARK: Step 2, playback

    func playTestTrack() {
        let typed = typedURI.trimmingCharacters(in: .whitespaces)
        let track = typed.isEmpty ? selectedTrack : TestTrack(label: "Typed URI", uri: typed)
        let port = accessPointPort == 0 ? "default" : String(accessPointPort)
        attempts.append(TrackAttempt(id: nextID, label: "\(track.label) [AP port \(port)]", uri: track.uri))
        nextID += 1
        withBridge { [self] bridge in
            audio?.ring.clear()
            append("lsb_load \(track.uri) -> \(bridge.load(track.uri))")
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

    /// Sets the result of the newest attempt for `uri` that has no result yet.
    private func record(_ result: String, for uri: String?) {
        guard let uri,
              let index = attempts.lastIndex(where: { $0.uri == uri && $0.result == "no result yet" })
        else { return }
        attempts[index].result = result
    }

    private func receive(_ event: BridgeEvent) {
        switch Int32(event.kind) {
        case LSB_EVENT_LOGGED_IN:
            isBridgeLoggedIn = true
            bridgeStatus = "PASS: LOGGED_IN after \(elapsedMs) ms"
            if let bridge {
                let actions = afterLogin
                afterLogin = []
                actions.forEach { $0(bridge) }
            }
        case LSB_EVENT_ERROR:
            if !isBridgeLoggedIn {
                bridgeStatus = "FAIL: \(event.message ?? "")"
                afterLogin = []
            }
        case LSB_EVENT_PLAYING:
            isPlaying = true
            record("PLAYING on \(accessPoint)", for: event.trackURI)
        case LSB_EVENT_PAUSED, LSB_EVENT_TRACK_ENDED:
            isPlaying = false
        case LSB_EVENT_UNAVAILABLE:
            isPlaying = false
            record("UNAVAILABLE on \(accessPoint)", for: event.trackURI)
        case LSB_EVENT_LOG:
            if let message = event.message, let range = message.range(of: "Connecting to AP ") {
                accessPoint = String(message[range.upperBound...]).replacingOccurrences(of: "\"", with: "")
            }
        case LSB_EVENT_LIBRARY:
            librespotLibrary.append(event.message ?? "")
            if let uri = event.trackURI {
                if uri.hasPrefix("spotify:playlist:") {
                    firstPlaylistURI = uri
                    if let bridge { append("lsb_read_context \(uri) -> \(bridge.readContext(uri))") }
                } else {
                    likedViaLibrespot = uri
                }
            }
        case LSB_EVENT_CONTEXT:
            if let uri = event.trackURI, let message = event.message {
                if message.hasPrefix("ERROR") {
                    librespotLibrary.append("FAIL context \(uri): \(message)")
                } else {
                    let tracks = message.split(separator: "\n").map(String.init)
                    contexts[uri] = tracks
                    if uri.hasSuffix(":collection") { likedContextURI = uri }
                    librespotLibrary.append("PASS context \(uri): \(tracks.count) tracks")
                }
            }
            // The track list is long. Log only the summary line above.
            return
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

    /// Milliseconds since the window opened, so all lines share one clock.
    private var elapsedMs: Int { Int(Date().timeIntervalSince(start) * 1000) }

    private func append(_ text: String) {
        lastLogWasPosition = false
        log.append(LogLine(id: nextID, text: "+\(elapsedMs) ms \(text)"))
        nextID += 1
        if log.count > 600 { log.removeFirst(log.count - 600) }
    }

    // MARK: Step 3a, library through librespot

    func readLibraryWithLibrespot() {
        librespotLibrary = []
        withBridge { [self] bridge in
            append("lsb_read_library -> \(bridge.readLibrary())")
        }
    }

    // MARK: Step 3b, library through the Web API

    func readLibrary() async {
        guard let token else { return }
        isReadingLibrary = true
        defer { isReadingLibrary = false }
        library = []
        let playlists = await Self.getWithRetry("/v1/me/playlists?limit=50", token: token, kind: .playlists)
        library.append(playlists)
        if let first = playlists.firstID {
            library.append(await Self.getWithRetry("/v1/playlists/\(first)/tracks?limit=50", token: token, kind: .tracks))
        } else {
            library.append(LibraryResult(path: "/v1/playlists/{first}/tracks", error: "Skipped: no playlist ID"))
        }
        library.append(await Self.getWithRetry("/v1/me/tracks?limit=50", token: token, kind: .tracks))
    }

    enum ItemKind { case playlists, tracks }

    /// On 429, waits for Retry-After (at most 60 s) and tries once more.
    nonisolated private static func getWithRetry(_ path: String, token: String, kind: ItemKind) async -> LibraryResult {
        let first = await get(path, token: token, kind: kind)
        guard first.status == 429 else { return first }
        let wait = min(first.retryAfter ?? 5, 60)
        try? await Task.sleep(for: .seconds(wait))
        var second = await get(path, token: token, kind: kind)
        second.firstAttempt = "status 429, Retry-After \(first.retryAfter.map(String.init) ?? "none"), waited \(wait) s"
        return second
    }

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
        if attempts.isEmpty { return "Not run" }
        let played = attempts.filter { $0.result.hasPrefix("PLAYING") }.count
        return played > 0 ? "PASS (\(played) of \(attempts.count) played)" : "FAIL (0 of \(attempts.count) played)"
    }

    /// Plain text for Jason to paste back. It has no token.
    var report: String {
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        var lines = [
            "Clasify librespot spike report, build \(Self.build)",
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
            "   Heard audio: \(heardAudio.map { $0 ? "yes" : "no" } ?? "not answered")",
        ]
        lines += attempts.map { "   \($0.result): \($0.label) \($0.uri)" }
        lines += ["", "3a. Library through librespot:"]
        lines += librespotLibrary.isEmpty ? ["   Not run"] : librespotLibrary.map { "   \($0)" }
        lines += ["", "3b. Library through the Web API:"]
        if library.isEmpty { lines.append("   Not run") }
        for result in library {
            let verdict = result.passed ? "PASS" : "FAIL"
            if let first = result.firstAttempt { lines.append("   First attempt GET \(result.path): \(first)") }
            var line = "   \(verdict) GET \(result.path): status \(result.status.map(String.init) ?? "none")"
            if let count = result.count { line += ", \(count) items" }
            if let total = result.total { line += " (total \(total))" }
            if let error = result.error { line += ", \(error)" }
            lines.append(line)
            if let body = result.body { lines.append("     Body: \(body)") }
        }
        lines += ["", "4. Spotify app engine:"]
        lines += spotifyApp.reportLines
        lines += ["", "Event and librespot log:"]
        lines += log.map { "   \($0.text)" }
        return lines.joined(separator: "\n")
    }
}

extension LibraryResult {
    /// Seconds from the Retry-After header, read back from `body`.
    var retryAfter: Int? {
        guard let body, let range = body.range(of: "Retry-After: ") else { return nil }
        return Int(body[range.upperBound...].prefix { $0.isNumber })
    }
}
