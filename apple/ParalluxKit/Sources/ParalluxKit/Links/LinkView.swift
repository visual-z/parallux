import Foundation

/// Per-link rates from the interfaces' own byte counters (feat-link-view).
///
/// The interface sees every byte the link carries — TCP, UDP/QUIC, and 叠加's
/// multipath legs — which the aggregate outbound's per-connection counters do
/// not. Keyed by link outbound tag so the diagram reads them like before.
public enum InterfaceRates {
    public struct Counter: Equatable, Sendable {
        public var received: UInt64
        public var sent: UInt64
        public init(received: UInt64, sent: UInt64) {
            self.received = received
            self.sent = sent
        }
    }

    /// A counter that went down (interface reset) or a new interface reads 0.
    public static func rates(previous: [String: Counter], current: [String: Counter], interval: TimeInterval) -> [String: LinkRates.Rate] {
        guard interval > 0 else { return [:] }
        var result: [String: LinkRates.Rate] = [:]
        for (name, now) in current {
            let before = previous[name] ?? now
            let down = now.received >= before.received ? now.received - before.received : 0
            let up = now.sent >= before.sent ? now.sent - before.sent : 0
            result[ProfileComposer.linkTag(name)] = LinkRates.Rate(upload: Int64(clamping: UInt64(Double(up) / interval)),
                                                                   download: Int64(clamping: UInt64(Double(down) / interval)))
        }
        return result
    }
}

/// One state per link, merged over every aggregate outbound (feat-link-view):
/// unhealthy if any group says so, active connections summed. Every reader
/// (panel, links page, notifications, menu bar) uses this, so they agree.
public enum LinkView {
    public struct State: Equatable, Sendable {
        public var healthy: Bool
        public var active: Int64
        public init(healthy: Bool, active: Int64) {
            self.healthy = healthy
            self.active = active
        }
    }

    public static func merge(_ groups: [LinkGroupStat]) -> [String: State] {
        var result: [String: State] = [:]
        for group in groups {
            for link in group.links {
                var state = result[link.tag] ?? State(healthy: true, active: 0)
                state.healthy = state.healthy && link.healthy
                state.active &+= link.active
                result[link.tag] = state
            }
        }
        return result
    }
}

/// Keeps the last diagram on screen through idle seconds (feat-link-view).
public enum FlowHold {
    /// Why 5 s: page loads pause 1–3 s between bursts; past 5 s the link is
    /// really idle. Assumed value; measure by watching how often 「暂无流量」
    /// shows while browsing.
    public static let limit: TimeInterval = 5

    public static func next<T>(current: [T], last: [T], lastAt: Date?, now: Date) -> (shown: [T], last: [T], lastAt: Date?) {
        if !current.isEmpty { return (current, current, now) }
        guard let lastAt, !last.isEmpty, now.timeIntervalSince(lastAt) <= limit else { return ([], last, lastAt) }
        return (last, last, lastAt)
    }
}
