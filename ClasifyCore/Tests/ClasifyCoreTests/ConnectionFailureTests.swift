import Foundation
import Testing
@testable import ClasifyCore

/// CLA-180: the `reason` of `setup_error` with `kind = no_connection`.
@Suite struct ConnectionFailureTests {
    @Test func eachURLErrorCodeMapsToItsReason() {
        let codes: [(URLError.Code, ConnectionFailure)] = [
            (.cannotFindHost, .dns), (.dnsLookupFailed, .dns),
            (.secureConnectionFailed, .tls), (.serverCertificateHasBadDate, .tls), (.serverCertificateUntrusted, .tls),
            (.serverCertificateHasUnknownRoot, .tls), (.serverCertificateNotYetValid, .tls),
            (.clientCertificateRejected, .tls), (.clientCertificateRequired, .tls),
            (.timedOut, .timeout),
            (.notConnectedToInternet, .offline), (.networkConnectionLost, .offline),
            (.cannotConnectToHost, .other(URLError.Code.cannotConnectToHost.rawValue)),
            (.cancelled, .other(URLError.Code.cancelled.rawValue)),
        ]
        for (code, failure) in codes {
            #expect(ConnectionFailure(urlErrorCode: code.rawValue) == failure, "\(code.rawValue)")
        }
        #expect(ConnectionFailure(urlErrorCode: 0) == .other(0))  // not a URLError
    }

    @Test func eachReasonHasAFixedNameWithNoAddressOrText() {
        let names: [(ConnectionFailure, String)] = [
            (.noDeviceID, "no_device_id"), (.dns, "dns"), (.tls, "tls"), (.timeout, "timeout"), (.offline, "offline"),
            (.server(503), "server_503"), (.server(200), "server_200"), (.other(-1004), "other_-1004"), (.other(0), "other_0"),
        ]
        for (failure, name) in names { #expect(failure.eventName == name) }
    }

    @Test func theReasonIsAPropertyOnlyWhenThereIsOne() {
        let with = BetaEvent.setupError(.noConnection, service: .appleMusic, reason: .dns)
        #expect(with.properties == ["kind": .text("no_connection"), "service": .text("apple_music"), "reason": .text("dns")])
        let without = BetaEvent.setupError(.noConnection, service: .appleMusic)
        #expect(without.properties == ["kind": .text("no_connection"), "service": .text("apple_music")])
    }

    func events(_ s: inout AppState, _ actions: Action..., now: Double) -> [BetaEvent] {
        let e = Dependencies(now: { now }, random: { _ in 0 })
        return actions.flatMap { reduce(&s, $0, e) }.compactMap { (fx: Effect) -> BetaEvent? in
            if case .track(let event) = fx { return event }
            return nil
        }
    }

    /// On Activate, a press, then the answer.
    func pressedActivate() -> AppState {
        var s = AppState()
        _ = events(&s, .spotifyAppFound(true), .launch, .restored(token: 1, ok: false), .select, now: 100)
        _ = events(&s, .select, .select, .select, .authDone(token: 2, ok: true), now: 100)
        _ = events(&s, .tick, now: 101.5)
        _ = events(&s, .select, now: 200)
        _ = events(&s, .checkActivation, .activation(.waiting(email: "sam@example.com", mail: 1), request: 2), now: 210)
        return s
    }

    @Test func noConnectionSendsItsReasonAndOtherErrorsSendNone() {
        var s = pressedActivate()
        #expect(events(&s, .select, .activation(.offline, request: 3, failure: .noDeviceID), now: 300)
            == [.setupError(.noConnection, service: .spotify, reason: .noDeviceID)])
        #expect(s.activateFailure == .noDeviceID)

        var busy = pressedActivate()
        #expect(events(&busy, .select, .activation(.mailBusy, request: 3, failure: .dns), now: 300)
            == [.setupError(.mailBusy, service: .spotify)])
        #expect(busy.activateFailure == nil)  // only `.offline` keeps a reason
    }

    @Test func anAnswerAfterNoConnectionClearsTheReason() {
        var s = pressedActivate()
        _ = events(&s, .select, .activation(.offline, request: 3, failure: .timeout), now: 300)
        #expect(s.activateFailure == .timeout)
        _ = events(&s, .select, .activation(.waiting(email: "sam@example.com", mail: 1), request: 4), now: 310)
        #expect(s.activateFailure == nil)
    }
}
