/// 聚合 and 代理 as two switches (feat-split-switches, decision 21).
///
/// `stored` is what the user last ran with; what the switches show is that
/// only while the tunnel runs. Off, both show off, and turning one on starts
/// with just that one: what you see is what runs.
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

    public static func shown(_ stored: ConnectionSwitches, running: Bool) -> ConnectionSwitches {
        running ? stored : .none
    }

    /// The new stored switches and what to do with the tunnel.
    public static func toggle(_ stored: ConnectionSwitches, running: Bool, _ which: Which, on: Bool) -> (ConnectionSwitches, Action) {
        let shown = shown(stored, running: running)
        var next = shown
        switch which {
        case .aggregation: next.aggregation = on
        case .proxy: next.proxy = on
        }
        guard next != shown else { return (stored, .nothing) }
        if next == .none { return (next, .disconnect) }
        return (next, running ? .reload : .connect)
    }

    /// The power button, the menu's 启动, URLs and on-demand start with the
    /// last combination; one that had both off starts with both on.
    public static func forStart(_ stored: ConnectionSwitches) -> ConnectionSwitches {
        stored == .none ? .both : stored
    }
}

/// The note under the aggregation picker when the chosen mode is not the one
/// in effect (feat-split-switches).
public enum AggregationNotice {
    public static func text(chosen: AggregationMode, effective: AggregationMode?) -> String? {
        guard let effective, chosen == .bond, effective == .failover else { return nil }
        return "尚未设置聚合服务器，暂按主备运行"
    }
}
