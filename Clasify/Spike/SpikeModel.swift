import AppKit
import Foundation
import LibrespotBridge
import Observation

struct LogLine: Identifiable {
    let id: Int
    var text: String
}

/// State and steps of the spike window: OAuth login, library reads through librespot,
/// and the Spotify app driven by Spotify Connect commands.
/// The access token lives only in memory, in `token`. It is never shown, logged or copied.
@MainActor
@Observable
final class SpikeModel {
    static let build = 10

    private(set) var oauth: OAuthResult?
    private(set) var oauthStatus = "Not run"
    private(set) var isLoggingIn = false
    private var token: String?

    private(set) var bridgeStatus = "Not run"
    private(set) var isBridgeLoggedIn = false
    private(set) var log: [LogLine] = []

    private(set) var librespotLibrary: [String] = []
    /// Track URIs of contexts read through librespot, by context URI.
    private(set) var contexts: [String: [String]] = [:]
    private(set) var firstPlaylistURI: String?
    private(set) var likedContextURI: String?
    /// The Spotify app driven only by Connect commands.
    let connect = ConnectProbe()

    @ObservationIgnored private var bridge: Bridge?
    @ObservationIgnored private var afterLogin: [(Bridge) -> Void] = []
    @ObservationIgnored private var start = Date()
    @ObservationIgnored private var nextID = 0

    var hasToken: Bool { token != nil }

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
            bridge = Bridge(onEvent: Self.onMain { [self] event in receive(event) })
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
            append("lsb_login -> \(bridge.login(accessToken: token))")
        }
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
        case LSB_EVENT_LIBRARY:
            librespotLibrary.append(event.message ?? "")
            if let uri = event.trackURI, uri.hasPrefix("spotify:playlist:") {
                firstPlaylistURI = uri
                if let bridge { append("lsb_read_context \(uri) -> \(bridge.readContext(uri))") }
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
        case LSB_EVENT_CONNECT:
            connect.connectResult(path: event.trackURI ?? "", message: event.message ?? "")
        case LSB_EVENT_CLUSTER:
            // Cluster updates are frequent. The Connect probe keeps its own log.
            connect.cluster(event.message ?? "")
            return
        case LSB_EVENT_LOG:
            // librespot's own log is noisy and was only needed for the playback tests.
            return
        default:
            break
        }
        var text = event.name
        if let uri = event.trackURI { text += " \(uri)" }
        if let message = event.message { text += " \"\(message)\"" }
        append(text)
    }

    /// Milliseconds since the window opened, so all lines share one clock.
    private var elapsedMs: Int { Int(Date().timeIntervalSince(start) * 1000) }

    private func append(_ text: String) {
        log.append(LogLine(id: nextID, text: "+\(elapsedMs) ms \(text)"))
        nextID += 1
        if log.count > 300 { log.removeFirst(log.count - 300) }
    }

    // MARK: Step 2, library through librespot

    func readLibraryWithLibrespot() {
        librespotLibrary = []
        withBridge { [self] bridge in
            append("lsb_read_library -> \(bridge.readLibrary())")
        }
    }

    // MARK: Spotify Connect through the bridge

    func connectDevices() {
        withBridge { [self] bridge in append("lsb_connect_devices -> \(bridge.connectDevices())") }
    }

    func connectRequest(_ method: String, _ path: String, body: String?) {
        withBridge { [self] bridge in
            append("lsb_connect_request \(method) \(path) -> \(bridge.connectRequest(method, path, body: body))")
        }
    }

    // MARK: Report

    func copyReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }

    /// Plain text for Jason to paste back. It has no token.
    var report: String {
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        var lines = [
            "Clasify spike report, build \(Self.build)",
            "App commit: \(BuildInfo.commit)",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString), \(arch)",
            "librespot: 0.8.0",
            "",
            "1. OAuth login: \(oauthStatus)",
        ]
        if let oauth {
            lines += [
                "   Client ID: \(oauth.clientID)",
                "   Scopes: \(oauth.scopes.joined(separator: " "))",
                "   Refresh token returned: \(oauth.hasRefreshToken ? "yes" : "no")",
                "   Expires in: \(oauth.expiresInSeconds) s",
            ]
        }
        lines += ["", "2. Library through librespot:", "   Bridge login: \(bridgeStatus)"]
        lines += librespotLibrary.isEmpty ? ["   Not run"] : librespotLibrary.map { "   \($0)" }
        lines += ["", "3. Spotify app through Connect commands:"]
        lines += connect.reportLines
        lines += ["", "Event log:"]
        lines += log.map { "   \($0.text)" }
        return lines.joined(separator: "\n")
    }
}
