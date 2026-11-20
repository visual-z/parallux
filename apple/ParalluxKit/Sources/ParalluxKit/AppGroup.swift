import Foundation

/// Identifiers shared by the app and the packet tunnel system extension.
///
/// On macOS the App Group must carry the team prefix, and a system extension's
/// NEMachServiceName must sit inside that group. The team prefix is only known
/// at build time ($(TeamIdentifierPrefix)), so both targets write the resolved
/// group into their Info.plist under `ParalluxAppGroup` and read it from there.
public enum AppGroup {
    public static let infoPlistKey = "ParalluxAppGroup"

    /// The App Group of the running bundle, or nil when the bundle was built
    /// without a team (unsigned builds expand the team prefix to "", leaving
    /// the bare bundle id, which macOS does not accept as a group).
    public static func identifier(in bundle: Bundle = .main) -> String? {
        resolve(bundle.object(forInfoDictionaryKey: infoPlistKey) as? String)
    }

    /// Exposed for tests. A usable group is "<Team ID>.<rest>", where a Team
    /// ID is ten uppercase letters or digits; anything else means no group.
    static func resolve(_ raw: String?) -> String? {
        guard let raw, let dot = raw.firstIndex(of: ".") else { return nil }
        let team = raw[..<dot]
        let isTeamID = team.count == 10 && team.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) }
        guard isTeamID, raw.index(after: dot) < raw.endIndex else { return nil }
        return raw
    }
}
