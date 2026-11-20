import Foundation

/// What the links page and the aggregation switch persist.
public struct LinkSettings: Codable, Equatable, Sendable {
    public var preferences = LinkPreferences()
    public var mode: AggregationMode = .bond
    /// The aggregation server used for 叠加 (AggregationServer.id), if any.
    public var bondServerID: UUID?
    /// 聚合 / 代理 as last run; missing in old data = both on.
    public var switches: ConnectionSwitches = .both

    public init() {}

    public static let defaultsKey = "parallux.links"

    public static func load(from defaults: UserDefaults) -> LinkSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let settings = try? JSONDecoder().decode(LinkSettings.self, from: data) else { return LinkSettings() }
        return settings
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }

    // Missing keys decode to their defaults.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preferences = try container.decodeIfPresent(LinkPreferences.self, forKey: .preferences) ?? LinkPreferences()
        mode = try container.decodeIfPresent(AggregationMode.self, forKey: .mode) ?? .bond
        bondServerID = try container.decodeIfPresent(UUID.self, forKey: .bondServerID)
        switches = try container.decodeIfPresent(ConnectionSwitches.self, forKey: .switches) ?? .both
    }
}

/// The two columns of the flow diagram, as rates.
public enum LinkFlow {
    public struct Node: Equatable, Sendable {
        public var id: String
        public var title: String
        public var detail: String
        public var rate: Int64
        public init(id: String, title: String, detail: String, rate: Int64) {
            self.id = id
            self.title = title
            self.detail = detail
            self.rate = rate
        }
    }

    /// - Parameters:
    ///   - links: enabled links in priority order.
    ///   - linkRates: bytes per second per link outbound tag (LinkRates).
    ///   - totalRate: the core's total rate, used when there is one link and no per-link counters.
    ///   - exits: FlowSummary.exits of the live connections.
    public static func columns(links: [LinkInterface], linkRates: [String: LinkRates.Rate], totalRate: Int64,
                               exits: [FlowSummary.Exit]) -> (left: [Node], right: [Node]) {
        let left: [Node] = links.map { link in
            let measured = linkRates[ProfileComposer.linkTag(link.name)]
            // No counters at all (one link, or the first second before the
            // aggregate has dialed): split the core's total evenly so the
            // diagram still shows traffic. Any counter present wins.
            let anyMeasured = links.contains { linkRates[ProfileComposer.linkTag($0.name)] != nil }
            let rate = measured?.total ?? (anyMeasured ? 0 : totalRate / Int64(max(links.count, 1)))
            return Node(id: link.name, title: link.title, detail: "\(link.displayName) · \(link.name)", rate: max(0, rate))
        }
        let right = exits.map { Node(id: $0.name, title: $0.name, detail: "", rate: $0.rate) }
        return (left, right)
    }
}

/// 「如果两条线路背后是同一条宽带，这里会提示你：叠加不会更快」(design, links page).
public enum SharedEgress {
    /// Egress IPs per interface name, as the probe saw them.
    public static func warning(links: [LinkInterface], egress: [String: String]) -> String? {
        var byIP: [String: [LinkInterface]] = [:]
        for link in links {
            if let ip = egress[link.name], !ip.isEmpty { byIP[ip, default: []].append(link) }
        }
        guard let shared = byIP.values.filter({ $0.count > 1 }).max(by: { $0.count < $1.count }) else { return nil }
        let names = shared.map { "「\($0.kind.title)」" }.joined(separator: "和")
        return "\(names)走的是同一个公网出口，背后可能是同一条宽带：叠加不会更快，分流也不会多出带宽。"
    }
}

extension LinkPreferences {
    /// Whether moving from `old` to `new` available links changes the enabled
    /// set the core was composed with (a link plugged in or pulled out).
    public func needsRecomposition(from old: [LinkInterface], to new: [LinkInterface]) -> Bool {
        Set(enabled(old).map(\.name)) != Set(enabled(new).map(\.name))
    }
}
