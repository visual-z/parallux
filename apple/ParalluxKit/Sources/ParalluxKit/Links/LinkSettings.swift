import Foundation

/// What the links page and the aggregation switch persist.
public struct LinkSettings: Codable, Equatable, Sendable {
    public var preferences = LinkPreferences()
    public var mode: AggregationMode = .bond
    /// The aggregation server used for 叠加 (AggregationServer.id), if any.
    public var bondServerID: UUID?

    public init() {}

    public static let defaultsKey = "parallux.links"

    public static func load(from defaults: UserDefaults) -> LinkSettings { LinkSettings() }
    public func save(to defaults: UserDefaults) {}
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
        ([], [])
    }
}

/// 「如果两条线路背后是同一条宽带，这里会提示你：叠加不会更快」(design, links page).
public enum SharedEgress {
    /// Egress IPs per interface name, as the probe saw them.
    public static func warning(links: [LinkInterface], egress: [String: String]) -> String? { nil }
}
