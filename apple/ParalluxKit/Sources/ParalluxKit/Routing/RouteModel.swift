import Foundation

/// One route rule of a profile, as the routing page shows it.
public struct RouteRule: Equatable, Identifiable, Sendable {
    /// Position in route.rules (0-based).
    public var index: Int
    /// Condition summary in sing-box's print format (RuleSummary.matchKey), or "" for logical rules.
    public var condition: String
    /// Raw condition items for naming (key → values).
    public var items: [String: [String]]
    /// The outbound tag for route actions; nil for sniff, hijack-dns, reject…
    public var outbound: String?
    public var action: String
    public var id: Int { index }

    /// What to show under the name: the match key, or every condition item
    /// for rules sing-box does not print (ip_is_private, logical rules).
    public var displayCondition: String {
        if !condition.isEmpty { return condition }
        let parts = items.keys.sorted().compactMap { key -> String? in
            guard let values = items[key], !values.isEmpty else { return nil }
            return values.count == 1 ? "\(key)=\(values[0])" : "\(key)=[\(values.joined(separator: " "))]"
        }
        return parts.isEmpty ? "规则 \(index + 1)" : parts.joined(separator: " ")
    }

    public init(index: Int, condition: String, items: [String: [String]], outbound: String?, action: String) {
        self.index = index
        self.condition = condition
        self.items = items
        self.outbound = outbound
        self.action = action
    }
}

/// Rules and route.final of a profile.
public struct RouteProfile: Equatable, Sendable {
    public var rules: [RouteRule]
    public var final: String?
    public init(rules: [RouteRule], final: String?) {
        self.rules = rules
        self.final = final
    }

    public static func parse(_ config: String) -> RouteProfile {
        guard let root = (try? JSONSerialization.jsonObject(with: Data(config.utf8))) as? [String: Any],
              let route = root["route"] as? [String: Any] else { return RouteProfile(rules: [], final: nil) }
        let summaries = RuleSummary.parse(config: config)
        let raw = (route["rules"] as? [[String: Any]]) ?? []
        let rules: [RouteRule] = raw.enumerated().map { index, rule in
            let action = (rule["action"] as? String) ?? "route"
            var items: [String: [String]] = [:]
            for (key, value) in rule where !RuleSummary.actionKeys.contains(key) {
                switch value {
                case let list as [Any]: items[key] = list.map { "\($0)" }
                case let bool as Bool: items[key] = [bool ? "true" : "false"]
                default: items[key] = ["\(value)"]
                }
            }
            let outbound = action == "route" ? rule["outbound"] as? String : nil
            let condition = index < summaries.count ? summaries[index].matchKey : ""
            return RouteRule(index: index, condition: condition, items: items, outbound: outbound, action: action)
        }
        return RouteProfile(rules: rules, final: route["final"] as? String)
    }
}

/// An exit followed through its groups: proxy › DE Auto › DE-1 AnyTLS.
public struct ExitChain: Equatable, Sendable {
    public enum Ending: Equatable, Sendable {
        case node
        case cycle
        case tooDeep
        case missing(String)
    }

    public var hops: [String]
    public var ending: Ending
    public var last: String? { hops.last }

    /// Why 8: real profiles nest two or three levels; deeper is a mistake or a cycle.
    public static let maxDepth = 8

    public init(hops: [String], ending: Ending) {
        self.hops = hops
        self.ending = ending
    }

    /// Follows `selected` of each group from `start` until a non-group outbound.
    public static func flatten(_ start: String, groups: [OutboundGroupModel], outbounds: Set<String>) -> ExitChain {
        let byTag = Dictionary(groups.map { ($0.tag, $0) }, uniquingKeysWith: { first, _ in first })
        var hops = [start]
        var current = start
        while true {
            guard outbounds.contains(current) || byTag[current] != nil else { return ExitChain(hops: hops, ending: .missing(current)) }
            guard let group = byTag[current], !group.selected.isEmpty else { return ExitChain(hops: hops, ending: .node) }
            let next = group.selected
            if hops.contains(next) { return ExitChain(hops: hops, ending: .cycle) }
            guard hops.count <= maxDepth else { return ExitChain(hops: hops, ending: .tooDeep) }
            hops.append(next)
            current = next
        }
    }
}

/// Every exit's flattened chain, computed once for the current groups
/// (docs/tasks/perf-routing-relayout.md).
public struct ExitChains: Equatable, Sendable {
    public init(outboundTags: [String], groups: [OutboundGroupModel], exits: [String]) {}
    public func chain(_ exit: String) -> ExitChain? { nil }
}

