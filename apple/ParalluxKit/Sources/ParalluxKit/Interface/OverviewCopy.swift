import Foundation

/// The overview's strings, as design v0.2 writes them (the design is one of
/// the allowed copy sources, docs/design/copy-and-style.md).
public enum OverviewCopy {
    /// Window subtitle: 「3 条线路 · 叠加 · 经东京 VPS」. Only 叠加 goes through
    /// the aggregation server; one link has no aggregation mode at all.
    public static func subtitle(links: Int, mode: AggregationMode?, server: String?) -> String {
        var parts = ["\(links) 条线路"]
        if let mode { parts.append(mode.title) }
        if mode == .bond, let server, !server.isEmpty {
            // 「经东京」 but 「经 Tokyo」: a space only before Latin text.
            let latin = server.unicodeScalars.first.map { $0.isASCII && $0.properties.isAlphabetic || ("0"..."9").contains($0) } ?? false
            parts.append(latin ? "经 \(server)" : "经\(server)")
        }
        return parts.joined(separator: " · ")
    }

    /// Under a link's name. `standby`: the link is enabled but only waits
    /// (主备's spare links, 仅备用 links).
    public static func linkDetail(enabled: Bool, standby: Bool, rate: Int64) -> String {
        if !enabled { return "已停用" }
        if standby, rate <= 0 { return "待命" }
        return RateFormat.bitsPerSecond(rate)
    }

    /// Under an exit's name: how the aggregation mode carries it, then the rate.
    public static func exitDetail(direct: Bool, mode: AggregationMode?, rate: Int64) -> String {
        let speed = RateFormat.bitsPerSecond(rate)
        guard !direct, let mode else { return speed }
        let how = switch mode {
        case .bond: "叠加后转发"
        case .balance: "按连接分到各线路"
        case .failover: "仅主线路"
        }
        return "\(how) · \(speed)"
    }

    /// 「东京 VPS → HK‑03」 when the node is reached through the aggregation server.
    public static func exitName(node: String, server: String?, mode: AggregationMode?) -> String {
        guard mode == .bond, let server, !server.isEmpty else { return node }
        return "\(server) → \(node)"
    }

    /// Above the centre bar: 「叠加 · 731 Mbps」.
    public static func centre(mode: AggregationMode?, rate: Int64) -> String {
        let speed = RateFormat.bitsPerSecond(rate)
        return mode.map { "\($0.title) · \(speed)" } ?? speed
    }
}

/// What a link is doing right now, as the panel and the overview both show it.
public enum LinkStanding: Equatable, Sendable {
    case disabled, carrying, primary, standby

    public static func all(enabled: [String], backup: Set<String>, mode: AggregationMode?) -> [String: LinkStanding] { [:] }

    public var badge: String? { nil }
}
