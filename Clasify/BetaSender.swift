import ClasifyCore
import Foundation

/// CLA-97 (A3b): sends the beta events to PostHog, project "myPod", US host. Only Jason tests it:
/// it sends only with a key in the build (`PostHogKey` in Info.plist, put in by the signed
/// build) and the switch `analytics.on` on (off by default). Without them it sends nothing and
/// keeps nothing.
///
/// The events wait in `analytics.unsent` (UserDefaults, one JSON string, at most 200), written
/// at each change, so a crash loses none. They go out with the account ID once this Mac is
/// active: setup events made before that wait. Sent events go only after PostHog answers 200.
@MainActor final class BetaSender {
    static let host = URL(string: "https://us.i.posthog.com/batch/")!
    static let unsentKey = "analytics.unsent", onKey = "analytics.on"
    /// At most this many events in one request.
    static let batchSize = 50

    /// PostHog's project key. A public write key: it can only add events (abuse list in the PR).
    let key: String
    private let defaults: UserDefaults
    /// The account ID, from the activation answer. In memory only.
    private let person: () -> String?
    private var queue: BetaQueue
    private var task: Task<Void, Never>?
    /// The next try, and the failed tries in a row: 30 s, 1 min, 2 min, … at most 10 min (CTO).
    private var nextTry = Date.distantPast, failures = 0

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral  // no cache, no cookies, nothing on disk
        config.timeoutIntervalForRequest = 15
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    init(defaults: UserDefaults = .standard, bundle: Bundle = .main, person: @escaping () -> String?) {
        let key = bundle.object(forInfoDictionaryKey: "PostHogKey") as? String ?? ""
        self.key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        (self.defaults, self.person) = (defaults, person)
        queue = BetaQueue(saved: defaults.string(forKey: Self.unsentKey))
        if !on { forget() }
    }

    /// The sender takes events: a key in the build and the switch on.
    var on: Bool { !key.isEmpty && defaults.bool(forKey: Self.onKey) }

    func take(_ event: BetaEvent) {
        guard on else { return forget() }
        queue.add(event, at: Date().timeIntervalSinceReferenceDate)
        save()
        if queue.events.count >= 20 && failures == 0 { nextTry = .distantPast }
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
        guard Date() >= nextTry, !queue.events.isEmpty, let person = person() else { return }
        nextTry = .distantFuture  // one request at a time
        let batch = Array(queue.events.prefix(Self.batchSize))
        var request = URLRequest(url: Self.host)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = BetaQueue.body(batch, key: key, person: person)
        let status = (try? await Self.session.data(for: request)).flatMap { ($0.1 as? HTTPURLResponse)?.statusCode }
        if status == 200 {
            failures = 0
            queue.remove(Set(batch.map(\.id)))
            save()
            nextTry = queue.events.isEmpty ? Date() + 30 : Date()
        } else {
            failures += 1
            nextTry = Date() + min(600, 30 * pow(2, Double(failures - 1)))
        }
    }

    private func save() { defaults.set(queue.saved, forKey: Self.unsentKey) }

    /// Off: nothing waits, nothing is kept.
    private func forget() {
        if !queue.events.isEmpty { queue = BetaQueue() }
        defaults.removeObject(forKey: Self.unsentKey)
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
