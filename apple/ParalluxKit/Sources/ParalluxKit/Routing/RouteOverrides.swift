import Foundation

/// 「改走」: per-profile rule overrides kept in the app (decision 20). The
/// profile file is never edited; the composer rewrites a rule's outbound when
/// connecting. A fingerprint of the rule's condition guards against a
/// subscription update shifting rules so an override would hit the wrong one.
public struct RouteOverride: Codable, Equatable, Sendable {
    public var ruleIndex: Int
    public var fingerprint: String
    public var outbound: String?
    public var name: String?

    public init(ruleIndex: Int, fingerprint: String, outbound: String? = nil, name: String? = nil) {
        self.ruleIndex = ruleIndex
        self.fingerprint = fingerprint
        self.outbound = outbound
        self.name = name
    }
}

public struct RouteOverrides: Codable, Equatable, Sendable {
    public var items: [RouteOverride] = []
    public init(items: [RouteOverride] = []) { self.items = items }

    public struct Result: Equatable, Sendable {
        public var config: String
        /// Rule indices whose outbound was rewritten.
        public var applied: Set<Int>
        /// Overrides dropped: rule moved or changed, or target outbound gone.
        public var stale: [RouteOverride]
    }

    /// Rewrites route.rules[i].outbound for every valid override.
    public static func apply(_ overrides: RouteOverrides, to config: String) -> Result {
        let reroutes = overrides.items.filter { $0.outbound != nil }
        guard !reroutes.isEmpty, var root = (try? JSONSerialization.jsonObject(with: Data(config.utf8))) as? [String: Any],
              var route = root["route"] as? [String: Any], var rules = route["rules"] as? [[String: Any]] else {
            return Result(config: config, applied: [], stale: [])
        }
        let profile = RouteProfile.parse(config)
        var tags = Set(((root["outbounds"] as? [[String: Any]]) ?? []).compactMap { $0["tag"] as? String })
        tags.formUnion(((root["endpoints"] as? [[String: Any]]) ?? []).compactMap { $0["tag"] as? String })
        var applied: Set<Int> = []
        var stale: [RouteOverride] = []
        for item in reroutes {
            guard item.ruleIndex >= 0, item.ruleIndex < profile.rules.count,
                  profile.rules[item.ruleIndex].condition == item.fingerprint,
                  profile.rules[item.ruleIndex].outbound != nil,
                  let target = item.outbound, tags.contains(target) else {
                stale.append(item)
                continue
            }
            rules[item.ruleIndex]["outbound"] = target
            applied.insert(item.ruleIndex)
        }
        guard !applied.isEmpty else { return Result(config: config, applied: [], stale: stale) }
        route["rules"] = rules
        root["route"] = route
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else {
            return Result(config: config, applied: [], stale: stale)
        }
        return Result(config: String(decoding: data, as: UTF8.self), applied: applied, stale: stale)
    }

    /// Valid overrides' names by rule index.
    public func names(for profile: RouteProfile) -> [Int: String] {
        var names: [Int: String] = [:]
        for item in items {
            guard let name = item.name, !name.isEmpty, item.ruleIndex >= 0, item.ruleIndex < profile.rules.count,
                  profile.rules[item.ruleIndex].condition == item.fingerprint else { continue }
            names[item.ruleIndex] = name
        }
        return names
    }

    /// Indices of rules whose outbound an override changes (for the 「已覆盖」 badge).
    public func reroutedIndices(for profile: RouteProfile) -> Set<Int> {
        Set(items.filter { $0.outbound != nil && $0.ruleIndex >= 0 && $0.ruleIndex < profile.rules.count
            && profile.rules[$0.ruleIndex].condition == $0.fingerprint }.map(\.ruleIndex))
    }

    /// Sets or clears the override of one rule; nil outbound and nil name removes it.
    public mutating func set(rule: RouteRule, outbound: String?, name: String?) {
        items.removeAll { $0.ruleIndex == rule.index }
        guard outbound != nil || (name != nil && !(name ?? "").isEmpty) else { return }
        items.append(RouteOverride(ruleIndex: rule.index, fingerprint: rule.condition, outbound: outbound, name: name))
    }
}
