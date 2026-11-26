import Foundation

public enum ConnectionState: String, CaseIterable, Identifiable, Sendable {
    case active, closed, all
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .active: "活跃"
        case .closed: "已关闭"
        case .all: "全部"
        }
    }
}

public enum ConnectionSort: String, CaseIterable, Identifiable, Sendable {
    case date, traffic, rate
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .date: "时间"
        case .traffic: "总流量"
        case .rate: "实时速率"
        }
    }
}

extension ConnectionQuery {
    /// Filter by state, hide DNS, search, then sort (newest / largest first).
    public static func apply(_ rows: [ConnectionRow], state: ConnectionState, sort: ConnectionSort, hideDNS: Bool, text: String) -> [ConnectionRow] {
        let kept = rows.filter { row in
            switch state {
            case .active: if row.isClosed { return false }
            case .closed: if !row.isClosed { return false }
            case .all: break
            }
            return !(hideDNS && isDNS(row))
        }
        return filter(kept, text: text).sorted { a, b in
            switch sort {
            case .date: a.createdAt > b.createdAt
            case .traffic: (a.uplinkTotal + a.downlinkTotal) > (b.uplinkTotal + b.downlinkTotal)
            case .rate: (a.uplink + a.downlink, a.createdAt) > (b.uplink + b.downlink, b.createdAt)
            }
        }
    }

    /// Port 53 or a sniffed DNS protocol (SFM hides the same).
    static func isDNS(_ row: ConnectionRow) -> Bool {
        row.destination.hasSuffix(":53") || row.rule.contains("protocol=dns")
    }
}
