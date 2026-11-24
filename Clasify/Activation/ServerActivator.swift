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

    func status() async -> Result<Activation, ConnectionFailure> { await ask("GET", "/v1/status") }
    func sendAgain() async -> Result<Activation, ConnectionFailure> { await ask("POST", "/v1/start") }

    func pageURL() async -> Result<String, ConnectionFailure> {
        await call("POST", "/v1/open").flatMap { answer in
            guard (200..<300).contains(answer.status), let code = answer.json?["code"] as? String,
                  var page = URLComponents(string: "https://getmypod.app/activate/") else { return .failure(.server(answer.status)) }
            page.queryItems = [URLQueryItem(name: "d", value: code)]
            return page.url.map { .success($0.absoluteString) } ?? .failure(.server(answer.status))
        }
    }

    /// CLA-166: POST /v1/feedback with the report. The status, or nil for no connection.
    func report(_ body: Data) async -> Int? { try? await call("POST", "/v1/feedback", body: body).get().status }

    /// The answer as an `Activation`. An answer the app does not know is a server failure (CLA-180).
    private func ask(_ method: String, _ path: String) async -> Result<Activation, ConnectionFailure> {
        await call(method, path).flatMap { answer in
            let activation = Activation(status: answer.status, json: answer.json)
            return activation == .offline ? .failure(.server(answer.status)) : .success(activation)
        }
    }

    /// One request with the device header. A failure says why there is no answer, with no URL,
    /// host or error text (CLA-180).
    private func call(_ method: String, _ path: String, body: Data = Data("{}".utf8)) async -> Result<(status: Int, json: [String: Any]?), ConnectionFailure> {
        guard let id = deviceID() else { return .failure(.noDeviceID) }
        var request = URLRequest(url: Self.host.appending(path: path))
        request.httpMethod = method
        request.setValue("Device \(id)", forHTTPHeaderField: "Authorization")
        if method == "POST" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch {
            return .failure(ConnectionFailure(urlErrorCode: (error as? URLError)?.errorCode ?? 0))
        }
        guard let http = result.1 as? HTTPURLResponse else { return .failure(.other(0)) }
        return .success((status: http.statusCode, json: (try? JSONSerialization.jsonObject(with: result.0)) as? [String: Any]))
    }
}
