import Foundation

/// Per-link counters of one aggregate outbound (core/aggregate GroupStat).
public struct LinkGroupStat: Codable, Equatable, Sendable {
    public struct Link: Codable, Equatable, Sendable {
        public var tag: String
        public var healthy: Bool
        public var backup: Bool
        public var upload: Int64
        public var download: Int64
        public var active: Int64
    }

    public var tag: String
    public var mode: String
    public var links: [Link]

    public static func decode(_ json: String) -> [LinkGroupStat] {
        (try? JSONDecoder().decode([LinkGroupStat].self, from: Data(json.utf8))) ?? []
    }
}

/// Turns two counter snapshots into per-link rates (bytes per second).
public enum LinkRates {
    public struct Rate: Equatable, Sendable {
        public var upload: Int64
        public var download: Int64
        public var total: Int64 { upload &+ download }
    }

    /// Keyed by link outbound tag, summed over every aggregate outbound:
    /// each group keeps its own counters for the same links, so differences
    /// are taken per (group, link) and only then added.
    /// Counter resets (a reloaded core) and
    /// groups new in this sample read as 0, not negative.
    public static func rates(previous: [LinkGroupStat], current: [LinkGroupStat], interval: TimeInterval) -> [String: Rate] {
        guard interval > 0 else { return [:] }
        struct Key: Hashable { let group: String, link: String }
        var before: [Key: LinkGroupStat.Link] = [:]
        for group in previous { for link in group.links { before[Key(group: group.tag, link: link.tag)] = link } }
        var up: [String: Int64] = [:]
        var down: [String: Int64] = [:]
        for group in current {
            for link in group.links {
                let old = before[Key(group: group.tag, link: link.tag)]
                up[link.tag, default: 0] += max(0, link.upload - (old?.upload ?? link.upload))
                down[link.tag, default: 0] += max(0, link.download - (old?.download ?? link.download))
            }
        }
        var result: [String: Rate] = [:]
        for tag in up.keys {
            result[tag] = Rate(upload: Int64(Double(up[tag] ?? 0) / interval), download: Int64(Double(down[tag] ?? 0) / interval))
        }
        return result
    }
}
