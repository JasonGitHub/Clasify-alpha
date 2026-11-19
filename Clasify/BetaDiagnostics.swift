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

    private static func fill(_ p: inout AppProblem, _ diagnostic: MXDiagnostic) {
        p.appBuild = diagnostic.metaData.applicationBuildVersion
        p.osVersion = diagnostic.metaData.osVersion
        let stack: MXCallStackTree? = (diagnostic as? MXCrashDiagnostic)?.callStackTree ?? (diagnostic as? MXHangDiagnostic)?.callStackTree
        if let stack { (p.frames, p.binaryUUID) = frames(stack.jsonRepresentation()) }
    }

    /// The frames of the thread that the report points at (`threadAttributed`), else the first
    /// one, from the innermost frame out: binary names only, never a path.
    static func frames(_ json: Data) -> (frames: [String], ownUUID: String?) {
        guard let tree = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let stacks = tree["callStacks"] as? [[String: Any]] else { return ([], nil) }
        let thread = stacks.first { $0["threadAttributed"] as? Bool == true } ?? stacks.first
        let own = Bundle.main.executableURL?.lastPathComponent
        var frames: [String] = [], ownUUID: String?
        var frame = (thread?["callStackRootFrames"] as? [[String: Any]])?.first
        while let f = frame, frames.count < AppProblem.maxFrames {
            let name = ((f["binaryName"] as? String) ?? "?").split(separator: "/").last.map(String.init) ?? "?"
            let offset = (f["offsetIntoBinaryTextSegment"] as? NSNumber)?.intValue ?? 0
            frames.append("\(name)+\(offset)")
            if name == own, ownUUID == nil { ownUUID = f["binaryUUID"] as? String }
            frame = (f["subFrames"] as? [[String: Any]])?.first
        }
        return (frames, ownUUID)
    }
}
