import Foundation

/// sing-box log levels (log/level.go); lower is more severe.
public enum LogLevel: Int, CaseIterable, Identifiable, Comparable, Sendable {
    case panic = 0, fatal, error, warn, info, debug, trace
    public var id: Int { rawValue }
    public static func < (a: LogLevel, b: LogLevel) -> Bool { a.rawValue < b.rawValue }
    public var title: String { "\(self)".uppercased() }
    /// Unknown values are treated as the least severe.
    public init(sing value: Int32) { self = LogLevel(rawValue: Int(value)) ?? .trace }
}

public struct LogEntry: Identifiable, Equatable, Sendable {
    public let id: Int
    public let level: LogLevel
    public let message: String
    public init(id: Int, level: LogLevel, message: String) {
        self.id = id
        self.level = level
        self.message = message
    }
}

public enum LogQuery {
    /// Entries at `level` or more severe whose message contains `text`.
    public static func filter(_ entries: [LogEntry], level: LogLevel, text: String) -> [LogEntry] {
        entries.filter { $0.level <= level && (text.isEmpty || $0.message.localizedCaseInsensitiveContains(text)) }
    }
}

/// The design colours a delay green when fast and red when slow.
public enum DelayGrade: Equatable, Sendable {
    case untested, fast, slow
    /// Why 150 ms: the design's examples put 74 ms green and 168 ms red.
    public static let slowThreshold: Int32 = 150
    public init(milliseconds: Int32) {
        self = milliseconds <= 0 ? .untested : milliseconds < Self.slowThreshold ? .fast : .slow
    }
}

public enum RouteMode {
    public static func title(_ mode: String) -> String {
        switch mode.lowercased() {
        case "rule": "规则"
        case "global": "全局"
        case "direct": "直连"
        default: mode
        }
    }
}

/// One row of the connections table, copied out of libbox's Connection.
public struct ConnectionRow: Identifiable, Equatable, Sendable {
    public var id: String
    public var process: String
    public var destination: String
    public var rule: String
    public var outbound: String
    public var chain: [String]
    public var network: String
    public var uplinkTotal: Int64
    public var downlinkTotal: Int64
    public var createdAt: Date
    public var isClosed: Bool
    /// Bytes per second over the last statistics interval.
    public var uplink: Int64 = 0
    public var downlink: Int64 = 0
    /// sing-box outbound type of `outbound` ("direct", "selector", "vmess"…).
    public var outboundType: String = ""

    public init(id: String, process: String, destination: String, rule: String, outbound: String, chain: [String] = [],
                network: String = "tcp", uplinkTotal: Int64 = 0, downlinkTotal: Int64 = 0, createdAt: Date = Date(), isClosed: Bool = false,
                uplink: Int64 = 0, downlink: Int64 = 0, outboundType: String = "") {
        self.id = id
        self.process = process
        self.destination = destination
        self.rule = rule
        self.outbound = outbound
        self.chain = chain
        self.network = network
        self.uplinkTotal = uplinkTotal
        self.downlinkTotal = downlinkTotal
        self.createdAt = createdAt
        self.isClosed = isClosed
        self.uplink = uplink
        self.downlink = downlink
        self.outboundType = outboundType
    }
}

public enum ConnectionQuery {
    public static func filter(_ rows: [ConnectionRow], text: String) -> [ConnectionRow] {
        guard !text.isEmpty else { return rows }
        return rows.filter { row in
            [row.process, row.destination, row.rule, row.outbound].contains { $0.localizedCaseInsensitiveContains(text) }
        }
    }
}

/// A route rule as shown on the rules page.
public struct RuleSummary: Identifiable, Equatable, Sendable {
    public var id: Int
    /// e.g. "geosite: cn" or "domain_suffix: example.com 等 3 项".
    public var condition: String
    /// e.g. "→ direct", "sniff", "hijack-dns".
    public var action: String
    /// The name sing-box reports in Connection.rule for this rule.
    public var matchKey: String

    public init(id: Int, condition: String, action: String, matchKey: String) {
        self.id = id
        self.condition = condition
        self.action = action
        self.matchKey = matchKey
    }

    /// Fields that are part of the action, not the condition.
    static let actionKeys: Set<String> = ["action", "outbound", "server", "strategy", "method", "no_drop", "rewrite_ttl",
                                          "client_subnet", "invert", "override_address", "override_port", "network_strategy",
                                          "fallback_delay", "udp_disable_domain_unmapping", "udp_connect", "udp_timeout",
                                          "tls_fragment", "tls_record_fragment", "sniffer", "timeout", "type", "mode", "rules"]

    /// Condition fields whose rule items sing-box prints in Connection.rule
    /// (route/rule/rule_default.go); only these form the match key.
    static let matchableKeys: Set<String> = ["inbound", "ip_version", "network", "auth_user", "protocol", "client", "domain",
                                             "domain_suffix", "domain_keyword", "domain_regex", "source_ip_cidr", "ip_cidr",
                                             "source_port", "source_port_range", "port", "port_range", "process_name", "process_path",
                                             "process_path_regex", "package_name", "user", "user_id", "clash_mode", "network_type",
                                             "wifi_ssid", "wifi_bssid", "rule_set"]

