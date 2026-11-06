import Foundation
import Observation

/// The spike's event log. It stays in memory and on stdout only. It writes no file.
@MainActor @Observable final class SpikeLog {
    static let shared = SpikeLog()

    private(set) var lines: [String] = []

    @ObservationIgnored private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return f
    }()

    func add(_ tag: String, _ text: String) {
        let line = "\(formatter.string(from: Date())) JST [\(tag)] \(text)"
        lines.append(line)
        print(line)
    }

    func clear() { lines.removeAll() }

    var text: String { lines.joined(separator: "\n") }
}

func elapsedMS(since start: Date) -> Int { Int(Date().timeIntervalSince(start) * 1000) }
