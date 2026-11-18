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
    /// SFM #105: the extension's memory limit in MB; 0 leaves the OOM killer off.
    public var memoryLimitMB = 0

    public init(configContent: String) {
        self.configContent = configContent
    }

    // Missing keys (options persisted by an older build) decode to defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        configContent = try c.decode(String.self, forKey: .configContent)
        includeAllNetworks = try c.decodeIfPresent(Bool.self, forKey: .includeAllNetworks) ?? false
        excludeLocalNetworks = try c.decodeIfPresent(Bool.self, forKey: .excludeLocalNetworks) ?? false
        excludeAPNs = try c.decodeIfPresent(Bool.self, forKey: .excludeAPNs) ?? false
        excludeDeviceCommunication = try c.decodeIfPresent(Bool.self, forKey: .excludeDeviceCommunication) ?? false
        enforceRoutes = try c.decodeIfPresent(Bool.self, forKey: .enforceRoutes) ?? false
        systemProxyEnabled = try c.decodeIfPresent(Bool.self, forKey: .systemProxyEnabled) ?? true
        excludeDefaultRoute = try c.decodeIfPresent(Bool.self, forKey: .excludeDefaultRoute) ?? false
        autoRouteUseSubRangesByDefault = try c.decodeIfPresent(Bool.self, forKey: .autoRouteUseSubRangesByDefault) ?? false
        memoryLimitMB = 0
    }

    /// Key under which the encoded options sit in startVPNTunnel(options:).
    public static let optionsKey = "parallux.startOptions"

    public func encoded() throws -> [String: NSObject] {
        [Self.optionsKey: try JSONEncoder().encode(self) as NSData]
    }

    /// nil when the dictionary carries no Parallux options (an on-demand start
    /// by the system passes none; the extension then uses its persisted copy).
    public static func decode(_ options: [String: NSObject]?) throws -> TunnelStartOptions? {
        guard let data = options?[optionsKey] as? Data else { return nil }
        return try JSONDecoder().decode(TunnelStartOptions.self, from: data)
    }

    /// The extension persists the last options as plain JSON.
    public func json() throws -> Data { try JSONEncoder().encode(self) }
    public static func fromJSON(_ data: Data) throws -> TunnelStartOptions {
        try JSONDecoder().decode(TunnelStartOptions.self, from: data)
    }
}
