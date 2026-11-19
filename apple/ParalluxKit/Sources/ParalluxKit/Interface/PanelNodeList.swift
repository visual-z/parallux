import Foundation

/// The groups of the panel's node page (docs/tasks/fix-panel-nodes-design-parity.md).
public enum PanelNodeList {
    public struct Section: Identifiable, Equatable, Sendable {
        public var tag: String
        public var subtitle: String
        public var selectable: Bool
        public var selected: String
        public var items: [OutboundGroupModel.Item]
        public var isOpen: Bool
        public var id: String { tag }
    }

    public static let openByDefault = 2

    public static func sections(_ groups: [OutboundGroupModel], search: String, toggled: Set<String>) -> [Section] { [] }
}
