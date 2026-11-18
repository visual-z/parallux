import Foundation

/// Network Extension knobs and profile overrides (settings › 隧道), same set as SFM.
public struct TunnelSettings: Codable, Equatable, Sendable {
    public var includeAllNetworks = false
    public var excludeLocalNetworks = false
    public var excludeAPNs = false
    public var excludeDeviceCommunication = false
    public var enforceRoutes = false
    public var systemProxyEnabled = true
    public var excludeDefaultRoute = false
    public var autoRouteUseSubRangesByDefault = false
    public init() {}
}

/// Everything the settings window persists. One Codable value under one
/// UserDefaults key, so adding a field never needs a migration: missing keys
/// decode to their defaults.
public struct AppSettings: Codable, Equatable, Sendable {
    public var showRateInMenuBar = false
    public var keepInMenuBarAfterClose = true
    /// Design default 叠加; applies once aggregation exists (M3).
    public var defaultAggregationMode: AggregationMode = .bond
    public var tunnel = TunnelSettings()
    public var onDemandEnabled = false
    public var onDemandRules: [OnDemandRuleModel] = []

    public init() {}

    public static let defaultsKey = "parallux.settings"

    public static func load(from defaults: UserDefaults) -> AppSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return settings
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }

    /// The start options for `content` under these settings.
    public func startOptions(content: String) -> TunnelStartOptions {
        var options = TunnelStartOptions(configContent: content)
        options.includeAllNetworks = tunnel.includeAllNetworks
        options.excludeLocalNetworks = tunnel.excludeLocalNetworks
        options.excludeAPNs = tunnel.excludeAPNs
        options.excludeDeviceCommunication = tunnel.excludeDeviceCommunication
        options.enforceRoutes = tunnel.enforceRoutes
        options.systemProxyEnabled = tunnel.systemProxyEnabled
        options.excludeDefaultRoute = tunnel.excludeDefaultRoute
        options.autoRouteUseSubRangesByDefault = tunnel.autoRouteUseSubRangesByDefault
        return options
    }

    // Missing keys decode to defaults, so older stored settings keep working.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        showRateInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showRateInMenuBar) ?? defaults.showRateInMenuBar
        keepInMenuBarAfterClose = try container.decodeIfPresent(Bool.self, forKey: .keepInMenuBarAfterClose) ?? defaults.keepInMenuBarAfterClose
        defaultAggregationMode = try container.decodeIfPresent(AggregationMode.self, forKey: .defaultAggregationMode) ?? defaults.defaultAggregationMode
        tunnel = try container.decodeIfPresent(TunnelSettings.self, forKey: .tunnel) ?? defaults.tunnel
        onDemandEnabled = try container.decodeIfPresent(Bool.self, forKey: .onDemandEnabled) ?? defaults.onDemandEnabled
        onDemandRules = try container.decodeIfPresent([OnDemandRuleModel].self, forKey: .onDemandRules) ?? defaults.onDemandRules
    }
}

/// One on-demand rule (settings › 按需连接); SFM's OnDemandRule model.
public struct OnDemandRuleModel: Codable, Equatable, Identifiable, Sendable {
    public enum Match: Codable, Equatable, Sendable {
        case anyNetwork
        case wifi(ssid: String)
        case probe(url: String)
    }

    public enum Action: String, Codable, CaseIterable, Sendable {
        case connect, disconnect
    }

    public var id = UUID()
    public var match: Match
    public var action: Action

    public init(match: Match, action: Action) {
        self.match = match
        self.action = action
    }

    /// nil when valid; otherwise what to fix.
    public var problem: String? {
        switch match {
        case .anyNetwork:
            return nil
        case let .wifi(ssid):
            return ssid.trimmingCharacters(in: .whitespaces).isEmpty ? "请填写 Wi‑Fi 名称" : nil
        case let .probe(url):
            guard let parsed = URL(string: url), let scheme = parsed.scheme?.lowercased(),
                  ["http", "https"].contains(scheme), parsed.host() != nil else { return "探测地址要以 http:// 或 https:// 开头" }
            return nil
        }
    }

    public var summary: String {
        let condition: String
        switch match {
        case .anyNetwork: condition = "任何网络"
        case let .wifi(ssid): condition = "Wi‑Fi 名称是「\(ssid)」"
        case let .probe(url): condition = "探测 \(url) 返回 200"
        }
        return "\(condition) · 动作：\(action == .connect ? "连接" : "断开")"
    }
}
