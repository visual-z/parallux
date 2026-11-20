import Foundation

/// core/pxbridge Explanation: which rule a target matches and where it goes.
public struct RouteExplanation: Codable, Equatable, Sendable {
    public var target: String
    public var ruleIndex: Int
    public var rule: String?
    public var action: String?
    public var outbound: String?
    public var final: Bool?
    public var skipped: Int?
    public var error: String?

    enum CodingKeys: String, CodingKey {
        case target, rule, action, outbound, final, skipped, error
        case ruleIndex = "rule_index"
    }

    public init(target: String, ruleIndex: Int, rule: String? = nil, action: String? = nil, outbound: String? = nil,
                final: Bool? = nil, skipped: Int? = nil, error: String? = nil) {
        self.target = target
        self.ruleIndex = ruleIndex
        self.rule = rule
        self.action = action
        self.outbound = outbound
        self.final = final
        self.skipped = skipped
        self.error = error
    }

    public static func decode(_ json: String) -> RouteExplanation? {
        guard !json.isEmpty else { return nil }
        return try? JSONDecoder().decode(RouteExplanation.self, from: Data(json.utf8))
    }
}