/// A traffic class on the route map: one rule (or route.final) and its live rate.
public struct TrafficClass: Equatable, Identifiable, Sendable {
    public var id: String
    public var ruleIndex: Int?
    public var name: String
    public var condition: String
    public var exit: String
    /// Bytes per second of the connections that matched it.
    public var rate: Int64
    public var connections: Int
    public var overridden: Bool
}

public struct RouteMap: Equatable, Sendable {
    public var classes: [TrafficClass]
    /// Classes beyond `maxClasses`, merged.
    public var hiddenCount: Int
    public var hiddenRate: Int64
    /// Exits used by the visible classes, in first-use order.
    public var exits: [String]

    /// Why 12: about what fits beside the exits at the default window height.
    public static let maxClasses = 12

    public static func build(profile: RouteProfile, connections: [ConnectionRow], labels: [Int: String] = [:],
                             overridden: Set<Int> = []) -> RouteMap {
        var classes = self.classes(profile: profile, connections: connections, labels: labels, overridden: overridden)
        guard !classes.isEmpty else { return RouteMap(classes: [], hiddenCount: 0, hiddenRate: 0, exits: []) }
        let order = Dictionary(uniqueKeysWithValues: classes.enumerated().map { ($1.id, $0) })
        classes.sort { a, b in a.rate != b.rate ? a.rate > b.rate : order[a.id]! < order[b.id]! }
        let visible = Array(classes.prefix(maxClasses))
        let hidden = classes.dropFirst(maxClasses)
        var exits: [String] = []
        for item in visible where !exits.contains(item.exit) { exits.append(item.exit) }
        return RouteMap(classes: visible, hiddenCount: hidden.count, hiddenRate: hidden.map(\.rate).reduce(0, &+), exits: exits)
    }

    /// Every traffic class in the profile's order (route.final last) with its
    /// live rate: one per routing rule. `build` sorts and cuts this snapshot;
    /// the route map keeps the order and steadies it (RouteRows).
    public static func classes(profile: RouteProfile, connections: [ConnectionRow], labels: [Int: String] = [:],
                               overridden: Set<Int> = []) -> [TrafficClass] {
        let routed = profile.rules.filter { $0.outbound != nil }
        guard !routed.isEmpty || profile.final != nil else { return [] }
        // Connections name their rule in sing-box's print format; the rule's
        // matchKey is built the same way (RuleSummary), so match on item sets.
        var byKey: [String: Int] = [:]
        for rule in routed where !rule.condition.isEmpty && byKey[rule.condition] == nil { byKey[rule.condition] = rule.index }
        var rates: [Int?: (Int64, Int)] = [:]
        for connection in connections where !connection.isClosed {
            let key = RuleSummary.items(of: connection.rule).sorted().joined(separator: " ")
            let index: Int? = connection.rule.isEmpty ? nil : byKey[key]
            guard connection.rule.isEmpty || index != nil else { continue }
            let rate = max(0, connection.uplink) &+ max(0, connection.downlink)
            let old = rates[index] ?? (0, 0)
            rates[index] = (old.0 &+ rate, old.1 + 1)
        }
        var classes: [TrafficClass] = routed.map { rule in
            let (rate, count) = rates[rule.index] ?? (0, 0)
            return TrafficClass(id: "rule-\(rule.index)", ruleIndex: rule.index, name: labels[rule.index] ?? TrafficLabel.name(for: rule),
                                condition: rule.displayCondition, exit: rule.outbound ?? "", rate: rate, connections: count,
                                overridden: overridden.contains(rule.index))
        }
        if let final = profile.final {
            let (rate, count) = rates[nil] ?? (0, 0)
            classes.append(TrafficClass(id: "final", ruleIndex: nil, name: TrafficLabel.finalName, condition: "route.final",
                                        exit: final, rate: rate, connections: count, overridden: false))
        }
        return classes
    }
}

/// Default names for traffic classes (decision 20).
public enum TrafficLabel {
    public static let finalName = "其余流量"

    /// Well-known rule-set suffixes (after "geosite-" / "geoip-").
    static let known: [String: String] = [
        "cn": "中国大陆", "geolocation-cn": "中国大陆", "geolocation-!cn": "境外网站", "private": "局域网",
        "youtube": "YouTube", "netflix": "Netflix", "google": "Google", "github": "GitHub", "telegram": "Telegram",
        "openai": "OpenAI", "anthropic": "Anthropic", "apple": "Apple", "icloud": "iCloud", "microsoft": "Microsoft",
        "twitter": "X / Twitter", "facebook": "Facebook", "spotify": "Spotify", "disney": "Disney+", "tiktok": "TikTok",
        "steam": "Steam", "steam@cn": "Steam 下载", "category-ads-all": "广告", "category-games": "游戏", "bilibili": "哔哩哔哩",
    ]

