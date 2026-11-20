import Foundation

/// The root helper's versioned Mach service (Base.xcconfig
/// PARALLUX_HELPER_MACH_SERVICE), read from the caller's Info.plist.
public enum HelperMachService {
    public static let infoPlistKey = "ParalluxHelperMachService"

    public static func name(in bundle: Bundle = .main) -> String? {
        resolve(bundle.object(forInfoDictionaryKey: infoPlistKey) as? String, appGroup: AppGroup.identifier(in: bundle))
    }

    /// "<App Group>.helper.<version>…", or nil for unsigned builds (no group).
    static func resolve(_ raw: String?, appGroup: String?) -> String? {
        guard let raw, let appGroup else { return nil }
        let prefix = appGroup + ".helper."
        guard raw.hasPrefix(prefix), raw.count > prefix.count else { return nil }
        return raw
    }

    /// A client for the running bundle's helper, or nil when unsigned.
    public static func client(in bundle: Bundle = .main) -> HelperXPCClient? {
        name(in: bundle).map { HelperXPCClient(machServiceName: $0) }
    }
}
