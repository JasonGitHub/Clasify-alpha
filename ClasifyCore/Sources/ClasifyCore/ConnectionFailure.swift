/// CLA-180: why a request to our server got no usable answer. It goes out as the `reason` of
/// `setup_error` with `kind = no_connection`. It holds no URL, host, address, device ID or error
/// text: only a fixed name, an HTTP status or a `URLError` code.
public enum ConnectionFailure: Error, Equatable, Sendable {
    /// The Mac gave no hardware ID, so no request went out.
    case noDeviceID
    /// The name did not resolve: often a DNS filter that blocks the domain.
    case dns
    /// The secure connection failed: a certificate or a network that inspects HTTPS.
    case tls
    case timeout
    /// The Mac is offline, or the connection dropped.
    case offline
    /// Our server answered with a status outside 200 to 299, or with an answer the app does not know.
    case server(Int)
    /// Any other error, with its `URLError` code (0: not a `URLError`).
    case other(Int)

    /// The failure for a `URLError` code. Core takes the plain number, so it needs no URLSession
    /// types; the app passes `URLError.errorCode`.
    public init(urlErrorCode code: Int) {
        switch code {
        case -1003, -1006: self = .dns  // cannotFindHost, dnsLookupFailed
        case -1206 ... -1200: self = .tls  // secureConnectionFailed, serverCertificate*, clientCertificate*
        case -1001: self = .timeout  // timedOut
        case -1009, -1005: self = .offline  // notConnectedToInternet, networkConnectionLost
        default: self = .other(code)
        }
    }

    /// The value of the event's `reason` property.
    public var eventName: String {
        switch self {
        case .noDeviceID: "no_device_id"
        case .dns: "dns"
        case .tls: "tls"
        case .timeout: "timeout"
        case .offline: "offline"
        case .server(let status): "server_\(status)"
        case .other(let code): "other_\(code)"
        }
    }
}
