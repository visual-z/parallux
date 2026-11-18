import Foundation

/// What a `parallux://` (or SFM's `sing-box://`) link asks the app to do.
public enum URLRoute: Equatable, Sendable {
    /// docs/research/aggregation-server-link.md; the whole link is kept for the parser.
    case addAggregationServer(String)
    /// SFM's import-remote-profile link, handed to libbox's parser verbatim.
    case importRemoteProfile(String)
    case connect, disconnect, toggle

    public static func parse(_ url: URL) -> URLRoute? { nil }
}
