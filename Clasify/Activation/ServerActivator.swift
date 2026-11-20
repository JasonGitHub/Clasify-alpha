import ClasifyCore
import Foundation

/// CLA-128: the app's side of the activation server (server/). The device ID is the only
/// secret. CLA-156: it is always the hardware ID (`HardwareID`), computed at each request and
/// stored nowhere; it goes out only in the Authorization header, and is never printed. The email in an answer stays in memory (AppState) only.
struct ServerActivator: Activator {
    /// Set up at deploy time, with Jason's OK.
    static let host = URL(string: "https://api.getmypod.app")!

    var session: URLSession = ServerActivator.ephemeral
    /// CLA-156: always the hardware ID. With no hardware UUID there is no ID, never a random one.
    var deviceID: @Sendable () -> String? = { HardwareID.deviceID() }

    static let ephemeral: URLSession = {
        let config = URLSessionConfiguration.ephemeral  // no cache, no cookies, nothing on disk
        config.timeoutIntervalForRequest = 10
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    func status() async -> Activation { await ask("GET", "/v1/status") }
    func sendAgain() async -> Activation { await ask("POST", "/v1/start") }

    func pageURL() async -> String? {
        guard let answer = await call("POST", "/v1/open"), (200..<300).contains(answer.status), let code = answer.json?["code"] as? String,
              var page = URLComponents(string: "https://getmypod.app/activate/") else { return nil }
        page.queryItems = [URLQueryItem(name: "d", value: code)]
        return page.url?.absoluteString
    }

    /// CLA-166: POST /v1/feedback with the report. The status, or nil for no connection.
    func report(_ body: Data) async -> Int? { await call("POST", "/v1/feedback", body: body)?.status }

    private func ask(_ method: String, _ path: String) async -> Activation {
        guard let answer = await call(method, path) else { return .offline }
        return Activation(status: answer.status, json: answer.json)
    }

    /// One request with the device header. Nil for no connection or a timeout.
    private func call(_ method: String, _ path: String, body: Data = Data("{}".utf8)) async -> (status: Int, json: [String: Any]?)? {
        guard let id = deviceID() else { return nil }
        var request = URLRequest(url: Self.host.appending(path: path))
        request.httpMethod = method
        request.setValue("Device \(id)", forHTTPHeaderField: "Authorization")
        if method == "POST" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        guard let result = try? await session.data(for: request), let http = result.1 as? HTTPURLResponse else { return nil }
        return (http.statusCode, (try? JSONSerialization.jsonObject(with: result.0)) as? [String: Any])
    }
}
