import ClasifyCore
import Foundation

/// CLA-166 (card CG, 384): sends Help › Report a Problem to the server, POST /v1/feedback. A
/// report waits in memory only, never on disk: with no connection, or with the server busy or
/// at its limit, it goes again later while the app runs (after 1 min, then 2, 4… up to 1 h).
/// The server's mail goes to the team; the text is not logged or sent anywhere else.
@MainActor
final class ProblemReporter {
    static let shared = ProblemReporter()

    struct Report: Sendable {
        let text: String
        let writeBack: Bool
        let service: String
    }

    var server = ServerActivator()
    /// The active service, from the store. AppModel sets it.
    var service: () -> String = { "" }
    private var pending: [Report] = []
    private var sending = false
    private var wait: Duration = .seconds(60)
    private var retry: Task<Void, Never>?

    func send(_ text: String, writeBack: Bool) {
        pending.append(Report(text: text, writeBack: writeBack, service: service()))
        Task { await flush() }
    }

    /// Sends the waiting reports in order. A sent report goes away. So does one the server
    /// refuses for good (400 bad text, 401 Mac not active): sending it again cannot help.
    private func flush() async {
        guard !sending else { return }
        sending = true
        defer { sending = false }
        while let report = pending.first {
            let status = await server.report(Self.body(report))
            if let status, status == 200 || status == 400 || status == 401 {
                pending.removeFirst()
                wait = .seconds(60)
            } else {
                later()
                return
            }
        }
    }

    private func later() {
        guard retry == nil else { return }
        let delay = wait
        wait = min(wait * 2, .seconds(3600))
        retry = Task { [weak self] in
            try? await Task.sleep(for: delay)
            self?.retry = nil
            await self?.flush()
        }
    }

    static func body(_ report: Report) -> Data {
        let info = Bundle.main.infoDictionary ?? [:]
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let json: [String: Any] = [
            "text": report.text,
            "writeBack": report.writeBack,
            "appVersion": info["CFBundleShortVersionString"] as? String ?? "",
            "build": info["CFBundleVersion"] as? String ?? "",
            "macOS": "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            "macModel": macModel,
            "service": report.service,
        ]
        return (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
    }

    /// The model name, such as "Mac15,3".
    static var macModel: String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "" }
        return bytes.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }
}
