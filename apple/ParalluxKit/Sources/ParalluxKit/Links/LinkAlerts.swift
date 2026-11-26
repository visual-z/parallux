import Foundation

/// Decides which link health changes become a 「线路不可用 / 已恢复」
/// notification. Pure, so the rules are tested here; LinkNotifier only posts
/// (fix-link-alerts-single-line, INV-21).
///
/// A notification is worth showing only when it changes what the user can
/// do: a drop is news when another line takes over, and a recovery is news
/// only after its drop was. With one line there is nothing to fall back to and
/// macOS already shows the network going away, so nothing is said.
public struct LinkAlerts: Sendable {
    public struct Alert: Equatable, Sendable {
        public var tag: String
        public var healthy: Bool
        public var title: String
        public var body: String
    }

    /// Why 10 s: the author's notifications came in 「不可用 → 已恢复」 pairs
    /// within the same minute — probe hiccups, not outages. A drop that lasts
    /// ten polls is one a user would notice. Assumed value; measure by
    /// counting announced drops that recover within a minute.
    public static let hold: TimeInterval = 10

    /// The state each link was last settled in (announced or not).
    private var settled: [String: Bool] = [:]
    /// A different state a link has shown since `since`, not yet settled.
    private var pending: [String: (healthy: Bool, since: Date)] = [:]
    /// Links whose drop was announced, so their recovery is too.
    private var announcedDown: Set<String> = []
    /// Every display name seen, so a link that drops out of the list keeps it.
    private var knownNames: [String: String] = [:]

    public init() {}

    /// One sample: each link tag's merged health, the display name of every
    /// link the app currently lists, and the sample time.
    public mutating func step(health: [String: Bool], names: [String: String], now: Date) -> [Alert] {
        knownNames.merge(names) { _, new in new }
        var alerts: [Alert] = []
        for tag in health.keys.sorted() {
            guard let healthy = health[tag] else { continue }
            guard let before = settled[tag] else {
                settled[tag] = healthy // the first sample is the baseline
                continue
            }
            guard healthy != before else {
                pending[tag] = nil // flipped back within the hold
                continue
            }
            if pending[tag]?.healthy != healthy { pending[tag] = (healthy, now) }
            guard let since = pending[tag]?.since, now.timeIntervalSince(since) >= Self.hold else { continue }
            pending[tag] = nil
            settled[tag] = healthy
            if let alert = announce(tag: tag, healthy: healthy, health: health) { alerts.append(alert) }
        }
        // A link that left the samples has no state to wait on.
        for tag in pending.keys where health[tag] == nil { pending[tag] = nil }
        return alerts
    }

    private mutating func announce(tag: String, healthy: Bool, health: [String: Bool]) -> Alert? {
        let name = displayName(tag)
        if healthy {
            guard announcedDown.remove(tag) != nil else { return nil }
            return Alert(tag: tag, healthy: true, title: "线路已恢复", body: "\(name)恢复可用，重新参与聚合。")
        }
        let fallbacks = health.filter { $0.key != tag && $0.value }.keys.sorted().map(displayName)
        guard !fallbacks.isEmpty else { return nil }
        announcedDown.insert(tag)
        return Alert(tag: tag, healthy: false, title: "线路不可用",
                     body: "\(name)暂时不可用，新连接改走\(fallbacks.joined(separator: "、"))。")
    }

    /// The listed name, else the last one seen, else the interface name.
    private func displayName(_ tag: String) -> String {
        if let name = knownNames[tag] { return name }
        let prefix = ProfileComposer.linkTag("")
        return tag.hasPrefix(prefix) ? String(tag.dropFirst(prefix.count)) : tag
    }
}
