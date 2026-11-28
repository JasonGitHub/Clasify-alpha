import Foundation

/// CLA-97: one event that waits for PostHog. `id` is PostHog's `uuid`, so an event sent twice
/// (the answer was lost) counts once. No account ID, token or email: the ID goes in at send time.
public struct QueuedEvent: Codable, Equatable, Sendable {
    public var id: String, name: String
    /// As `Dependencies.now`: seconds since 2001-01-01 UTC.
    public var time: Double
    public var properties: [String: BetaValue]

    /// CLA-194: `build` (CFBundleVersion of the app that made the event) goes in as `app_build`,
    /// a number, when the event is made, so an event that waits across an update keeps the build
    /// that made it. An event that has its own `app_build` (`app_problem`: the build that
    /// crashed, from MetricKit) keeps it; one that has none gets no stamp, because the running
    /// build may not be the one that crashed.
    ///
    /// CLA-203: `os` (the macOS version, as "15.8.1") goes in as `os_version`, and `spotifyApp`
    /// (the Spotify app's version) as `spotify_app`, each when known. `app_problem` keeps its
    /// own `os_version`, the one that MetricKit names for the crash, and `music_pick` its own
    /// `spotify_app` (whether the app was found).
    public init(_ event: BetaEvent, at time: Double, build: Int? = nil, os: String? = nil, spotifyApp: String? = nil,
                id: String = UUID().uuidString) {
        (self.id, self.name, self.time, self.properties) = (id, event.name, time, event.properties)
        if let os, properties["os_version"] == nil { properties["os_version"] = .text(os) }
        if let spotifyApp, properties["spotify_app"] == nil { properties["spotify_app"] = .text(spotifyApp) }
        if case .appProblem = event { return }
        if let build, properties["app_build"] == nil { properties["app_build"] = .number(build) }
    }
}

/// CLA-97: the events that wait for PostHog, oldest first. The app keeps them in UserDefaults
/// (`analytics.unsent`, one JSON string) at each change, so a crash loses none.
public struct BetaQueue: Equatable, Sendable {
    /// At most 200 wait; the oldest goes first (Jason OK 22:44 JST).
    public static let limit = 200
    public private(set) var events: [QueuedEvent] = []

    public init() {}
    /// From the saved string. A string that does not read gives an empty queue.
    public init(saved: String?) {
        guard let data = saved?.data(using: .utf8), let events = try? JSONDecoder().decode([QueuedEvent].self, from: data) else { return }
        self.events = Array(events.suffix(Self.limit))
    }

    public var saved: String {
        guard let data = try? JSONEncoder().encode(events) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    public mutating func add(_ event: BetaEvent, at time: Double, build: Int? = nil, os: String? = nil, spotifyApp: String? = nil) {
        add(QueuedEvent(event, at: time, build: build, os: os, spotifyApp: spotifyApp))
    }
    public mutating func add(_ event: QueuedEvent) {
        events.append(event)
        if events.count > Self.limit { events.removeFirst(events.count - Self.limit) }
    }

    /// The sent events go only after PostHog answered 200. By ID, as new events can come and
    /// old ones go while a send runs.
    public mutating func remove(_ ids: Set<String>) { events.removeAll { ids.contains($0.id) } }

    /// The body of a POST to PostHog's `/batch/`. `person` is the `distinct_id`: the account ID,
    /// or before activation the install ID (CLA-97, Jason "ok 1" 21:00 JST 11-20). With `linking`
    /// (the install ID), a `$identify` goes first: PostHog then merges the install ID's earlier
    /// events into the account's person.
    public static func body(_ events: [QueuedEvent], key: String, person: String, linking anon: String? = nil, linkID: String = UUID().uuidString) -> Data {
        let time = ISO8601DateFormatter()
        time.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var batch = events.map { e in
            var properties = e.properties
            properties["distinct_id"] = .text(person)
            return Item(event: e.name, uuid: e.id, timestamp: time.string(from: Date(timeIntervalSinceReferenceDate: e.time)), properties: properties)
        }
        if let anon, anon != person, let first = events.first {
            let link = Item(event: "$identify", uuid: linkID, timestamp: time.string(from: Date(timeIntervalSinceReferenceDate: first.time)),
                            properties: ["distinct_id": .text(person), "$anon_distinct_id": .text(anon)])
            batch.insert(link, at: 0)
        }
        return (try? JSONEncoder().encode(Body(api_key: key, batch: batch))) ?? Data()
    }

    /// Who the events go out as: the account ID once this Mac has one, before that the random
    /// install ID. Nil with neither: the events wait.
    public static func person(account: String?, install: String?) -> String? { account ?? install }

    /// The install ID to link to the account, once: when an account ID is there and the link has
    /// not gone out yet.
    public static func linking(account: String?, install: String?, linked: Bool) -> String? {
        guard account != nil, !linked else { return nil }
        return install
    }

    private struct Body: Encodable { var api_key: String, batch: [Item] }
    private struct Item: Encodable { var event: String, uuid: String, timestamp: String, properties: [String: BetaValue] }
}

/// As plain JSON values: text, whole number, true or false, decimal. JSONEncoder writes a whole
/// decimal (1200.0) as 1200, so after a save it reads back as `.number`: PostHog sees the same
/// number, so nothing is lost (CTO 23:53 JST).
extension BetaValue: Codable {
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .text(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .flag(let v): try c.encode(v)
        case .decimal(let v): try c.encode(v)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self) { self = .flag(v) }
        else if let v = try? c.decode(Int.self) { self = .number(v) }
        else if let v = try? c.decode(Double.self) { self = .decimal(v) }
        else { self = .text(try c.decode(String.self)) }
    }
}
