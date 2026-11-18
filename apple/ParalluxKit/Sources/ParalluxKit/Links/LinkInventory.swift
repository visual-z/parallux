import Foundation

/// The kind of a physical link, as the panel and links page show it.
public enum LinkKind: String, Codable, Sendable, CaseIterable {
    case wifi, ethernet, iPhone, other

    public var title: String {
        switch self {
        case .wifi: "Wi‑Fi"
        case .ethernet: "有线"
        case .iPhone: "iPhone"
        case .other: "其他"
        }
    }

    public var symbol: String {
        switch self {
        case .wifi: "wifi"
        case .ethernet: "cable.connector"
        case .iPhone: "iphone"
        case .other: "network"
        }
    }
}

/// One candidate link: a physical interface that can reach the Internet.
public struct LinkInterface: Codable, Equatable, Identifiable, Sendable {
    public var name: String
    public var kind: LinkKind
    /// The system's name for the service ("Wi‑Fi", "USB 10/100/1000 LAN", "iPhone USB").
    public var displayName: String
    public var address: String?
    public var id: String { name }

    public init(name: String, kind: LinkKind, displayName: String, address: String? = nil) {
        self.name = name
        self.kind = kind
        self.displayName = displayName
        self.address = address
    }
}

public enum LinkInventory {
    /// What the system configuration says about one interface.
    public struct Raw: Equatable, Sendable {
        public var name: String
        /// SCNetworkInterface type ("IEEE80211", "Ethernet", "Bridge"…), or nil.
        public var scType: String?
        /// SCNetworkInterface localized display name, or nil.
        public var scDisplayName: String?
        public var flags: UInt32
        public var ipv4: String?
        public init(name: String, scType: String?, scDisplayName: String?, flags: UInt32, ipv4: String?) {
            self.name = name
            self.scType = scType
            self.scDisplayName = scDisplayName
            self.flags = flags
            self.ipv4 = ipv4
        }
    }

    /// Candidate links in a stable order (Wi‑Fi first, then by name).
    public static func classify(_ raws: [Raw]) -> [LinkInterface] { [] }
}
