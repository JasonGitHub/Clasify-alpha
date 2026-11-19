import Testing
@testable import ClasifyCore

/// CLA-97, A4: `app_problem` from MetricKit's crash and hang reports.
@Suite struct AppProblemTests {
    func events(_ s: inout AppState, _ action: Action) -> [BetaEvent] {
        reduce(&s, action, Dependencies(now: { 100 }, random: { _ in 0 })).compactMap { (fx: Effect) -> BetaEvent? in
            if case .track(let event) = fx { return event }
            return nil
        }
    }

    @Test func eachReportedProblemIsOneEventAtMostTenPerLaunch() {
        var s = playing()
        let hang = AppProblem(kind: .hang, hangMs: 2500)
        #expect(events(&s, .appProblems([hang])) == [.appProblem(hang, service: .spotify)])
        #expect(events(&s, .appProblems(Array(repeating: hang, count: 14))).count == 10)
        #expect(events(&s, .appProblems([])).isEmpty)
    }

    @Test func aCrashSendsItsNumbersReasonAndAShortStack() {
        let frames = (0..<40).map { "myPod+\($0)" }
        let crash = AppProblem(
            kind: .crash, exceptionType: 1, exceptionCode: 2, signal: 11, terminationReason: String(repeating: "x", count: 300),
            appBuild: "356", osVersion: "macOS 27.0", binaryUUID: "ABC", frames: frames)
        let p = BetaEvent.appProblem(crash, service: .appleMusic).properties
        #expect(BetaEvent.appProblem(crash, service: .appleMusic).name == "app_problem")
        #expect(p["kind"] == .text("crash") && p["signal"] == .number(11) && p["exception_type"] == .number(1))
        #expect(p["exception_code"] == .number(2) && p["app_build"] == .text("356") && p["os_version"] == .text("macOS 27.0"))
        #expect(p["binary_uuid"] == .text("ABC") && p["service"] == .text("apple_music") && p["hang_ms"] == nil)
        #expect(p["termination_reason"] == .text(String(repeating: "x", count: 200)))
        #expect(p["stack"] == .text(frames.prefix(30).joined(separator: "\n")))
        #expect(AppProblem(kind: .hang, hangMs: 900).properties == ["kind": .text("hang"), "hang_ms": .number(900)])
    }
}
