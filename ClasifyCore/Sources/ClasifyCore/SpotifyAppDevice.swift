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

    /// A computer device with this Mac's name, else the only computer device that is not in
    /// `excluding`. Names are compared without case, and with ’ and ' as the same letter.
    ///
    /// When Clasify launches Spotify here, it passes the devices that were there before the
    /// launch. Another machine, such as a work PC, is then never taken for this Mac: only a
    /// computer that came after the launch can be this Mac's Spotify app.
    public static func pick(_ devices: [Candidate], computerName: String?, excluding: Set<String> = []) -> Pick {
        let computers = devices.filter { $0.type == "COMPUTER" }
        if let name = computerName.map(normalized), let match = computers.first(where: { normalized($0.name) == name }) {
            return .found(id: match.id)
        }
        let new = computers.filter { !excluding.contains($0.id) }
        switch new.count {
        case 0: return .none
        case 1: return .found(id: new[0].id)
        default: return .ambiguous
        }
    }

    static func normalized(_ name: String) -> String {
        name.replacingOccurrences(of: "\u{2019}", with: "'").lowercased()
    }
}
