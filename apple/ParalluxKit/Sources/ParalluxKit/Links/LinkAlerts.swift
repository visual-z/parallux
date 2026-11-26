import Foundation

/// Decides which link health changes become a 「线路不可用 / 已恢复」
/// notification. Pure, so the rules are tested here; LinkNotifier only posts.
///
/// Freeze-point stub (fix-link-alerts-single-line): today's behaviour — every
/// flip alerts at once with fixed text, and an unknown link shows its tag.
public struct LinkAlerts: Sendable {
    public struct Alert: Equatable, Sendable {
        public var tag: String
        public var healthy: Bool
        public var title: String
        public var body: String
    }

    /// How long a new state must last before it is announced.
    public static let hold: TimeInterval = 10

    private var last: [String: Bool] = [:]

    public init() {}

    /// One sample: each link tag's merged health, the display name of every
    /// link the app currently lists, and the sample time.
    public mutating func step(health: [String: Bool], names: [String: String], now _: Date) -> [Alert] {
        defer { last = health }
        guard !last.isEmpty else { return [] }
        return health.keys.sorted().compactMap { tag in
            guard let healthy = health[tag], let before = last[tag], before != healthy else { return nil }
            let name = names[tag] ?? tag
            return Alert(tag: tag, healthy: healthy,
                         title: healthy ? "线路已恢复" : "线路不可用",
                         body: healthy ? "\(name)重新参与聚合。" : "\(name)暂时不可用，新连接改走其他线路。")
        }
    }
}
