import AppKit
import ClasifyCore
import Foundation

/// CLA-97 (A3b): sends the beta events to PostHog, project "myPod", US host. It sends only with
/// a key in the build (`PostHogKey` in Info.plist, put in by the signed build) and the switch
/// `analytics.on` on. The switch is on when it is not set (Jason 20:31 JST 11-20: on for
/// everyone); `defaults write com.cappyai.mypod analytics.on -bool false` turns it off. Without
/// a key, or with the switch off, it sends nothing and keeps nothing.
///
/// The events wait in `analytics.unsent` (UserDefaults, one JSON string, at most 200), written
/// at each change, so a crash loses none. They go out with the account ID once this Mac is
/// active. Before that they go out at once as `analytics.installID`: a random UUID made at the
/// first start with analytics on, for analytics only (never the activation device ID, never
/// sent to our server). The first batch with the account ID links the two with `$identify`
/// (Jason "ok 1" 21:00 JST 11-20); `analytics.linked` holds the install ID it linked. A reinstall or `defaults
/// delete` makes a new install ID. Sent events go only after PostHog answers 200.
@MainActor final class BetaSender {
    static let host = URL(string: "https://us.i.posthog.com/batch/")!
    static let unsentKey = "analytics.unsent", onKey = "analytics.on"
    static let installKey = "analytics.installID", linkedKey = "analytics.linked"
    /// At most this many events in one request.
    static let batchSize = 50

    /// PostHog's project key. A public write key: it can only add events (abuse list in the PR).
    let key: String
    /// CLA-194: this app's build number (CFBundleVersion), put in each event as `app_build`.
    let build: Int?
    private let defaults: UserDefaults
    /// The account ID, from the activation answer. In memory only.
    private let person: () -> String?
    private var queue: BetaQueue
    private var task: Task<Void, Never>?
    /// The next try, and the failed tries in a row: 30 s, 1 min, 2 min, … at most 10 min (CTO).
    private var nextTry = Date.distantPast, failures = 0
    /// The events of the batch that PostHog refused (400) once (CTO 00:25 JST 11-20). Its retry
    /// sends these same events, so a second refusal drops only them, not events added since.
    private var refused: Set<String> = []

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral  // no cache, no cookies, nothing on disk
        config.timeoutIntervalForRequest = 15
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    init(defaults: UserDefaults = .standard, bundle: Bundle = .main, person: @escaping () -> String?) {
        let key = bundle.object(forInfoDictionaryKey: "PostHogKey") as? String ?? ""
        self.key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        build = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String).flatMap { Int($0) }
        (self.defaults, self.person) = (defaults, person)
        queue = BetaQueue(saved: defaults.string(forKey: Self.unsentKey))
        if !on { forget() } else { makeInstallID() }
    }

    /// At the first start with analytics on, and again when the switch comes back on while the
    /// app runs (Codex on #369): `forget()` removed the old one.
    private func makeInstallID() {
        if defaults.string(forKey: Self.installKey) == nil { defaults.set(UUID().uuidString, forKey: Self.installKey) }
    }

    private var install: String? { defaults.string(forKey: Self.installKey) }

    /// The sender takes events: a key in the build and the switch on.
    var on: Bool { !key.isEmpty && Self.switchOn(defaults) }

    /// The switch `analytics.on`: on when it is not set.
    static func switchOn(_ defaults: UserDefaults) -> Bool { defaults.object(forKey: onKey) as? Bool ?? true }

    func take(_ event: BetaEvent) {
        guard on else { return forget() }
        makeInstallID()
        queue.add(event, at: Date().timeIntervalSinceReferenceDate, build: build, os: Self.os, spotifyApp: Self.spotifyApp())
        save()
        if queue.events.count >= 20 && failures == 0 { nextTry = .distantPast }
    }

    /// CLA-203: the macOS version, as "15.8.1", on every event.
    static let os: String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }()

    /// CLA-203: the installed Spotify app's version, as `spotify_version` on every event; nil when it is not installed.
    /// Read from its Info.plist each time (no cache), so an update in this launch shows.
    static func spotifyApp() -> String? {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client"),
              let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) else { return nil }
        return info["CFBundleShortVersionString"] as? String
    }

    /// Starts the send loop. It looks once a second and sends when a try is due.
    func start() {
        guard task == nil else { return }
        nextTry = Date()  // the events from the last run go out at once
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                await self.sendIfDue()
            }
        }
    }

    private func sendIfDue() async {
        guard on else { return forget() }
        let account = person(), install = self.install
        guard Date() >= nextTry, !queue.events.isEmpty, let person = BetaQueue.person(account: account, install: install) else { return }
        // The link is for this install ID: a new one (after off and on) links again (Codex on #369).
        let linking = BetaQueue.linking(account: account, install: install, linked: install != nil && defaults.string(forKey: Self.linkedKey) == install)
        nextTry = .distantFuture  // one request at a time
        var batch = queue.events.filter { refused.contains($0.id) }  // the queue may have dropped some
        if batch.isEmpty { (refused, batch) = ([], Array(queue.events.prefix(Self.batchSize))) }
        var request = URLRequest(url: Self.host)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = BetaQueue.body(batch, key: key, person: person, linking: linking)
        let status = (try? await Self.session.data(for: request)).flatMap { ($0.1 as? HTTPURLResponse)?.statusCode }
        if status == 200 || (status == 400 && !refused.isEmpty) {
            // A batch that PostHog refuses twice goes: it can never be sent (CTO 00:25 JST).
            (failures, refused) = (0, [])
            if let linking, status == 200, on { defaults.set(linking, forKey: Self.linkedKey) }
            queue.remove(Set(batch.map(\.id)))
            save()
            nextTry = queue.events.isEmpty ? Date() + 30 : Date()
        } else if status == 400 {
            refused = Set(batch.map(\.id))
            nextTry = Date() + 30
        } else {  // no network, a timeout or a 5xx: keep and wait longer
            failures += 1
            nextTry = Date() + min(600, 30 * pow(2, Double(failures - 1)))
        }
    }

    /// CLA-182: events wait to go out.
    var waiting: Bool { on && !queue.events.isEmpty }

    /// CLA-182: at a quit, one try to send what waits, for at most `seconds`. What does not go
    /// out in time stays in `analytics.unsent` for the next start, as before.
    func flush(within seconds: Double) async {
        guard waiting else { return }
        let deadline = Date() + seconds
        while nextTry == .distantFuture, Date() < deadline {  // a request already runs: wait for it
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard waiting, Date() < deadline else { return }
        nextTry = .distantPast  // at the quit, no wait from earlier failures
        let left = deadline.timeIntervalSinceNow
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.sendIfDue() }
            group.addTask { try? await Task.sleep(for: .seconds(left)) }
            await group.next()
            group.cancelAll()  // a request still running stops; its events stay
        }
    }

    private func save() { defaults.set(queue.saved, forKey: Self.unsentKey) }

    /// Off: nothing waits, nothing is kept, the install ID too.
    private func forget() {
        if !queue.events.isEmpty { queue = BetaQueue() }
        for key in [Self.unsentKey, Self.installKey, Self.linkedKey] { defaults.removeObject(forKey: key) }
    }
}

extension BetaSender {
    /// Ms from this process's start to now, for `app_speed` (`Action.appStarted`). Nil when the
    /// system does not say.
    static func msSinceProcessStart() -> Int? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        let started = Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000
        guard started > 0 else { return nil }
        return max(0, Int(((Date().timeIntervalSince1970 - started) * 1000).rounded()))
    }
}
