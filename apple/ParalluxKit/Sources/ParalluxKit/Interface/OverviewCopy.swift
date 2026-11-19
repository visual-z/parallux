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

/// What a link is doing right now, as the panel and the overview both show
/// it. One rule for both, so they cannot disagree about which link leads.
public enum LinkStanding: Equatable, Sendable {
    /// Switched off.
    case disabled
    /// Takes traffic (分流, 叠加, or the only link).
    case carrying
    /// 主备's leading link.
    case primary
    /// Enabled but waiting: 主备's other links, and 仅备用 links in any mode.
    case standby

    /// - Parameters:
    ///   - enabled: names of the enabled links in priority order.
    ///   - backup: names marked 仅备用.
    ///   - mode: the aggregation mode in effect; nil with fewer than two links.
    /// - Returns: one entry per enabled link. A link without an entry is disabled.
    public static func all(enabled: [String], backup: Set<String>, mode: AggregationMode?) -> [String: LinkStanding] {
        guard let first = enabled.first else { return [:] }
        // The core skips backup-only links while any other is usable; when
        // every link is backup-only the first one takes the traffic anyway.
        let lead = enabled.first { !backup.contains($0) } ?? first
        var standings: [String: LinkStanding] = [:]
        for name in enabled {
            if mode == .failover {
                standings[name] = name == lead ? .primary : .standby
            } else {
                standings[name] = backup.contains(name) && name != lead ? .standby : .carrying
            }
        }
        return standings
    }

    /// The design's 「主」「备」 tag after a link's name.
    public var badge: String? {
        switch self {
        case .primary: "主"
        case .standby: "备"
        case .disabled, .carrying: nil
        }
    }
}
