import ClasifyCore
import Foundation
import Security

/// CLA-128: the app's side of the activation server (server/). The device ID is the only
/// secret; it lives in the Keychain, goes out only in the Authorization header, and is never
/// printed. The email in an answer stays in memory (AppState) only.
struct ServerActivator: Activator {
    /// Set up at deploy time, with Jason's OK.
    static let host = URL(string: "https://api.getmypod.app")!

    var session: URLSession = ServerActivator.ephemeral
    var deviceID: @Sendable () -> String? = { DeviceIDStore.readOrMake() }

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

    private func ask(_ method: String, _ path: String) async -> Activation {
        guard let answer = await call(method, path) else { return .offline }
        return Activation(status: answer.status, json: answer.json)
    }

    /// One request with the device header. Nil for no connection or a timeout.
    private func call(_ method: String, _ path: String) async -> (status: Int, json: [String: Any]?)? {
        guard let id = deviceID() else { return nil }
        var request = URLRequest(url: Self.host.appending(path: path))
        request.httpMethod = method
        request.setValue("Device \(id)", forHTTPHeaderField: "Authorization")
        if method == "POST" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data("{}".utf8)
        }
        guard let result = try? await session.data(for: request), let http = result.1 as? HTTPURLResponse else { return nil }
        return (http.statusCode, (try? JSONSerialization.jsonObject(with: result.0)) as? [String: Any])
    }
}

/// The activation device ID: 32 random bytes as base64url, made once, kept only in the Keychain.
enum DeviceIDStore {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: AppID.bundle + ".activation",
         kSecAttrAccount as String: "device-id"]
    }

    /// The stored ID, if this Mac has one. It makes none.
    static func read() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// The stored ID, or a new one. Nil when the Keychain refuses it.
    static func readOrMake() -> String? {
        if let id = read() { return id }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        let id = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        var item = query
        item[kSecValueData as String] = Data(id.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem { return read() }  // another call made it first
        return status == errSecSuccess ? id : nil
    }
}
