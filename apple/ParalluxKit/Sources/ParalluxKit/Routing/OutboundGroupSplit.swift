/// A picker's items resolved against one snapshot of the core's groups: the
/// items that name another group, each paired with the group it names, and the
/// rest (the nodes). Resolving once is the point: a row carries its group, so
/// nothing in the view has to look the tag up again later, when the snapshot it
/// was built from may already be gone (fix-node-picker-subgroups).
public struct OutboundGroupSplit: Equatable, Sendable {
    /// One item that names another group, with that group from the same
    /// snapshot. The group is a value: clearing the live group list afterwards
    /// cannot change what this row renders.
    public struct Subgroup: Identifiable, Equatable, Sendable {
        public var item: OutboundGroupModel.Item
        public var group: OutboundGroupModel
        public var id: String { item.tag }

        public init(item: OutboundGroupModel.Item, group: OutboundGroupModel) {
            self.item = item
            self.group = group
        }
    }

    /// Items that name another group, in their original order.
    public var subgroups: [Subgroup]
    /// Items that are nodes (no group carries their tag), in their original order.
    public var nodes: [OutboundGroupModel.Item]

    public init(subgroups: [Subgroup] = [], nodes: [OutboundGroupModel.Item] = []) {
        self.subgroups = subgroups
        self.nodes = nodes
    }
}

extension OutboundGroupModel {
    /// Splits the items into the ones that name another group (paired with it)
    /// and the nodes, against one snapshot of `groups`.
    ///
    /// stub: returns nothing yet (fix-node-picker-subgroups).
    public func split(among groups: [OutboundGroupModel]) -> OutboundGroupSplit {
        OutboundGroupSplit()
    }
}