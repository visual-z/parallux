import Foundation

/// Keeps a diagram's nodes in place while traffic comes and goes
/// (docs/tasks/fix-flow-stability.md).
public struct FlowSlots: Equatable, Sendable {
    public struct Slot: Equatable, Sendable, Identifiable {
        public var id: String
        public var rate: Double
        public var isOther: Bool
    }

    public static let retention: TimeInterval = 15
    public static let smoothing: TimeInterval = 2
    public static let otherID = "\u{0}other"

    public var limit: Int
    public private(set) var slots: [Slot] = []

    public init(limit: Int) { self.limit = limit }

    public mutating func update(_ rates: [(id: String, rate: Double)], at time: TimeInterval) {}
}

/// The route map's rows in a steady order (docs/tasks/fix-flow-stability.md).
public struct RouteRows: Equatable, Sendable {
    public private(set) var active: [String] = []
    public private(set) var idle: [String] = []

    public init() {}

    public mutating func update(order: [String], rates: [String: Double], at time: TimeInterval) {}
}
