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
    /// Outbound types that leave without a node. With two links or more the
    /// composer replaces the profile's `direct` outbounds by `aggregate`
    /// outbounds of the same tag (ProfileComposer), so direct traffic arrives
    /// here typed `aggregate`; nodes keep their own type and only detour
    /// through one.
    static let directTypes: Set<String> = ["direct", "aggregate"]

    public static func exits(_ connections: [ConnectionRow]) -> [Exit] {
        var rates: [String: Int64] = [:]
        for connection in connections {
            let rate = max(0, connection.uplink) &+ max(0, connection.downlink)
            guard rate > 0 else { continue }
            let name = directTypes.contains(connection.outboundType) ? directName : connection.outbound
            rates[name, default: 0] &+= rate
        }
        let sorted = rates.map { Exit(name: $0.key, rate: $0.value) }
            .sorted { $0.rate != $1.rate ? $0.rate > $1.rate : $0.name < $1.name }
        guard sorted.count > maxExits else { return sorted }
        let rest = sorted[maxExits...].map(\.rate).reduce(0, &+)
        return Array(sorted.prefix(maxExits)) + [Exit(name: otherName, rate: rest)]
    }
}
