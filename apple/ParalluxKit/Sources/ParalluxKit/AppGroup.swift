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
    /// without one (unsigned builds have an empty team prefix).
    public static func identifier(in bundle: Bundle = .main) -> String? {
        resolve(bundle.object(forInfoDictionaryKey: infoPlistKey) as? String)
    }

    /// Exposed for tests: an unexpanded or empty value means "no group".
    static func resolve(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty, !raw.contains("$(") else { return nil }
        return raw
    }
}
