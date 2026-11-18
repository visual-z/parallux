import Foundation

/// The extension's versioned Mach service (Base.xcconfig
/// PARALLUX_TUNNEL_MACH_SERVICE), read from Info.plist like the App Group.
public enum MachService {
    public static let infoPlistKey = "ParalluxTunnelMachService"

    public static func name(in bundle: Bundle = .main) -> String? {
        resolve(bundle.object(forInfoDictionaryKey: infoPlistKey) as? String,
                appGroup: AppGroup.identifier(in: bundle))
    }

    /// A usable name is "<App Group>.tunnel.<version>": macOS only lets a
    /// system extension register Mach services inside its App Group, and the
    /// version suffix keeps the app off a replaced extension's stale endpoint.
    static func resolve(_ raw: String?, appGroup: String?) -> String? {
        raw
    }
}