    public static func parse(config: String) -> [RuleSummary] {
        guard let root = try? JSONSerialization.jsonObject(with: Data(config.utf8)) as? [String: Any],
              let route = root["route"] as? [String: Any],
              let rules = route["rules"] as? [[String: Any]] else { return [] }
        return rules.enumerated().map { index, rule in
            let action = (rule["action"] as? String) ?? "route"
            let actionText = action == "route" ? "→ " + ((rule["outbound"] as? String) ?? "?") : action
            if rule["type"] as? String == "logical" {
                let mode = (rule["mode"] as? String) ?? "and"
                let count = (rule["rules"] as? [Any])?.count ?? 0
                return RuleSummary(id: index, condition: "逻辑 \(mode)（\(count) 条子规则）", action: actionText, matchKey: "")
            }
            let keys = rule.keys.sorted().filter { !actionKeys.contains($0) }
            let items = keys.compactMap { formatItem($0, rule[$0]) }
            let matchable = keys.filter(matchableKeys.contains).compactMap { formatItem($0, rule[$0]) }
            let condition = items.isEmpty ? "全部流量" : items.joined(separator: " ")
            return RuleSummary(id: index, condition: condition, action: actionText, matchKey: matchable.sorted().joined(separator: " "))
        }
    }

    /// The only items sing-box truncates past three values when printing a
    /// rule (rule_item_domain.go, rule_item_domain_keyword.go, rule_item_cidr.go);
    /// every other item prints its whole list.
    static let truncatedKeys: Set<String> = ["domain", "domain_suffix", "domain_keyword", "ip_cidr", "source_ip_cidr"]

    /// Formats one condition the way sing-box's rule items print themselves
    /// (route/rule/rule_item_*.go): one value bare, a list in brackets, and
    /// for `truncatedKeys` more than three cut to the first three plus "...".
    static func formatItem(_ key: String, _ value: Any?) -> String? {
        let values: [String]
        switch value {
        case let list as [Any]: values = list.map { "\($0)" }
        case let single?: values = ["\(single)"]
        case nil: return nil
        }
        guard !values.isEmpty else { return nil }
        if values.count == 1 { return "\(key)=\(values[0])" }
        if values.count > 3, truncatedKeys.contains(key) { return "\(key)=[\(values[..<3].joined(separator: " "))...]" }
        return "\(key)=[\(values.joined(separator: " "))]"
    }

    /// Splits a Connection.rule string into items, keeping bracketed lists whole.
    static func items(of rule: String) -> [String] {
        var items: [String] = []
        var current = ""
        var depth = 0
        for character in rule {
            if character == "[" { depth += 1 }
            if character == "]" { depth -= 1 }
            if character == " ", depth == 0 {
                if !current.isEmpty { items.append(current) }
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { items.append(current) }
        return items
    }

    /// Connections per rule, keyed by RuleSummary.id. Matches on the set of
    /// items so field order in the profile does not matter; rules without
    /// conditions (and logical rules) are not matched.
    public static func hits(_ rules: [RuleSummary], connections: [ConnectionRow]) -> [Int: Int] {
        var byKey: [String: Int] = [:]
        for rule in rules where !rule.matchKey.isEmpty && byKey[rule.matchKey] == nil {
            byKey[rule.matchKey] = rule.id
        }
        var counts: [Int: Int] = [:]
        for connection in connections where !connection.rule.isEmpty {
            let key = items(of: connection.rule).sorted().joined(separator: " ")
            if let id = byKey[key] { counts[id, default: 0] += 1 }
        }
        return counts
    }
}

/// One outbound group (selector / urltest) as the nodes page shows it.
public struct OutboundGroupModel: Identifiable, Equatable, Sendable {
    public struct Item: Identifiable, Equatable, Sendable {
        public var tag: String
        public var type: String
        /// Milliseconds of the last URL test; 0 when untested.
        public var delay: Int32
        public var id: String { tag }
        public init(tag: String, type: String, delay: Int32) {
            self.tag = tag
            self.type = type
            self.delay = delay
        }
    }

    public var tag: String
    public var type: String
    public var selectable: Bool
    public var selected: String
    public var items: [Item]
    public var id: String { tag }

    public init(tag: String, type: String, selectable: Bool, selected: String, items: [Item]) {
        self.tag = tag
        self.type = type
        self.selectable = selectable
        self.selected = selected
        self.items = items
    }

    /// "手动选择 · 8 个节点" / "自动选择延迟最低 · 1 个节点"
    public var subtitle: String {
        let kind = type == "urltest" ? "自动选择延迟最低" : selectable ? "手动选择" : type
        return "\(kind) · \(items.count) 个节点"
    }
}

/// One point of the traffic sparkline.
public struct RatePoint: Equatable, Sendable {
    public var uplink: Int64
    public var downlink: Int64
    public init(uplink: Int64, downlink: Int64) {
        self.uplink = uplink
        self.downlink = downlink
    }
}
