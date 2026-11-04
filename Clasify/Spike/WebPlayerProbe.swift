import AppKit
import Darwin
import Foundation
import Observation
import WebKit

/// Build 7. Two tests, spike only:
/// A. The Web Playback SDK in a web view that is never shown.
/// B. Starting playback on the Spotify app with a Spotify Connect command, not AppleScript,
///    while the Spotify window is checked every 50 ms.
@MainActor
@Observable
final class WebPlayerProbe {
    private(set) var results: [SpotifyAppProbe.ResultLine] = []
    private(set) var sdkDeviceID: String?
    private(set) var isLoaded = false

    @ObservationIgnored private var log: [String] = []
    @ObservationIgnored private weak var model: SpikeModel?
    @ObservationIgnored private var webView: WKWebView?
    @ObservationIgnored private var hiddenWindow: NSWindow?
    @ObservationIgnored private var handler: WebMessageHandler?
    @ObservationIgnored private var createdAt = Date()
    @ObservationIgnored private var start = Date()
    @ObservationIgnored private var devices: [ConnectDevice] = []
    @ObservationIgnored private var pendingAppPlay: (context: String, name: String)?
    @ObservationIgnored private var pendingSDKPlay: String?
    @ObservationIgnored private var positionEvents = 0

    struct ConnectDevice {
        let id: String
        let name: String
        let type: String
        let software: String
        let active: Bool
    }

    private func set(_ name: String, _ value: String) {
        if let index = results.firstIndex(where: { $0.name == name }) {
            results[index].value = value
        } else {
            results.append(SpotifyAppProbe.ResultLine(name: name, value: value))
        }
        append("RESULT \(name): \(value)")
    }

    private var elapsedMs: Int { Int(Date().timeIntervalSince(start) * 1000) }

    private func append(_ text: String) {
        log.append("+\(elapsedMs) ms \(text)")
        if log.count > 300 { log.removeFirst(log.count - 300) }
    }

    /// Hides the token and any line that may hold a credential.
    private func scrub(_ text: String) -> String {
        var text = text
        if let token = model?.accessToken, !token.isEmpty {
            text = text.replacingOccurrences(of: token, with: "[token]")
        }
        let lower = text.lowercased()
        if ["bearer ", "access_token", "authorization"].contains(where: { lower.contains($0) }) {
            return String(text.prefix(40)) + " [hidden: may hold a credential]"
        }
        return text.count > 400 ? String(text.prefix(400)) + "..." : text
    }

    // MARK: A. Web Playback SDK

