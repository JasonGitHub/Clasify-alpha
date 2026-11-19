import Foundation

/// CLA-97: one event that waits for PostHog. `id` is PostHog's `uuid`, so an event sent twice
/// (the answer was lost) counts once. No account ID, token or email: the ID goes in at send time.
public struct QueuedEvent: Codable, Equatable, Sendable {
    public var id: String, name: String
    /// As `Dependencies.now`: seconds since 2001-01-01 UTC.
    public var time: Double
    public var properties: [String: BetaValue]

    public init(_ event: BetaEvent, at time: Double, id: String = UUID().uuidString) {
        (self.id, self.name, self.time, self.properties) = (id, event.name, time, event.properties)
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

    public mutating func add(_ event: BetaEvent, at time: Double) { add(QueuedEvent(event, at: time)) }
    public mutating func add(_ event: QueuedEvent) {
        events.append(event)
        if events.count > Self.limit { events.removeFirst(events.count - Self.limit) }
    }

    /// The sent events go only after PostHog answered 200. By ID, as new events can come and
    /// old ones go while a send runs.
    public mutating func remove(_ ids: Set<String>) { events.removeAll { ids.contains($0.id) } }

    /// The body of a POST to PostHog's `/batch/`. `person` is the account ID (`distinct_id`).
    public static func body(_ events: [QueuedEvent], key: String, person: String) -> Data {
        let time = ISO8601DateFormatter()
        time.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let batch = events.map { e in
            var properties = e.properties
            properties["distinct_id"] = .text(person)
            return Item(event: e.name, uuid: e.id, timestamp: time.string(from: Date(timeIntervalSinceReferenceDate: e.time)), properties: properties)
        }
        return (try? JSONEncoder().encode(Body(api_key: key, batch: batch))) ?? Data()
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
