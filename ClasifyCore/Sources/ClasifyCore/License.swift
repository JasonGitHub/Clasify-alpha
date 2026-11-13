/// A license of the Rust parts that Clasify links (card BF, change 213). `License.all`, one row
/// of the Licenses list each, is made by scripts/licenses.py from LibrespotBridge/Cargo.lock.
public struct License: Sendable, Equatable {
    public let name: String
    /// The license text, then the names of the parts under it, one screen line each.
    public let lines: [String]
}

extension AppState {
    /// The license screen shows this many lines of 14 pt; its name takes the first 2.
    public static let licenseShownLines = 14, licenseNameLines = 2

    /// The last step of license `i`'s page: its last line is on the screen's last line.
    public static func licenseSteps(_ i: Int) -> Int {
        License.all.indices.contains(i) ? max(0, License.all[i].lines.count + licenseNameLines - licenseShownLines) : 0
    }
}