    func loadSDK(model: SpikeModel) {
        self.model = model
        guard model.accessToken != nil else {
            set("SDK", "no token. Run step 1 first.")
            return
        }
        guard webView == nil else { return }
        createdAt = Date()
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let handler = WebMessageHandler { [weak self] type, data in self?.received(type: type, data: data) }
        configuration.userContentController.add(handler, name: "clasify")
        self.handler = handler
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 320, height: 240), configuration: configuration)
        // A window that is never ordered on screen, so WebKit treats the view as attached.
        let window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 320, height: 240),
            styleMask: [.borderless], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        window.contentView = webView
        hiddenWindow = window
        self.webView = webView
        // http://127.0.0.1 is a secure context, which EME needs. Nothing is fetched from it.
        webView.loadHTMLString(Self.page, baseURL: URL(string: "http://127.0.0.1/"))
        set("SDK", "loading https://sdk.scdn.co/spotify-player.js")
    }

    private func received(type: String, data: String) {
        switch type {
        case "token_request":
            // The token goes to the page as a call argument, never in a URL, the source or a log.
            guard let token = model?.accessToken else { return }
            webView?.callAsyncJavaScript(
                "window.__deliverToken(t)", arguments: ["t": token], in: nil, in: .page, completionHandler: nil
            )
            append("token handed to getOAuthToken")
        case "ready":
            sdkDeviceID = Self.field("device_id", in: data)
            set("SDK ready", "device_id \(sdkDeviceID ?? "?") after \(Int(Date().timeIntervalSince(createdAt) * 1000)) ms")
            visibility("Visible after SDK ready")
        case "not_ready", "initialization_error", "authentication_error", "account_error", "playback_error",
             "connect", "env", "script_error", "sdk_loaded":
            set("SDK \(type)", scrub(data))
        case "drm":
            let system = Self.field("ks", in: data) ?? "?"
            set("DRM \(system)", scrub(data))
        case "drm_used":
            set("DRM requested by the SDK", scrub(data))
        case "state":
            append("STATE \(scrub(data))")
            if data.contains("\"paused\":false") { set("SDK playing", scrub(data)) }
        case "position":
            positionEvents += 1
            if positionEvents % 5 == 1 { append("POSITION \(scrub(data))") }
            set("SDK position polls", "\(positionEvents), last \(scrub(data))")
        default:
            append("\(type.uppercased()) \(scrub(data))")
        }
    }

    private static func field(_ name: String, in json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object[name].map { "\($0)" }
    }

    /// Transfers the current playback to the SDK device (connect-state transfer).
    func transferToSDK() {
        guard let id = sdkDeviceID else { return set("Transfer to SDK", "SDK not ready") }
        append("transfer to \(id)")
        model?.connectPost(
            "/connect-state/v1/connect/transfer/from/\(id)/to/\(id)",
            body: #"{"transfer_options":{"restore_paused":"resume"}}"#
        )
    }

    /// Sends a play command with a playlist context to the SDK device.
    func playOnSDK() {
        guard let id = sdkDeviceID else { return set("Play on SDK", "SDK not ready") }
        guard let context = model?.firstPlaylistURI else { return set("Play on SDK", "no playlist. Run 3a first.") }
        // The sender must be a registered Connect device, so register this session first.
        // connectResult sends the command when the device list comes back.
        pendingAppPlay = nil
        pendingSDKPlay = context
        model?.connectDevices()
    }

    /// The Web API route. It is quota-blocked for this client ID, but the status is useful.
    func playOnSDKWithWebAPI() async {
        guard let id = sdkDeviceID, let token = model?.accessToken, let context = model?.firstPlaylistURI else {
            return set("Web API PUT /me/player/play", "needs SDK ready, step 1 and 3a")
        }
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/play?device_id=\(id)")!)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["context_uri": context])
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let retry = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After") ?? "none"
            let body = String(decoding: data.prefix(300), as: UTF8.self)
            set("Web API PUT /me/player/play", "status \(status), Retry-After \(retry), body \(scrub(body))")
        } catch {
            set("Web API PUT /me/player/play", "error \(error.localizedDescription)")
        }
    }

    func heard(_ answer: String) { set("SDK heard audio", answer) }

    func memory() {
        var own = Self.usage(of: getpid())
        var count = 0
        let since = Int(createdAt.timeIntervalSince1970) - 2
        for pid in Self.allPIDs() where Self.path(of: pid).contains("com.apple.WebKit") && Self.startTime(of: pid) >= since {
            let usage = Self.usage(of: pid)
            own.resident += usage.resident
            own.footprint += usage.footprint
            count += 1
        }
        set("Memory Clasify plus \(count) WebKit processes",
            "RSS \(own.resident / 1_048_576) MB, footprint \(own.footprint / 1_048_576) MB")
    }

    // MARK: B. Spotify app through a Connect command

    func playOnSpotifyApp(model: SpikeModel, liked: Bool) {
        self.model = model
        guard let context = liked ? model.likedContextURI : model.firstPlaylistURI else {
            return set("Connect play", "no context. Run 1 and 3a first.")
        }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: SpotifyAppProbe.bundleID).first != nil else {
            return set("Connect play", "Spotify is not running. Start it, or use Connect to Spotify app.")
        }
        pendingAppPlay = (context, liked ? "Liked Songs" : "Playlist")
        model.connectDevices()
    }

    func connectResult(path: String, message: String) {
        if path == "devices" {
            guard !message.hasPrefix("ERROR") else {
                set("Connect devices", message)
                pendingAppPlay = nil
                pendingSDKPlay = nil
                return
            }
            devices = message.split(separator: "\n").compactMap { line in
                let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                guard parts.count == 5 else { return nil }
                return ConnectDevice(id: parts[0], name: parts[1], type: parts[2], software: parts[3], active: parts[4] == "true")
            }
            set("Connect devices", devices.map { "\($0.name) (\($0.type), \($0.software)\($0.active ? ", active" : ""))" }
                .joined(separator: "; "))
            if let context = pendingSDKPlay, let id = sdkDeviceID {
                pendingSDKPlay = nil
                model?.connectPost("/connect-state/v1/player/command/from/{self}/to/\(id)", body: Self.playCommand(context))
            }
            if let pending = pendingAppPlay {
                pendingAppPlay = nil
                Task { await sendAppPlay(context: pending.context, name: pending.name) }
            }
            return
        }
        set("Connect POST \(path.components(separatedBy: "/").prefix(6).joined(separator: "/"))", scrub(message))
    }

    /// The Spotify app's device: a computer that is not this session and not the SDK.
    private var appDevice: ConnectDevice? {
        let others = devices.filter { $0.name != "Clasify spike" && $0.id != sdkDeviceID }
        return others.first { $0.type == "COMPUTER" && $0.software.lowercased().contains("osx") }
            ?? others.first { $0.type == "COMPUTER" }
    }

    private func sendAppPlay(context: String, name: String) async {
        guard let device = appDevice,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: SpotifyAppProbe.bundleID).first
        else {
            return set("Connect play \(name)", "no Spotify app device in the Connect list")
        }
        let before = Self.readSpotify()
        let windowsBefore = Self.onScreenWindows(of: app)
        let activeBefore = app.isActive
        model?.connectPost("/connect-state/v1/player/command/from/{self}/to/\(device.id)", body: Self.playCommand(context))
        let sentAt = Date()
        // Poll the window every 50 ms for 2 s.
        var maxWindows = windowsBefore
        var everActive = activeBefore
        var everUnhidden = !app.isHidden
        var firstChangeMs: Int?
        var playingAtMs: Int?
        for step in 0..<40 {
            try? await Task.sleep(for: .milliseconds(50))
            let windows = Self.onScreenWindows(of: app)
            if windows > maxWindows || (app.isActive && !activeBefore), firstChangeMs == nil {
                firstChangeMs = Int(Date().timeIntervalSince(sentAt) * 1000)
            }
            maxWindows = max(maxWindows, windows)
            everActive = everActive || app.isActive
            everUnhidden = everUnhidden || !app.isHidden
            if playingAtMs == nil, step % 4 == 3, let now = Self.readSpotify(),
               now.state == "playing", now.track != before?.track {
                playingAtMs = Int(Date().timeIntervalSince(sentAt) * 1000)
            }
        }
        let after = Self.readSpotify()
        let inContext = after.map { model?.contexts[context]?.contains($0.track) ?? false } ?? false
        set("Connect play \(name) to \(device.name)",
            "playing: \(playingAtMs.map { "yes after about \($0) ms" } ?? "no change seen (state \(after?.state ?? "?"))"), "
                + "track in context: \(inContext)")
        set("Connect play \(name): window check (50 ms for 2 s)",
            "windows before \(windowsBefore), max \(maxWindows); active before \(activeBefore), ever active \(everActive); "
                + "ever unhidden \(everUnhidden); first change \(firstChangeMs.map { "at \($0) ms" } ?? "none")")
    }

    private static func playCommand(_ context: String) -> String {
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return """
        {"command":{"context":{"uri":"\(context)","url":"context://\(context)","metadata":{}},\
        "play_origin":{"feature_identifier":"harmony","feature_version":"4.11.0"},\
        "options":{"license":"on-demand","skip_to":{},"player_options_override":{}},\
        "logging_params":{"command_id":"\(id)"},"endpoint":"play"}}
        """
    }

    /// Reads the Spotify app state with AppleScript. A read does not activate Spotify.
    private static func readSpotify() -> (state: String, track: String)? {
        var error: NSDictionary?
        let source = """
        tell application "Spotify"
            set s to (player state as string)
            try
                set t to (id of current track)
            on error
                set t to ""
            end try
            return s & "|" & t
        end tell
        """
        guard let value = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue, error == nil else {
            return nil
        }
        let parts = value.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }

    private static func onScreenWindows(of app: NSRunningApplication) -> Int {
        (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? [])
            .filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier }
            .filter { ($0[kCGWindowLayer as String] as? Int) == 0 }
            .count
    }

    private func visibility(_ name: String) {
        let shown = NSApp.windows.filter { $0.isVisible }.count
        set(name, "hidden SDK window visible \(hiddenWindow?.isVisible ?? false), Clasify windows on screen \(shown)")
    }

    // MARK: Process helpers

    nonisolated private static func allPIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return Array(pids.prefix(Int(max(filled, 0)))).filter { $0 > 0 }
    }

    nonisolated private static func path(of pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return "" }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    nonisolated private static func startTime(of pid: pid_t) -> Int {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return 0 }
        return Int(info.pbi_start_tvsec)
    }

    nonisolated private static func usage(of pid: pid_t) -> (resident: UInt64, footprint: UInt64) {
        var info = rusage_info_v2()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
            }
        }
        guard status == 0 else { return (0, 0) }
        return (info.ri_resident_size, info.ri_phys_footprint)
    }

    // MARK: Report

    var reportLines: [String] {
        if results.isEmpty { return ["   Not run"] }
        return results.map { "   \($0.name): \($0.value)" } + ["   Log:"] + log.map { "     \($0)" }
    }

    // MARK: Page

    private static let page = """
    <!doctype html>
    <html><head><meta charset="utf-8"></head><body>
    <script>
    const post = (type, data) => {
      try { window.webkit.messageHandlers.clasify.postMessage({ type, data: JSON.stringify(data ?? null) }); } catch (e) {}
    };
    for (const level of ['log', 'warn', 'error']) {
      const original = console[level];
      console[level] = (...args) => {
        post('console_' + level, args.map(a => { try { return typeof a === 'string' ? a : JSON.stringify(a); } catch (e) { return String(a); } }).join(' '));
        original.apply(console, args);
      };
    }
    window.addEventListener('error', e => post('page_error', { message: e.message, source: e.filename }));
    window.addEventListener('unhandledrejection', e => post('page_rejection', { reason: String(e.reason) }));
    post('env', { secure: window.isSecureContext, eme: !!navigator.requestMediaKeySystemAccess,
                  mse: !!window.MediaSource, mms: !!window.ManagedMediaSource, webkitKeys: !!window.WebKitMediaKeys,
                  ua: navigator.userAgent });

    // Which key system does the SDK ask for, and does it get one?
    if (navigator.requestMediaKeySystemAccess) {
      const original = navigator.requestMediaKeySystemAccess.bind(navigator);
      navigator.requestMediaKeySystemAccess = (ks, configs) => original(ks, configs).then(
        access => { post('drm_used', { ks, ok: true }); return access; },
        error => { post('drm_used', { ks, ok: false, error: error.name + ': ' + error.message }); throw error; });
      const config = [{ initDataTypes: ['cenc', 'sinf', 'skd'],
                        audioCapabilities: [{ contentType: 'audio/mp4; codecs="mp4a.40.2"' }] }];
      for (const ks of ['com.apple.fps', 'com.apple.fps.1_0', 'com.widevine.alpha', 'org.w3.clearkey']) {
        original(ks, config).then(() => post('drm', { ks, ok: true }),
                                  e => post('drm', { ks, ok: false, error: e.name + ': ' + e.message }));
      }
    }

    window.__tokenCallbacks = [];
    window.__deliverToken = t => { const callbacks = window.__tokenCallbacks; window.__tokenCallbacks = []; callbacks.forEach(cb => cb(t)); };

    window.onSpotifyWebPlaybackSDKReady = () => {
      post('sdk_loaded', {});
      const player = new Spotify.Player({
        name: 'Clasify spike web player',
        getOAuthToken: cb => { window.__tokenCallbacks.push(cb); post('token_request', {}); },
        volume: 0.5
      });
      window.__player = player;
      for (const name of ['ready', 'not_ready']) player.addListener(name, ({ device_id }) => post(name, { device_id }));
      for (const name of ['initialization_error', 'authentication_error', 'account_error', 'playback_error'])
        player.addListener(name, ({ message }) => post(name, { message }));
      player.addListener('player_state_changed', s => post('state', s ? { paused: s.paused, position: s.position,
        duration: s.duration, track: s.track_window && s.track_window.current_track && s.track_window.current_track.uri,
        context: s.context && s.context.uri } : null));
      player.connect().then(ok => post('connect', { ok }));
      setInterval(() => player.getCurrentState().then(s => {
        if (s && !s.paused) post('position', { position: s.position, duration: s.duration });
      }), 1000);
    };

    const script = document.createElement('script');
    script.src = 'https://sdk.scdn.co/spotify-player.js';
    script.onerror = () => post('script_error', { src: script.src });
    document.head.appendChild(script);
    </script>
    </body></html>
    """
}

/// Receives the page's messages. WebKit calls it on the main thread.
@MainActor
private final class WebMessageHandler: NSObject, WKScriptMessageHandler {
    private let onMessage: (String, String) -> Void

    init(onMessage: @escaping (String, String) -> Void) {
        self.onMessage = onMessage
    }

    nonisolated func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        MainActor.assumeIsolated {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            onMessage(type, body["data"] as? String ?? "")
        }
    }
}
