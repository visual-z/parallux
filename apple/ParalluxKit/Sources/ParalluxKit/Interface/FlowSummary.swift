import Foundation

/// Right-hand column of the flow diagram: live traffic per exit.
public enum FlowSummary {
    public struct Exit: Equatable, Sendable {
        public var name: String
        /// Bytes per second, both directions.
        public var rate: Int64
        public init(name: String, rate: Int64) {
            self.name = name
            self.rate = rate
        }
    }

    /// Why 4: the diagram has room for about five labelled exits at panel size.
    public static let maxExits = 4
    public static let directName = "直连"
    public static let otherName = "其他"

    public static func exits(_ connections: [ConnectionRow]) -> [Exit] { [] }
}
