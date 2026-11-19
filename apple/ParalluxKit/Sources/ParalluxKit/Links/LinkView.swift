import Foundation

/// Per-link rates from the interfaces' own byte counters (feat-link-view). stub
public enum InterfaceRates {
    public struct Counter: Equatable, Sendable {
        public var received: UInt64
        public var sent: UInt64
        public init(received: UInt64, sent: UInt64) {
            self.received = received
            self.sent = sent
        }
    }

    public static func rates(previous: [String: Counter], current: [String: Counter], interval: TimeInterval) -> [String: LinkRates.Rate] { [:] }
}

/// One state per link, merged over every aggregate outbound (feat-link-view). stub
public enum LinkView {
    public struct State: Equatable, Sendable {
        public var healthy: Bool
        public var active: Int64
        public init(healthy: Bool, active: Int64) {
            self.healthy = healthy
            self.active = active
        }
    }

    public static func merge(_ groups: [LinkGroupStat]) -> [String: State] { [:] }
}

/// Keeps the last diagram on screen through idle seconds (feat-link-view). stub
public enum FlowHold {
    public static let limit: TimeInterval = 0
    public static func next<T>(current: [T], last: [T], lastAt: Date?, now: Date) -> (shown: [T], last: [T], lastAt: Date?) {
        (current, current, now)
    }
}
