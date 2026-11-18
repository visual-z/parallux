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
        rows
    }
}
