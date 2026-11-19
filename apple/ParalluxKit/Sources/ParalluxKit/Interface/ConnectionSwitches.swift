/// 聚合 and 代理 as two switches (feat-split-switches). stub
public struct ConnectionSwitches: Codable, Equatable, Sendable, Hashable {
    public var aggregation: Bool
    public var proxy: Bool
    public init(aggregation: Bool, proxy: Bool) {
        self.aggregation = aggregation
        self.proxy = proxy
    }

    public static let both = ConnectionSwitches(aggregation: true, proxy: true)
    public static let none = ConnectionSwitches(aggregation: false, proxy: false)

    public enum Which: CaseIterable, Sendable { case aggregation, proxy }
    public enum Action: Equatable, Sendable { case connect, reload, disconnect, nothing }

    public static func shown(_ stored: ConnectionSwitches, running: Bool) -> ConnectionSwitches { stored }
    public static func toggle(_ stored: ConnectionSwitches, running: Bool, _ which: Which, on: Bool) -> (ConnectionSwitches, Action) { (stored, .nothing) }
    public static func forStart(_ stored: ConnectionSwitches) -> ConnectionSwitches { stored }
}

/// The note under the aggregation picker when the chosen mode is not the one
/// in effect (feat-split-switches). stub
public enum AggregationNotice {
    public static func text(chosen: AggregationMode, effective: AggregationMode?) -> String? { nil }
}
