import Foundation

/// The kind of a physical link, as the panel and links page show it.
public enum LinkKind: String, Codable, Sendable, CaseIterable {
    case wifi, ethernet, iPhone, other
    /// A relay link (中继线路, PLAN decision 24): not an interface of this
    /// Mac but a relay host on the LAN, reached over one of the others.
    case relay

    public var title: String {
        switch self {
        case .wifi: "Wi‑Fi"
        case .ethernet: "有线"
        case .iPhone: "iPhone"
        case .other: "其他"
        case .relay: "中继"
        }
    }

    public var symbol: String {
        switch self {
        case .wifi: "wifi"
        case .ethernet: "cable.connector"
        case .iPhone: "iphone"
        case .other: "network"
        case .relay: "point.3.connected.trianglepath.dotted"
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
    /// What rows and the diagram call this link. stub: feat-relay-links
    public var title: String { kind.title }

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
    public static func classify(_ raws: [Raw]) -> [LinkInterface] {
        let links: [LinkInterface] = raws.compactMap { raw in
            guard LinkProbe.isCandidate(name: raw.name, flags: raw.flags, hasIPv4: raw.ipv4 != nil),
                  raw.scType != "Bridge" else { return nil }
            let display = raw.scDisplayName ?? raw.name
            let kind: LinkKind
            switch raw.scType {
            case "IEEE80211": kind = .wifi
            // iPhone USB tethering shows as Ethernet named "iPhone USB" (or
            // localized "iPhone"); it is metered, so it gets its own kind.
            case "Ethernet" where display.localizedCaseInsensitiveContains("iPhone"): kind = .iPhone
            case "Ethernet": kind = .ethernet
            default: kind = .other
            }
            return LinkInterface(name: raw.name, kind: kind, displayName: display, address: raw.ipv4)
        }
        return links.sorted { a, b in
            (a.kind == .wifi ? 0 : 1, a.name.count, a.name) < (b.kind == .wifi ? 0 : 1, b.name.count, b.name)
        }
    }
}
