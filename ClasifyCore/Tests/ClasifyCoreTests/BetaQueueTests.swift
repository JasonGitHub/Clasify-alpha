import Foundation
import Testing
@testable import ClasifyCore

/// CLA-97, A3a: the events that wait for PostHog, and the body that sends them.
@Suite struct BetaQueueTests {
    let song = BetaEvent.firstSong(seconds: 60, service: .spotify)

    @Test func theQueueKeepsTheNewest200AndRemovesOnlyWhatWasSent() {
        var q = BetaQueue()
        for i in 0..<205 { q.add(QueuedEvent(song, at: Double(i), id: "e\(i)")) }
        #expect(q.events.count == 200 && q.events.first?.id == "e5" && q.events.last?.id == "e204")
        let sending = Set(q.events.prefix(3).map(\.id))
        q.add(QueuedEvent(song, at: 300, id: "new"))  // comes while the send runs; e5 goes
        q.remove(sending)
        #expect(q.events.count == 198 && q.events.first?.id == "e8" && q.events.last?.id == "new")
    }

    @Test func theSavedStringReadsBack() {
        var q = BetaQueue()
        q.add(QueuedEvent(.dayActive(DayUse(day: 20261119, weekday: 5), service: .appleMusic), at: 1.5, id: "a"))
        q.add(QueuedEvent(.useError(.listNotLoaded, offline: true, service: .spotify), at: 2, id: "b"))
        let back = BetaQueue(saved: q.saved)
        #expect(back.events.map(\.id) == ["a", "b"] && back.events[1] == q.events[1])
        #expect(back.events[0].properties["service"] == .text("apple_music") && back.events[0].properties["used_settings"] == .flag(false))
        #expect(BetaQueue(saved: "not json").events.isEmpty && BetaQueue(saved: nil).events.isEmpty)
        let decimal = QueuedEvent(.appSpeed(startMs: 3, libraryMs: 4), at: 0, id: "c")
        var d = BetaQueue(); d.add(decimal)
        #expect(BetaQueue(saved: d.saved).events == [decimal])
    }

    @Test func theBodyHasTheKeyThePersonAndEachEvent() throws {
        let e = QueuedEvent(song, at: 0, id: "u1")
        let body = BetaQueue.body([e], key: "phc_test", person: "acct-1")
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["api_key"] as? String == "phc_test")
        let item = try #require((json["batch"] as? [[String: Any]])?.first)
        #expect(item["event"] as? String == "first_song" && item["uuid"] as? String == "u1")
        #expect(item["timestamp"] as? String == "1970-01-01T00:00:00.000Z")
        let p = try #require(item["properties"] as? [String: Any])
        #expect(p["distinct_id"] as? String == "acct-1" && p["seconds"] as? Int == 60 && p["service"] as? String == "spotify")
    }

    /// CTO 23:46 JST: no device ID, hardware UUID, token or email in any event.
    @Test func noEventHoldsADeviceIDATokenOrAnEmail() {
        let all: [BetaEvent] = [
            .setupStep(.hello, seconds: 1, service: .spotify), .setupError(.loginFailed, service: .spotify), song,
            .controlLost(.timeout, service: .spotify), .controlBack(seconds: 3, service: .spotify),
            .appUpdated(from: 1, to: 2, days: 3), .useError(.loginFailed, offline: false, service: .spotify),
            .appSpeed(startMs: 1, libraryMs: 2), .musicPick(.spotify, top: .appleMusic, spotifyApp: true),
            .betaRenewal(.warning, pressed: true, daysLeft: 3), .serviceSwitch(from: .spotify, to: .appleMusic),
            .dayActive(DayUse(day: 20261119, weekday: 5), service: .spotify),
        ]
        let body = String(decoding: BetaQueue.body(all.map { QueuedEvent($0, at: 0) }, key: "k", person: "p"), as: UTF8.self).lowercased()
        for word in ["device", "hardware", "token", "email", "mail\"", "@"] {
            #expect(!body.contains(word), "\(word)")
        }
    }
}
