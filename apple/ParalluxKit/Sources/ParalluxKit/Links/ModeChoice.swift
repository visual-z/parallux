import Foundation

/// Choosing 聚合方式 and the aggregation server in use.
///
/// Every change to `mode`, `bondServerID` or the server list goes through
/// these, so the rule is kept in one place instead of at each control.
public extension LinkSettings {
    /// What choosing a mode did.
    enum ModeChange: Equatable, Sendable {
        case applied
        /// 叠加 was asked for and there is no aggregation server; nothing changed.
        case needsServer
    }

    /// The mode of a fresh install.
    static let defaultMode: AggregationMode = .bond

    /// Chooses `mode`. `servers`: the ids on the aggregation server list.
    mutating func choose(_ mode: AggregationMode, servers: [UUID]) -> ModeChange {
        self.mode = mode
        return .applied
    }

    /// Brings the settings in line with the server list: after a server was
    /// added or removed, and for settings saved earlier.
    /// `awaitingBond`: the user asked for 叠加 while the list was empty.
    mutating func serversChanged(_ servers: [UUID], awaitingBond: Bool = false) {}

    /// Uses `id` for 叠加.
    mutating func useServer(_ id: UUID, servers: [UUID]) {
        bondServerID = id
    }
}

public extension AggregationMode {
    /// The mode's name in a menu.
    func menuTitle(hasServer: Bool) -> String { title }
}
