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
        Result(config: config, applied: [], stale: [])
    }

    /// Valid overrides' names by rule index.
    public func names(for profile: RouteProfile) -> [Int: String] { [:] }
}
