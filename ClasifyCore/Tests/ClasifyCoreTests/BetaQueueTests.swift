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
        q.add(QueuedEvent(.dayActive(DayUse(day: 20261119, weekday: 5), service: .appleMusic, color: .silver), at: 1.5, id: "a"))
        q.add(QueuedEvent(.useError(.listNotLoaded, offline: true, service: .spotify), at: 2, id: "b"))
        let back = BetaQueue(saved: q.saved)
        #expect(back.events.map(\.id) == ["a", "b"] && back.events[1] == q.events[1])
        #expect(back.events[0].properties["service"] == .text("apple_music") && back.events[0].properties["used_settings"] == .flag(false))
        #expect(BetaQueue(saved: "not json").events.isEmpty && BetaQueue(saved: nil).events.isEmpty)
        var use = DayUse(day: 20261119, weekday: 5)
        use.bands = [90, 0, 60, 0]  // 1.5 and 1 minutes: one with a fraction, one whole
        var d = BetaQueue(); d.add(QueuedEvent(.dayActive(use, service: .spotify, color: .silver), at: 0, id: "c"))
        let p = BetaQueue(saved: d.saved).events[0].properties
        #expect(p["minutes_night"] == .decimal(1.5) && p["minutes"] == .decimal(2.5))
        #expect(p["minutes_work"] == .number(1))  // a whole decimal reads back as a number: the same in PostHog
    }

    /// CLA-194: each event carries the build that made it, stamped when it is made.
    @Test func eachEventCarriesTheBuildThatMadeIt() throws {
        var q = BetaQueue()
        q.add(song, at: 1, build: 480)
        q.add(song, at: 2)  // an event from before CLA-194, or a build with no number: no field
        #expect(q.events[0].properties["app_build"] == .number(480) && q.events[1].properties["app_build"] == nil)
        let back = BetaQueue(saved: q.saved)  // it waits across an update: still the old build
        #expect(back.events[0].properties["app_build"] == .number(480))
        let body = BetaQueue.body(back.events, key: "k", person: "p")
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let p = try #require((json["batch"] as? [[String: Any]])?.first?["properties"] as? [String: Any])
        #expect(p["app_build"] as? Int == 480)
        // app_problem keeps its own: the build that crashed, from MetricKit.
        let crash = AppProblem(kind: .crash, appBuild: "470", frames: [])
        #expect(QueuedEvent(.appProblem(crash, service: .spotify), at: 3, build: 480).properties["app_build"] == .text("470"))
        #expect(QueuedEvent(.appProblem(AppProblem(kind: .crash, frames: []), service: .spotify), at: 3, build: 480).properties["app_build"] == .number(480))
    }

    @Test func theBodyHasTheKeyThePersonAndEachEvent() throws {
        let e = QueuedEvent(song, at: 816_789_600, id: "u1")  // 2026-11-19 14:00 UTC (from 2001)
        let body = BetaQueue.body([e], key: "phc_test", person: "acct-1")
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["api_key"] as? String == "phc_test")
        let item = try #require((json["batch"] as? [[String: Any]])?.first)
        #expect(item["event"] as? String == "first_song" && item["uuid"] as? String == "u1")
        #expect(item["timestamp"] as? String == "2026-11-19T14:00:00.000Z")
        let p = try #require(item["properties"] as? [String: Any])
        #expect(p["distinct_id"] as? String == "acct-1" && p["seconds"] as? Int == 60 && p["service"] as? String == "spotify")
    }

    /// Jason "ok 1" (21:00 JST 11-20): before activation the events go out as the random install
    /// ID; with the account ID they go out as the account, and the first such batch links the two.
    @Test func theInstallIDSendsBeforeActivationAndLinksOnce() throws {
        #expect(BetaQueue.person(account: nil, install: nil) == nil)
        #expect(BetaQueue.person(account: nil, install: "i1") == "i1")
        #expect(BetaQueue.person(account: "acct-1", install: "i1") == "acct-1")
        #expect(BetaQueue.linking(account: nil, install: "i1", linked: false) == nil)
        #expect(BetaQueue.linking(account: "acct-1", install: "i1", linked: false) == "i1")
        #expect(BetaQueue.linking(account: "acct-1", install: "i1", linked: true) == nil)
        #expect(BetaQueue.linking(account: "acct-1", install: nil, linked: false) == nil)

        let e = QueuedEvent(song, at: 816_789_600, id: "u1")
        let body = BetaQueue.body([e], key: "k", person: "acct-1", linking: "i1", linkID: "l1")
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let batch = try #require(json["batch"] as? [[String: Any]])
        #expect(batch.count == 2 && batch[0]["event"] as? String == "$identify" && batch[0]["uuid"] as? String == "l1")
        let link = try #require(batch[0]["properties"] as? [String: Any])
        #expect(link["distinct_id"] as? String == "acct-1" && link["$anon_distinct_id"] as? String == "i1")
        #expect(batch[1]["event"] as? String == "first_song" && (batch[1]["properties"] as? [String: Any])?["distinct_id"] as? String == "acct-1")
        // No link without one, or to itself.
        for plain in [BetaQueue.body([e], key: "k", person: "i1"), BetaQueue.body([e], key: "k", person: "i1", linking: "i1")] {
            let items = try #require((try JSONSerialization.jsonObject(with: plain) as? [String: Any])?["batch"] as? [[String: Any]])
            #expect(items.count == 1 && items[0]["event"] as? String == "first_song")
        }
    }

    /// CTO 23:46 JST: no device ID, hardware UUID, token or email in any event.
    @Test func noEventHoldsADeviceIDATokenOrAnEmail() {
        let all: [BetaEvent] = [
            .setupStep(.hello, seconds: 1, service: .spotify), .setupError(.loginFailed, service: .spotify), song,
            .controlLost(.timeout, service: .spotify), .controlBack(seconds: 3, service: .spotify),
            .appUpdated(from: 1, to: 2, days: 3), .useError(.loginFailed, offline: false, service: .spotify),
            .appSpeed(startMs: 1, libraryMs: 2, loaded: true), .musicPick(.spotify, top: .appleMusic, spotifyApp: true),
            .betaRenewal(.warning, pressed: true, daysLeft: 3), .serviceSwitch(from: .spotify, to: .appleMusic),
            .dayActive(DayUse(day: 20261119, weekday: 5), service: .spotify, color: .silver),
        ]
        let body = String(decoding: BetaQueue.body(all.map { QueuedEvent($0, at: 0) }, key: "k", person: "p"), as: UTF8.self).lowercased()
        for word in ["device", "hardware", "token", "email", "mail\"", "@"] {
            #expect(!body.contains(word), "\(word)")
        }
        // No 43-character base64url string, the form of the activation device ID.
        let long = body.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }).filter { $0.count >= 43 }
        #expect(long.isEmpty, "\(long)")
    }
}
