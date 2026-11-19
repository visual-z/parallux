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

    public static func parse(_ config: String) -> RouteProfile { RouteProfile(rules: [], final: nil) }
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
        ExitChain(hops: [], ending: .node)
    }
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
        RouteMap(classes: [], hiddenCount: 0, hiddenRate: 0, exits: [])
    }
}

/// Default names for traffic classes (decision 20).
public enum TrafficLabel {
    public static func name(for rule: RouteRule) -> String { rule.condition }
    public static let finalName = "其余流量"
}

/// Region and multiplier from a node name.
public struct NodeTraits: Equatable, Sendable {
    public var region: String
    public var multiplier: String?
    public static let otherRegion = "其他"
    public static func infer(_ name: String) -> NodeTraits { NodeTraits(region: otherRegion, multiplier: nil) }
}

/// Three latency levels for the routing pages (design v0.3).
public enum LatencyGrade: Equatable, Sendable {
    case untested, fast, medium, slow
    public init(milliseconds: Int32) { self = .untested }
}
