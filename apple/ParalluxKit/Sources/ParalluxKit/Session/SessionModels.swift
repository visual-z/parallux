import Foundation

/// sing-box log levels (log/level.go); lower is more severe.
public enum LogLevel: Int, CaseIterable, Identifiable, Comparable, Sendable {
    case panic = 0, fatal, error, warn, info, debug, trace
    public var id: Int { rawValue }
    public static func < (a: LogLevel, b: LogLevel) -> Bool { a.rawValue < b.rawValue }
    public var title: String { "\(self)".uppercased() }
    public init(sing value: Int32) { self = .info }
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
    public static func filter(_ entries: [LogEntry], level: LogLevel, text: String) -> [LogEntry] { [] }
}

/// The design colours a delay green when fast and red when slow.
public enum DelayGrade: Equatable, Sendable {
    case untested, fast, slow
    /// Why 150 ms: the design's examples put 74 ms green and 168 ms red.
    public static let slowThreshold: Int32 = 150
    public init(milliseconds: Int32) { self = .untested }
}

public enum RouteMode {
    public static func title(_ mode: String) -> String { mode }
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

    public init(id: String, process: String, destination: String, rule: String, outbound: String, chain: [String] = [],
                network: String = "tcp", uplinkTotal: Int64 = 0, downlinkTotal: Int64 = 0, createdAt: Date = Date(), isClosed: Bool = false) {
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
    }
}

public enum ConnectionQuery {
    public static func filter(_ rows: [ConnectionRow], text: String) -> [ConnectionRow] { [] }
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

    public static func parse(config: String) -> [RuleSummary] { [] }

    /// Connections per rule, keyed by RuleSummary.id.
    public static func hits(_ rules: [RuleSummary], connections: [ConnectionRow]) -> [Int: Int] { [:] }
}
