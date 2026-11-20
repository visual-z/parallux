/// How traffic is spread over the active links (CONTEXT.md: 分流 / 叠加 / 主备).
public enum AggregationMode: String, CaseIterable, Identifiable, Sendable, Codable {
    /// Per-connection load balancing across links. Needs no server; a single
    /// connection still uses one link.
    case balance
    /// One connection split across all links and reassembled on the user's
    /// own aggregation server. The only mode that speeds up a single stream.
    case bond
    /// Only the primary link carries traffic; the others take over on failure.
    case failover

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .balance: "分流"
        case .bond: "叠加"
        case .failover: "主备"
        }
    }

    /// Bonding is the only mode that needs an aggregation server.
    public var requiresAggregationServer: Bool { self == .bond }
}
