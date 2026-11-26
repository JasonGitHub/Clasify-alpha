import Foundation

/// CLA-97 (A4): a crash or a hang of an earlier run, as macOS reports it through MetricKit at
/// a later launch. The app turns each report into this, with no file and no raw report kept.
/// It holds no song, artist or playlist names and no paths: only numbers, the system's short
/// reason, and the stack as binary names with offsets (symbolicated later with the dSYM).
public struct AppProblem: Equatable, Sendable {
    public enum Kind: String, Sendable { case crash, hang }

    /// At most this many frames, this many reports from one launch, and this long a reason
    /// (CTO 01:08 JST 11-20: one bad launch must not fill the queue of 200).
    public static let maxFrames = 30, maxPerLaunch = 10, maxReason = 200

    public var kind: Kind
    public var exceptionType: Int?, exceptionCode: Int?, signal: Int?
    public var terminationReason: String?
    public var hangMs: Int?
    /// The build and macOS that had the problem, from the report, not the ones that send it.
    public var appBuild: String?, osVersion: String?
    /// Our own binary's UUID, once, to find its dSYM.
    public var binaryUUID: String?
    /// The crashed thread's frames (a hang: the main thread's), each "binaryName+offset".
    public var frames: [String]

    public init(
        kind: Kind, exceptionType: Int? = nil, exceptionCode: Int? = nil, signal: Int? = nil,
        terminationReason: String? = nil, hangMs: Int? = nil, appBuild: String? = nil, osVersion: String? = nil,
        binaryUUID: String? = nil, frames: [String] = []
    ) {
        (self.kind, self.exceptionType, self.exceptionCode, self.signal) = (kind, exceptionType, exceptionCode, signal)
        (self.terminationReason, self.hangMs, self.appBuild, self.osVersion) = (terminationReason, hangMs, appBuild, osVersion)
        (self.binaryUUID, self.frames) = (binaryUUID, frames)
    }

    /// The frames of `MXCallStackTree.jsonRepresentation()`, from the thread that the report
    /// points at (`threadAttributed`), else the first one, innermost frame first: binary names
    /// only, never a path. Also the UUID of `ownBinary`, once. The tree can sit under a
    /// top-level "callStackTree" key (Apple's documented form) or be the top level itself.
    public static func stack(json: Data, ownBinary: String?) -> (frames: [String], ownUUID: String?) {
        guard let top = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return ([], nil) }
        let tree = top["callStackTree"] as? [String: Any] ?? top
        guard let stacks = tree["callStacks"] as? [[String: Any]] else { return ([], nil) }
        let thread = stacks.first { $0["threadAttributed"] as? Bool == true } ?? stacks.first
        var frames: [String] = [], ownUUID: String?
        var frame = (thread?["callStackRootFrames"] as? [[String: Any]])?.first
        while let f = frame, frames.count < maxFrames {
            let name = ((f["binaryName"] as? String) ?? "?").split(separator: "/").last.map(String.init) ?? "?"
            let offset = f["offsetIntoBinaryTextSegment"] as? Int ?? (f["offsetIntoBinaryTextSegment"] as? NSNumber)?.intValue ?? 0
            frames.append("\(name)+\(offset)")
            if name == ownBinary, ownUUID == nil { ownUUID = f["binaryUUID"] as? String }
            frame = (f["subFrames"] as? [[String: Any]])?.first
        }
        return (frames, ownUUID)
    }

    var properties: [String: BetaValue] {
        var p: [String: BetaValue] = ["kind": .text(kind.rawValue)]
        if let exceptionType { p["exception_type"] = .number(exceptionType) }
        if let exceptionCode { p["exception_code"] = .number(exceptionCode) }
        if let signal { p["signal"] = .number(signal) }
        if let terminationReason { p["termination_reason"] = .text(String(terminationReason.prefix(Self.maxReason))) }
        if let hangMs { p["hang_ms"] = .number(hangMs) }
        // CLA-194 (CTO): a number, as on every other event. Text that is not a number: no field.
        if let build = appBuild.flatMap({ Int($0) }) { p["app_build"] = .number(build) }
        if let osVersion { p["os_version"] = .text(osVersion) }
        if let binaryUUID { p["binary_uuid"] = .text(binaryUUID) }
        if !frames.isEmpty { p["stack"] = .text(frames.prefix(Self.maxFrames).joined(separator: "\n")) }
        return p
    }
}
