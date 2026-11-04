import AppKit
import Darwin
import Foundation
import Observation

/// Build 6: runs go-librespot as a subprocess to see if Spotify grants it audio keys.
/// Spike only. go-librespot is not a product dependency.
@MainActor
@Observable
final class GoLibrespotProbe {
    private(set) var results: [SpotifyAppProbe.ResultLine] = []
    private(set) var status = "Not run"
    private(set) var isBusy = false

    @ObservationIgnored private var log: [String] = []
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var workDir: URL?
    @ObservationIgnored private var reader: PipeReader?
    @ObservationIgnored private var openedLoginURL = false

    static let apiPort = 36783
    static let pipeFormat = "s16le"

    private var binary: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/go-librespot")
    }

    private func set(_ name: String, _ value: String) {
        if let index = results.firstIndex(where: { $0.name == name }) {
            results[index].value = value
        } else {
            results.append(SpotifyAppProbe.ResultLine(name: name, value: value))
        }
    }

    // MARK: Run

    func run(tracks: [(name: String, uri: String)]) async {
        guard !isBusy else { return }
        isBusy = true
        results = []
        log = []
        openedLoginURL = false
        defer {
            stop()
            isBusy = false
        }
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            set("go-librespot binary", "missing at \(binary.path)")
            status = "Binary missing"
            return
        }
        do {
            try start()
        } catch {
            set("Start", "failed: \(error.localizedDescription)")
            status = "Start failed"
            return
        }
        status = "Waiting for login in the browser"
        guard await waitForLogin() else {
            status = "Login failed or timed out"
            return
        }
        for track in tracks {
            status = "Playing \(track.name)"
            await play(track)
        }
        set("Pipe bytes total", "\(reader?.bytes ?? 0)")
        status = "Done"
    }

    private func start() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("clasify-golibrespot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        workDir = dir
        let pipePath = dir.appendingPathComponent("audio.pipe").path
        guard mkfifo(pipePath, 0o600) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "mkfifo failed (\(errno))"])
        }
        // Credentials (state.json) stay in this temp dir, which stop() deletes.
        let config = """
        log_level: debug
        device_name: Clasify spike
        zeroconf_enabled: false
        disable_autoplay: true
        audio_backend: pipe
        audio_output_pipe: '\(pipePath)'
        audio_output_pipe_format: \(Self.pipeFormat)
        audio_output_pipe_wait_for_reader: true
        cache:
          enabled: false
        credentials:
          type: interactive
        server:
          enabled: true
          address: 127.0.0.1
          port: \(Self.apiPort)
        """
        try config.write(to: dir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

        let reader = PipeReader(path: pipePath)
        reader.start()
        self.reader = reader

        let process = Process()
        process.executableURL = binary
        process.arguments = ["--config_dir", dir.path]
        process.currentDirectoryURL = dir
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        Self.readLines(from: output, Self.onMain { [weak self] line in self?.received(line) })
        process.terminationHandler = Self.onTermination(Self.onMain { [weak self] code in
            self?.append("EXIT status \(code)")
        })
        try process.run()
        self.process = process
        set("Temp dir", "created (config, FIFO and credentials live here)")
    }

    /// Ends go-librespot and deletes the temp dir with its credentials.
    private func stop() {
        if let process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        process = nil
        reader?.stop()
        reader = nil
        if let workDir {
            try? FileManager.default.removeItem(at: workDir)
            let gone = !FileManager.default.fileExists(atPath: workDir.path)
            set("Temp dir deleted", gone ? "yes" : "NO: \(workDir.path)")
        }
        workDir = nil
    }

    private func waitForLogin() async -> Bool {
        for _ in 0..<1800 {
            if log.contains(where: { $0.contains("authenticated AP") }) {
                set("Login", "PASS (authenticated AP)")
                // Give the API server a moment.
                try? await Task.sleep(for: .seconds(2))
                return true
            }
            if process?.isRunning != true {
                set("Login", "FAIL: go-librespot exited")
                return false
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        set("Login", "FAIL: no login within 180 s")
        return false
    }

    private func play(_ track: (name: String, uri: String)) async {
        let startLine = log.count
        let startBytes = reader?.bytes ?? 0
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(Self.apiPort)/player/play")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["uri": track.uri])
        var httpStatus = "no response"
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            httpStatus = "\((response as? HTTPURLResponse)?.statusCode ?? 0)"
        } catch {
            httpStatus = "error: \(error.localizedDescription)"
        }
        append("POST /player/play \(track.uri) -> \(httpStatus)")
        // Wait up to 12 s for audio or a refusal.
        var verdict = "no audio and no key line within 12 s"
        for _ in 0..<120 {
            try? await Task.sleep(for: .milliseconds(100))
            let recent = log[min(startLine, log.count)...]
            if recent.contains(where: { $0.contains("refused the audio key") || $0.contains("failed retrieving audio key") }) {
                verdict = "REFUSED"
                break
            }
            if (reader?.bytes ?? 0) - startBytes > 176_400 { // About 0.5 s of 44.1 kHz stereo s16le.
                verdict = "GRANTED (audio is flowing)"
                break
            }
        }
        let bytes = (reader?.bytes ?? 0) - startBytes
        let keyLines = log[min(startLine, log.count)...]
            .filter { $0.lowercased().contains("key") || $0.contains("playback_error") || $0.contains("unplayable") }
            .suffix(3)
            .map { $0.count > 300 ? String($0.prefix(300)) + "..." : $0 }
        let detail = keyLines.isEmpty ? "" : " | " + keyLines.joined(separator: " | ")
        set(track.name, "\(verdict), POST \(httpStatus), \(bytes) bytes to the pipe\(detail)")
        _ = try? await URLSession.shared.data(for: {
            var pause = URLRequest(url: URL(string: "http://127.0.0.1:\(Self.apiPort)/player/pause")!)
            pause.httpMethod = "POST"
            return pause
        }())
    }

    // MARK: Log

    private func received(_ line: String) {
        if !openedLoginURL, line.contains("to complete authentication visit the following link:"),
           let range = line.range(of: "https://") {
            let text = line[range.lowerBound...].prefix { !$0.isWhitespace && $0 != "\"" }
            if let url = URL(string: String(text)) {
                openedLoginURL = true
                NSWorkspace.shared.open(url)
                let clientID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "client_id" }?.value ?? "unknown"
                set("Client ID", clientID)
                append("Opened the login link in the browser")
            }
        }
        if line.contains("running go-librespot"), let range = line.range(of: "running go-librespot ") {
            set("go-librespot version", String(line[range.upperBound...].prefix { !$0.isWhitespace && $0 != "\"" }))
        }
        if line.contains("connected to "), let range = line.range(of: "connected to ") {
            set("AP host", String(line[range.upperBound...].prefix { !$0.isWhitespace && $0 != "\"" }))
        }
        append(Self.scrub(line))
    }

    private func append(_ line: String) {
        log.append(line)
        if log.count > 2000 { log.removeFirst(log.count - 2000) }
    }

    /// Hides any line that may hold a credential. The login URL holds no secret, but the
    /// callback with the code and the tokens after it do.
    nonisolated static func scrub(_ line: String) -> String {
        let lower = line.lowercased()
        let markers = ["token", "bearer", "authorization", "password", "code=", "auth_data", "credentials", "stored_credential"]
        guard markers.contains(where: { lower.contains($0) }) else { return line }
        return String(line.prefix(40)) + " [hidden: may hold a credential]"
    }

    // MARK: Threads

    nonisolated private static func onMain<T: Sendable>(
        _ handler: @escaping @MainActor @Sendable (T) -> Void
    ) -> @Sendable (T) -> Void {
        { value in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { handler(value) }
            }
        }
    }

    /// Built in a nonisolated function, so the handler has no actor isolation.
    nonisolated private static func onTermination(_ handler: @escaping @Sendable (Int32) -> Void) -> @Sendable (Process) -> Void {
        { process in handler(process.terminationStatus) }
    }

    /// Splits the output into lines on a background thread.
    nonisolated private static func readLines(from pipe: Pipe, _ handler: @escaping @Sendable (String) -> Void) {
        let handle = pipe.fileHandleForReading
        DispatchQueue.global(qos: .utility).async {
            var buffer = Data()
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let index = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer[buffer.startIndex..<index]
                    buffer.removeSubrange(buffer.startIndex...index)
                    handler(String(decoding: lineData, as: UTF8.self))
                }
            }
            if !buffer.isEmpty { handler(String(decoding: buffer, as: UTF8.self)) }
        }
    }

    // MARK: Report

    var reportLines: [String] {
        if results.isEmpty { return ["   Not run"] }
        return results.map { "   \($0.name): \($0.value)" }
            + ["   Pipe format: \(Self.pipeFormat)", "   Last 50 log lines:"]
            + log.suffix(50).map { "     \($0.count > 400 ? String($0.prefix(400)) + "..." : $0)" }
    }
}

/// Reads the audio FIFO on a background thread and counts the bytes. The audio is
/// dropped, not stored.
// @unchecked Sendable is safe: every mutable field is read and written only under `lock`.
private final class PipeReader: @unchecked Sendable {
    private let path: String
    private let lock = NSLock()
    private var count = 0
    private var stopped = false

    init(path: String) { self.path = path }

    var bytes: Int { lock.withLock { count } }
    private var isStopped: Bool { lock.withLock { stopped } }

    func start() {
        Thread.detachNewThread { [self] in
            var buffer = [UInt8](repeating: 0, count: 65_536)
            // go-librespot may close and reopen the FIFO between tracks, so reopen after EOF.
            while !isStopped {
                let fd = open(path, O_RDONLY)
                guard fd >= 0 else { return }
                while true {
                    let n = read(fd, &buffer, buffer.count)
                    if n <= 0 { break }
                    lock.withLock { count += n }
                }
                close(fd)
            }
        }
    }

    func stop() {
        lock.withLock { stopped = true }
        // Unblock a reader that waits in open(): open the FIFO for writing, then close it.
        let fd = open(path, O_WRONLY | O_NONBLOCK)
        if fd >= 0 { close(fd) }
    }
}
