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
    public var visible: [DashboardCard] { order.filter { !hidden.contains($0) } }

    /// Drops unknown ids, appends cards added in a newer version.
    public static func decode(order raw: [String], hidden rawHidden: [String]) -> DashboardCards {
        var cards = DashboardCards()
        var order: [DashboardCard] = []
        for id in raw { if let card = DashboardCard(rawValue: id), !order.contains(card) { order.append(card) } }
        order += DashboardCard.allCases.filter { !order.contains($0) }
        cards.order = order
        cards.hidden = Set(rawHidden.compactMap(DashboardCard.init(rawValue:)))
        return cards
    }

    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { order[$0] }
        let before = source.filter { $0 < destination }.count
        order = order.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        order.insert(contentsOf: moving, at: destination - before)
    }

    public mutating func reset() { self = DashboardCards() }

    // Stored as raw strings so a card removed in a later version cannot break decoding.
    enum CodingKeys: String, CodingKey { case order, hidden }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self = Self.decode(order: try c.decodeIfPresent([String].self, forKey: .order) ?? [],
                           hidden: try c.decodeIfPresent([String].self, forKey: .hidden) ?? [])
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(order.map(\.rawValue), forKey: .order)
        try c.encode(hidden.map(\.rawValue).sorted(), forKey: .hidden)
    }
}
