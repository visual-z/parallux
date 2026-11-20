import Foundation

/// The overview's strings, as design v0.2 writes them (the design is one of
/// the allowed copy sources, docs/design/copy-and-style.md).
public enum OverviewCopy {
    /// Window subtitle: 「3 条线路 · 叠加 · 经东京 VPS」. Only 叠加 goes through
    /// the aggregation server; one link has no aggregation mode at all.
    /// `problem`: an error the status line wants shown (a failed action, a
    /// core the app cannot read). It wins: the subtitle is the only place the
    /// running overview has for it.
    public static func subtitle(links: Int, mode: AggregationMode?, server: String?, problem: String? = nil) -> String {
        if let problem, !problem.isEmpty { return problem }
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

    /// Under an exit's name: its rate. How the aggregation mode carries it
    /// is in the diagram's heading and the window's subtitle already; saying
    /// it again under every exit was noise (the author, 2026-11-20).
    public static func exitDetail(rate: Int64) -> String {
        RateFormat.bitsPerSecond(rate)
    }

    /// 「东京 VPS → HK‑03」 when the node is reached through the aggregation server.
    public static func exitName(node: String, server: String?, mode: AggregationMode?) -> String {
        guard mode == .bond, let server, !server.isEmpty else { return node }
        return "\(server) → \(node)"
    }

    /// 「命中最多：geosite‑cn → 直连（61%）」 for the route mode card.
    /// The rule most connections hit, where they went and its share of all
    /// connections. A connection carries the rule it matched (libbox
    /// Connection.rule: the condition only), so this needs nothing from the
    /// profile. nil when no connection matched a rule (only route.final).
    public static func topRule(_ connections: [ConnectionRow]) -> String? {
        // Without DNS lookups (the connections page's 隐藏 DNS test): on a
        // profile that routes DNS by rule they would nearly always win, and
        // the line is about where traffic goes.
        let connections = connections.filter { !ConnectionQuery.isDNS($0) }
        var byRule: [String: [ConnectionRow]] = [:]
        for connection in connections where !connection.rule.isEmpty { byRule[connection.rule, default: []].append(connection) }
        // Most hits first; a tie goes to the smaller text so the line does not flicker.
        guard let (rule, hits) = byRule.min(by: { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }) else { return nil }
        var exits: [String: Int] = [:]
        for hit in hits {
            exits[FlowSummary.directTypes.contains(hit.outboundType) ? FlowSummary.directName : hit.outbound, default: 0] += 1
        }
        let exit = exits.min { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }?.key ?? ""
        // A single rule set reads as its name (design: 「geosite‑cn」); anything
        // else keeps sing-box's own `key=value` form.
        let single = "rule_set="
        let name = rule.hasPrefix(single) && !rule.contains(" ") && !rule.contains("[") ? String(rule.dropFirst(single.count)) : rule
        let share = Int((Double(hits.count) / Double(connections.count) * 100).rounded())
        return exit.isEmpty ? "命中最多：\(name)（\(share)%）" : "命中最多：\(name) → \(exit)（\(share)%）"
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

    /// Follows the core's own order (core/aggregate/order.go, linkOrder):
    /// healthy primaries, then healthy backup-only links, then unhealthy ones.
    /// - Parameters:
    ///   - enabled: names of the links in use, in priority order.
    ///   - backup: names marked 仅备用.
    ///   - unhealthy: names the core's health probe currently fails.
    ///   - mode: the aggregation mode in effect; nil with fewer than two links.
    /// - Returns: one entry per name in `enabled`. A link without an entry is not in use.
    public static func all(enabled: [String], backup: Set<String>, unhealthy: Set<String> = [], mode: AggregationMode?) -> [String: LinkStanding] {
        let primaries = enabled.filter { !unhealthy.contains($0) && !backup.contains($0) }
        let spares = enabled.filter { !unhealthy.contains($0) && backup.contains($0) }
        // The link a new connection is tried on first.
        guard let lead = primaries.first ?? spares.first ?? enabled.first else { return [:] }
        var standings: [String: LinkStanding] = [:]
        for name in enabled {
            if mode == .failover {
                standings[name] = name == lead ? .primary : .standby
            } else {
                // 分流 and 叠加 use every healthy primary; with none, the lead alone.
                standings[name] = name == lead || primaries.contains(name) ? .carrying : .standby
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

/// Copy of the connections page (design v0.2).
public enum ConnectionCopy {
    /// How long a connection has been open: 「42 秒」「4 分 12 秒」「2 小时 5 分」.
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = seconds.isFinite && seconds > 0 ? Int(seconds) : 0
        if total < 60 { return "\(total) 秒" }
        if total < 3600 { return "\(total / 60) 分 \(total % 60) 秒" }
        return "\(total / 3600) 小时 \(total / 60 % 60) 分"
    }
}

/// Where a row dragged onto another row of a list ends up (the design's
/// lists: links and profiles are ordered by dragging).
public enum ListReorder {
    /// The dragged row takes the place of the row it was dropped on: dragged
    /// down it lands after the target, dragged up before it. Unknown rows and
    /// a drop on itself change nothing.
    public static func moving(_ id: String, onto target: String, in ids: [String]) -> [String] {
        guard id != target, let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: target) else { return ids }
        var result = ids
        result.remove(at: from)
        result.insert(id, at: to)
        return result
    }

    /// The same move as `move(fromOffsets:toOffset:)` takes it; nil when nothing moves.
    public static func offsets(moving id: String, onto target: String, in ids: [String]) -> (from: Int, to: Int)? {
        guard id != target, let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: target) else { return nil }
        return (from, to > from ? to + 1 : to)
    }
}
