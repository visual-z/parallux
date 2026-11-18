import Foundation

/// What a `parallux://` (or SFM's `sing-box://`) link asks the app to do.
public enum URLRoute: Equatable, Sendable {
    /// docs/research/aggregation-server-link.md; the whole link is kept for the parser.
    case addAggregationServer(String)
    /// SFM's import-remote-profile link, handed to libbox's parser verbatim.
    case importRemoteProfile(String)
    case connect, disconnect, toggle

    public static func parse(_ url: URL) -> URLRoute? {
        let scheme = url.scheme?.lowercased()
        let host = url.host()?.lowercased()
        switch (scheme, host) {
        case ("parallux", "aggregation-server"): return .addAggregationServer(url.absoluteString)
        case ("parallux", "import-remote-profile"), ("sing-box", "import-remote-profile"): return .importRemoteProfile(url.absoluteString)
        case ("parallux", "connect"): return .connect
        case ("parallux", "disconnect"): return .disconnect
        case ("parallux", "toggle"): return .toggle
        default: return nil
        }
    }
}
