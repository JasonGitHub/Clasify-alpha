import AppKit
import Observation
import WebKit

struct WebPlaylist: Identifiable, Hashable, Decodable {
    let id: String
    let name: String
}

@MainActor @Observable final class PathCModel {
    var playlists: [WebPlaylist] = []
    var status = "-"
    var hasToken = Keychain.loadToken() != nil
}

/// Path C: MusicKit JS v3 in a 1x1 WKWebView inside the spike's own window.
/// Website data is not persistent, so nothing goes to disk. You sign in again after each launch.
@MainActor final class PathC: NSObject {
    let model = PathCModel()
    let webView: WKWebView
    private var popupWindows: [NSWindow] = []
    private var poller: Timer?
    private var log: SpikeLog { SpikeLog.shared }

    override init() {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        super.init()
        config.userContentController.add(self, name: "spike")
        webView.uiDelegate = self
        webView.navigationDelegate = self
        webView.loadHTMLString(Self.page, baseURL: URL(string: "https://localhost/"))
    }

    func saveToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        model.hasToken = Keychain.saveToken(trimmed)
        log.add("C", model.hasToken ? "developer token saved in the Keychain" : "Keychain save failed")
    }

    func deleteToken() {
        Keychain.deleteToken()
        model.hasToken = false
        log.add("C", "developer token deleted from the Keychain")
    }

    func configure() async {
        guard let token = Keychain.loadToken() else {
            log.add("C", "no developer token in the Keychain")
            return
        }
        _ = await call("return await spikeConfigure(token)", ["token": token])
    }

    func authorize() async { _ = await call("return await spikeAuthorize()") }

    func loadPlaylists() async {
        guard let json = await call("return await spikePlaylists()"),
              let data = json.data(using: .utf8) else { return }
        do {
            model.playlists = try JSONDecoder().decode([WebPlaylist].self, from: data)
        } catch {
            log.add("C", "playlist decode error: \(error)")
        }
    }

    func play(_ playlist: WebPlaylist) async {
        log.add("C", "play \(playlist.name) (\(playlist.id))")
        _ = await call("return await spikePlay(id)", ["id": playlist.id])
        startPolling()
    }

    func playCatalogSong() async {
        _ = await call("return await spikeCatalog()")
        startPolling()
    }

    func togglePause() async { _ = await call("return await spikeToggle()") }
    func next() async { _ = await call("return await spikeNext()") }
    func seekForward() async { _ = await call("return await spikeSeek()") }

    private func startPolling() {
        guard poller == nil else { return }
        poller = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated {
                let path = self
                Task { @MainActor in
                    if let text = await path.call("return spikeStatus()", quiet: true) {
                        path.model.status = text
                    }
                }
            }
        }
    }

    private func call(_ body: String, _ arguments: [String: String] = [:], quiet: Bool = false) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            webView.callAsyncJavaScript(body, arguments: arguments, in: nil, in: .page) { result in
                switch result {
                case .success(let value):
                    let text = value as? String
                    continuation.resume(returning: text)
                case .failure(let error):
                    if !quiet {
                        MainActor.assumeIsolated { SpikeLog.shared.add("C", "JS error: \(error.localizedDescription)") }
                    }
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static let page = #"""
    <!doctype html>
    <html><head><meta charset="utf-8">
    <script>
    function log(m) { window.webkit.messageHandlers.spike.postMessage(String(m)); }
    window.onerror = function (m) { log('JS error: ' + m); };
    window.addEventListener('unhandledrejection', function (e) { log('JS rejection: ' + (e.reason && (e.reason.message || e.reason.errorCode || e.reason))); });

    async function checkFairPlay() {
      const configs = [{
        initDataTypes: ['skd'],
        audioCapabilities: [{ contentType: 'audio/mp4;codecs="mp4a.40.2"' }],
        videoCapabilities: [{ contentType: 'video/mp4;codecs="avc1.42E01E"' }]
      }];
      for (const ks of ['com.apple.fps', 'com.apple.fps.1_0', 'com.apple.fps.3_0']) {
        try { await navigator.requestMediaKeySystemAccess(ks, configs); log('EME ' + ks + ': supported'); }
        catch (e) { log('EME ' + ks + ': ' + e.name); }
      }
      if (typeof WebKitMediaKeys !== 'undefined') {
        log('WebKitMediaKeys fps.1_0 video/mp4: ' + WebKitMediaKeys.isTypeSupported('com.apple.fps.1_0', 'video/mp4'));
      } else {
        log('WebKitMediaKeys: undefined');
      }
    }
    checkFairPlay();

    document.addEventListener('musickitloaded', function () { log('musickit.js loaded, version ' + (MusicKit.version || '?')); });

    let music = null;
    function title() { return music && music.nowPlayingItem ? music.nowPlayingItem.title : 'none'; }

    async function spikeConfigure(token) {
      if (!window.MusicKit) {
        await new Promise(function (r) { document.addEventListener('musickitloaded', r, { once: true }); });
      }
      music = await MusicKit.configure({ developerToken: token, app: { name: 'Clasify Spike', build: '0.1' } });
      music.addEventListener('playbackStateDidChange', function () { log('state ' + MusicKit.PlaybackStates[music.playbackState] + ' at ' + Math.round(music.currentPlaybackTime) + ' s'); });
      music.addEventListener('nowPlayingItemDidChange', function () { log('track changed: ' + title()); });
      music.addEventListener('mediaPlaybackError', function (e) { log('mediaPlaybackError: ' + (e && (e.errorCode || e.message || JSON.stringify(e)))); });
      log('configured; authorized=' + music.isAuthorized + '; storefront=' + music.storefrontId);
      return 'ok';
    }
    async function spikeAuthorize() { await music.authorize(); log('authorized=' + music.isAuthorized); return 'ok'; }
    async function spikePlaylists() {
      const t0 = Date.now();
      const r = await music.api.music('/v1/me/library/playlists', { limit: 100 });
      const items = r.data.data.map(function (p) { return { id: p.id, name: p.attributes.name }; });
      log('library playlists: ' + items.length + ' in ' + (Date.now() - t0) + ' ms');
      return JSON.stringify(items);
    }
    async function spikePlay(id) {
      const t0 = Date.now();
      await music.setQueue({ playlist: id, startPlaying: true });
      log('setQueue(playlist) returned in ' + (Date.now() - t0) + ' ms');
      return 'ok';
    }
    async function spikeCatalog() {
      const r = await music.api.music('/v1/catalog/{{storefrontId}}/search', { term: 'Daft Punk', types: 'songs', limit: 1 });
      const song = r.data.results.songs.data[0];
      log('catalog song: ' + song.attributes.name);
      await music.setQueue({ song: song.id, startPlaying: true });
      return 'ok';
    }
    async function spikeToggle() { if (music.isPlaying) { music.pause(); } else { await music.play(); } return 'ok'; }
    async function spikeNext() { await music.skipToNextItem(); return 'ok'; }
    async function spikeSeek() { await music.seekToTime(music.currentPlaybackTime + 30); return 'ok'; }
    function spikeStatus() {
      if (!music) { return 'not configured'; }
      return MusicKit.PlaybackStates[music.playbackState] + ', ' + Math.round(music.currentPlaybackTime) + ' s, ' + title();
    }
    </script>
    <script src="https://js-cdn.music.apple.com/musickit/v3/musickit.js" async></script>
    </head><body></body></html>
    """#
}

extension PathC: WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        log.add("C", "\(message.body)")
    }
}

extension PathC: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === self.webView { log.add("C", "page loaded") }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        log.add("C", "page load error: \(error.localizedDescription)")
    }
}

extension PathC: WKUIDelegate {
    /// MusicKit JS signs in with a popup. The spike shows it in its own window.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let popup = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 640), configuration: configuration)
        popup.uiDelegate = self
        let window = NSWindow(contentRect: popup.frame, styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Apple Music sign-in (spike window)"
        window.contentView = popup
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        popupWindows.append(window)
        log.add("C", "sign-in popup opened: \(navigationAction.request.url?.host ?? "?")")
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        for window in popupWindows where window.contentView === webView { window.close() }
        popupWindows.removeAll { $0.contentView === webView }
        log.add("C", "sign-in popup closed")
    }
}
