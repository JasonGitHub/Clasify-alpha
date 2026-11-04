/// Picks the Spotify desktop app on this Mac from the account's Spotify Connect devices.
/// The app's Spotify player uses it. It is plain Swift here so that it runs in the Linux tests.
public enum SpotifyAppDevice {
    /// One Connect device. The list never holds Clasify's own device.
    public struct Candidate: Equatable, Sendable {
        public let id: String, name: String, type: String
        public init(id: String, name: String, type: String) { self.id = id; self.name = name; self.type = type }
    }

    public enum Pick: Equatable, Sendable {
        case found(id: String)
        /// No computer device yet, for example while Spotify starts.
        case none
        /// Several computers, and none has this Mac's name.
        case ambiguous
    }

    /// A computer device with this Mac's name, else the only computer device when
    /// `allowOnlyComputer` is true. Names are compared without case, and with ’ and ' as the
    /// same letter. Right after Clasify launched Spotify, this Mac's device is not in the list
    /// yet, and the only computer can be another one, such as a work PC. So the caller allows
    /// the fallback only when Spotify already ran here, or after some seconds with no name match.
    public static func pick(_ devices: [Candidate], computerName: String?, allowOnlyComputer: Bool) -> Pick {
        let computers = devices.filter { $0.type == "COMPUTER" }
        if let name = computerName.map(normalized), let match = computers.first(where: { normalized($0.name) == name }) {
            return .found(id: match.id)
        }
        switch computers.count {
        case 0: return .none
        case 1: return allowOnlyComputer ? .found(id: computers[0].id) : .none
        default: return allowOnlyComputer ? .ambiguous : .none
        }
    }

    static func normalized(_ name: String) -> String {
        name.replacingOccurrences(of: "\u{2019}", with: "'").lowercased()
    }
}
