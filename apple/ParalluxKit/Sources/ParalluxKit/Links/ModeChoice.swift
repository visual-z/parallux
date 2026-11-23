import Foundation

/// Choosing 聚合方式 and the aggregation server in use (PLAN decision 27).
///
/// 叠加 exists only behind an aggregation server, and that is kept true when
/// the settings are written, not discovered when they are read: every change
/// to `mode`, `bondServerID` or the server list goes through these three
/// functions (INV-16), and AppModel is their only caller. Before this, the
/// controls wrote the fields themselves and 叠加 without a server ran as 主备
/// with nothing but a caption in the panel to say so.
public extension LinkSettings {
    /// What choosing a mode did.
    enum ModeChange: Equatable, Sendable {
        case applied
        /// 叠加 was asked for and there is no aggregation server; nothing changed.
        case needsServer
    }

    /// The mode of a fresh install, and the one 叠加 becomes when its last
    /// server goes. Why 分流: it is the only mode that uses every link and
    /// needs no server. With 叠加 as the default, every new install ran as
    /// 主备 on one link until a server was added.
    static let defaultMode: AggregationMode = .balance

    /// Chooses `mode`. `servers`: the ids on the aggregation server list.
    /// 叠加 with an empty list changes nothing: the caller sends the user to
    /// add a server instead.
    mutating func choose(_ mode: AggregationMode, servers: [UUID]) -> ModeChange {
        if mode.requiresAggregationServer, servers.isEmpty { return .needsServer }
        // Whatever came in, what goes out names a listed server.
        settle(on: servers)
        self.mode = mode
        checkInvariants(servers: servers)
        return .applied
    }

    /// Brings the settings in line with the server list: after a server was
    /// added or removed, and at launch for settings saved by a build that
    /// did not keep the rule.
    /// `awaitingBond`: the user asked for 叠加 while the list was empty, so
    /// the first server finishes that choice.
    mutating func serversChanged(_ servers: [UUID], awaitingBond: Bool = false) {
        settle(on: servers)
        if servers.isEmpty {
            if mode.requiresAggregationServer { mode = Self.defaultMode }
        } else if awaitingBond {
            mode = .bond
        }
        checkInvariants(servers: servers)
    }

    /// Uses `id` for 叠加; an id that is not on the list is ignored.
    mutating func useServer(_ id: UUID, servers: [UUID]) {
        guard servers.contains(id) else { return }
        bondServerID = id
        checkInvariants(servers: servers)
    }

    /// The server in use is on the list whenever the list has one: the one
    /// already chosen if it is still there, the first otherwise.
    private mutating func settle(on servers: [UUID]) {
        if let current = bondServerID, servers.contains(current) { return }
        bondServerID = servers.first
    }

    /// INV-16 (docs/INVARIANTS.md).
    private func checkInvariants(servers: [UUID]) {
        assert(bondServerID.map(servers.contains) ?? servers.isEmpty, "the server in use must be on the list")
        assert(!mode.requiresAggregationServer || bondServerID != nil, "叠加 without an aggregation server")
    }
}

public extension AggregationMode {
    /// The mode's name in a menu. 叠加 with no server opens the aggregation
    /// server page instead of switching, so it carries the ellipsis macOS
    /// gives to commands that need something more first.
    func menuTitle(hasServer: Bool) -> String {
        requiresAggregationServer && !hasServer ? title + "…" : title
    }
}
