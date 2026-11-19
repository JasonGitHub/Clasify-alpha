import ClasifyCore
import Foundation
import MetricKit

/// CLA-97 (A4): takes the crash and hang reports that macOS hands over through MetricKit,
/// at the launch after the problem. Each becomes an `AppProblem` at once; the raw report is not
/// kept, and nothing is written to disk. With `analytics.on` off the sender drops them, and
/// MetricKit does not hand them over again. No CPU or disk-write reports (CTO 01:08 JST 11-20).
final class BetaDiagnostics: NSObject, MXMetricManagerSubscriber, Sendable {
    private let send: @MainActor @Sendable (Action) -> Void

    init(send: @escaping @MainActor @Sendable (Action) -> Void) {
        self.send = send
        super.init()
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let problems = payloads.flatMap { payload in
            (payload.crashDiagnostics ?? []).map(Self.problem) + (payload.hangDiagnostics ?? []).map(Self.problem)
        }
        guard !problems.isEmpty else { return }
        let send = send
        Task { @MainActor in send(.appProblems(problems)) }
    }

    private static func problem(_ crash: MXCrashDiagnostic) -> AppProblem {
        var p = AppProblem(
            kind: .crash, exceptionType: crash.exceptionType?.intValue, exceptionCode: crash.exceptionCode?.intValue,
            signal: crash.signal?.intValue, terminationReason: crash.terminationReason)
        fill(&p, crash)
        return p
    }

    private static func problem(_ hang: MXHangDiagnostic) -> AppProblem {
        var p = AppProblem(kind: .hang, hangMs: Int(hang.hangDuration.converted(to: .milliseconds).value.rounded()))
        fill(&p, hang)
        return p
    }

    private static let own = Bundle.main.executableURL?.lastPathComponent

    private static func fill(_ p: inout AppProblem, _ diagnostic: MXDiagnostic) {
        p.appBuild = diagnostic.metaData.applicationBuildVersion
        p.osVersion = diagnostic.metaData.osVersion
        let stack: MXCallStackTree? = (diagnostic as? MXCrashDiagnostic)?.callStackTree ?? (diagnostic as? MXHangDiagnostic)?.callStackTree
        if let stack { (p.frames, p.binaryUUID) = AppProblem.stack(json: stack.jsonRepresentation(), ownBinary: own) }
    }
}
