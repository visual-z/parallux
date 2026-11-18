import Foundation

/// Everything the app passes to the extension when it starts the tunnel.
///
/// The extension cannot read the app's container (it runs as root), so the
/// selected configuration travels inside the start options, and the extension
/// persists them for on-demand restarts. One Codable value under one key keeps
/// the two sides from drifting key by key (SFM writes each NSNumber by hand).
public struct TunnelStartOptions: Codable, Equatable, Sendable {
    public var configContent: String
    /// NEPacketTunnelNetworkSettings knobs, same set as SFM's overrides.
    public var includeAllNetworks = false
    public var excludeLocalNetworks = false
    public var excludeAPNs = false
    public var excludeDeviceCommunication = false
    public var enforceRoutes = false
    public var systemProxyEnabled = true
    public var excludeDefaultRoute = false
    public var autoRouteUseSubRangesByDefault = false

    public init(configContent: String) {
        self.configContent = configContent
    }

    /// Key under which the encoded options sit in startVPNTunnel(options:).
    public static let optionsKey = "parallux.startOptions"

    public func encoded() throws -> [String: NSObject] {
        [:]
    }

    public static func decode(_ options: [String: NSObject]?) throws -> TunnelStartOptions? {
        nil
    }
}