    static func setName(_ tag: String) -> String {
        var name = tag
        for prefix in ["geosite-", "geoip-"] where name.hasPrefix(prefix) { name.removeFirst(prefix.count) }
        return known[name] ?? name
    }

    public static func name(for rule: RouteRule) -> String {
        let items = rule.items
        if items["ip_is_private"] == ["true"] { return "局域网" }
        if let sets = items["rule_set"], !sets.isEmpty {
            var names: [String] = []
            for set in sets where !names.contains(setName(set)) { names.append(setName(set)) }
            return names.joined(separator: " / ")
        }
        for key in ["process_name", "package_name"] {
            if let values = items[key], let first = values.first { return values.count > 1 ? "\(first) 等 \(values.count) 项" : first }
        }
        for key in ["domain_suffix", "domain", "domain_keyword"] {
            if let values = items[key], let first = values.first {
                let host = first.hasPrefix(".") ? String(first.dropFirst()) : first
                return values.count > 1 ? "\(host) 等 \(values.count) 项" : host
            }
        }
        if let cidr = items["ip_cidr"]?.first { return cidr }
        if let mode = items["clash_mode"]?.first { return "\(RouteMode.title(mode))模式" }
        if let port = items["port"]?.first { return "端口 \(port)" }
        return rule.condition.isEmpty ? "规则 \(rule.index + 1)" : rule.condition
    }
}

/// Region and multiplier from a node name.
public struct NodeTraits: Equatable, Sendable {
    public var region: String
    public var multiplier: String?
    public static let otherRegion = "其他"
    /// Flags and names to region; the first match wins, so put specific before broad.
    static let regions: [(String, [String])] = [
        ("香港", ["🇭🇰", "香港", "HK", "Hong Kong", "HongKong"]),
        ("台湾", ["🇹🇼", "台湾", "台灣", "TW", "Taiwan"]),
        ("日本", ["🇯🇵", "日本", "东京", "大阪", "JP", "Japan", "Tokyo"]),
        ("新加坡", ["🇸🇬", "新加坡", "狮城", "SG", "Singapore"]),
        ("韩国", ["🇰🇷", "韩国", "首尔", "KR", "Korea"]),
        ("美国", ["🇺🇸", "美国", "洛杉矶", "硅谷", "US", "USA", "United States"]),
        ("德国", ["🇩🇪", "德国", "法兰克福", "DE", "Germany"]),
        ("英国", ["🇬🇧", "英国", "伦敦", "UK", "GB", "London"]),
        ("中国", ["🇨🇳", "中国", "回国", "CN"]),
    ]

    public static func infer(_ name: String) -> NodeTraits {
        var region = otherRegion
        let words = name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        search: for (candidate, keys) in regions {
            for key in keys {
                let isCode = key.allSatisfy { $0.isASCII && $0.isUppercase } && key.count <= 3
                if isCode ? words.contains(where: { $0 == key || $0.hasPrefix(key) && $0.dropFirst(key.count).allSatisfy(\.isNumber) }) : name.localizedCaseInsensitiveContains(key) {
                    region = candidate
                    break search
                }
            }
        }
        return NodeTraits(region: region, multiplier: multiplier(in: name))
    }

    static func multiplier(in name: String) -> String? {
        let patterns = [#"([0-9]+(?:\.[0-9]+)?)\s*倍"#, #"(?:^|\s)[xX×]\s*([0-9]+(?:\.[0-9]+)?)"#, #"([0-9]+(?:\.[0-9]+)?)\s*[xX×](?:\s|$)"#]
        for pattern in patterns {
            if let match = name.range(of: pattern, options: .regularExpression) {
                let digits = name[match].filter { $0.isNumber || $0 == "." }
                return "\(digits) 倍率"
            }
        }
        return nil
    }
}

/// Three latency levels for the routing pages (design v0.3).
public enum LatencyGrade: Equatable, Sendable {
    case untested, fast, medium, slow
    /// Why 400 / 800: proxy nodes abroad sit at 150–600 ms; v0.2's single
    /// 150 ms cut painted nearly every node red (design v0.3).
    public init(milliseconds: Int32) {
        switch milliseconds {
        case ...0: self = .untested
        case ..<400: self = .fast
        case ..<800: self = .medium
        default: self = .slow
        }
    }
}
