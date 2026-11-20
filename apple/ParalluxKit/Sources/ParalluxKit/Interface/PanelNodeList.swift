import Foundation

/// The groups of the panel's node page as design v0.2 shows them: which
/// groups appear, which are open, and what a search leaves.
public enum PanelNodeList {
    public struct Section: Identifiable, Equatable, Sendable {
        public var tag: String
        /// 「手动选择」 or 「自动测速」 after the group's name.
        public var subtitle: String
        /// A selector: its nodes can be picked. A urltest group only shows its pick.
        public var selectable: Bool
        public var selected: String
        public var items: [OutboundGroupModel.Item]
        public var isOpen: Bool
        public var id: String { tag }
    }

    /// Why 2: design v0.2 opens the first two groups and folds the rest; a
    /// profile's first groups are the ones people switch, and a subscription
    /// can bring dozens of groups that would bury them.
    public static let openByDefault = 2

    /// - Parameters:
    ///   - search: text typed into the search field; surrounding whitespace is ignored.
    ///   - toggled: groups the user opened or folded, i.e. the opposite of their default.
    public static func sections(_ groups: [OutboundGroupModel], search: String, toggled: Set<String>) -> [Section] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return groups.enumerated().compactMap { index, group in
            let items = term.isEmpty ? group.items : group.items.filter { $0.tag.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            // A search only shows groups it hit, and shows them open: a match hidden in a folded group is no match.
            if !term.isEmpty, items.isEmpty { return nil }
            let open = term.isEmpty ? (index < openByDefault) != toggled.contains(group.tag) : true
            return Section(tag: group.tag, subtitle: subtitle(group.type), selectable: group.selectable, selected: group.selected,
                           items: items, isOpen: open)
        }
    }

    /// Design v0.2's wording for the two group kinds.
    static func subtitle(_ type: String) -> String {
        switch type.lowercased() {
        case "selector": "手动选择"
        case "urltest": "自动测速"
        default: type
        }
    }
}
