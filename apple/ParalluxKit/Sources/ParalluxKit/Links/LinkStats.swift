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

    /// Keyed by link outbound tag. Counter resets (a reloaded core) read as 0, not negative.
    public static func rates(previous: [LinkGroupStat], current: [LinkGroupStat], interval: TimeInterval) -> [String: Rate] {
        guard interval > 0 else { return [:] }
        var before: [String: LinkGroupStat.Link] = [:]
        for group in previous { for link in group.links { before[link.tag] = link } }
        var result: [String: Rate] = [:]
        for group in current {
            for link in group.links {
                let old = before[link.tag]
                let up = max(0, link.upload - (old?.upload ?? link.upload))
                let down = max(0, link.download - (old?.download ?? link.download))
                result[link.tag] = Rate(upload: Int64(Double(up) / interval), download: Int64(Double(down) / interval))
            }
        }
        return result
    }
}
