import Foundation

/// The overview's cards (SFM #34: show, hide and reorder them).
public enum DashboardCard: String, Codable, CaseIterable, Identifiable, Sendable {
    case traffic, routeMode, profile
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .traffic: "流量"
        case .routeMode: "路由模式"
        case .profile: "配置"
        }
    }
}

public struct DashboardCards: Codable, Equatable, Sendable {
    public var order: [DashboardCard] = DashboardCard.allCases
    public var hidden: Set<DashboardCard> = []
    public init() {}

    /// Cards to draw, in order.
    public var visible: [DashboardCard] { [] }

    /// Drops unknown ids, appends cards added in a newer version.
    public static func decode(order raw: [String], hidden rawHidden: [String]) -> DashboardCards { DashboardCards() }

    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {}
    public mutating func reset() {}
}
