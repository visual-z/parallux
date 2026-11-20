import Foundation

/// User choices about links (links page, panel): which links are on, their
/// priority, which are backup-only.
public struct LinkPreferences: Codable, Equatable, Sendable {
    /// Interface names in priority order; links not listed come after, by name.
    public var order: [String] = []
    public var disabled: Set<String> = []
    public var backup: Set<String> = []
    public init() {}

    /// The enabled links in priority order.
    public func enabled(_ available: [LinkInterface]) -> [LinkInterface] {
        let ranked = available.sorted { a, b in
            let ia = order.firstIndex(of: a.name) ?? Int.max
            let ib = order.firstIndex(of: b.name) ?? Int.max
            return ia != ib ? ia < ib : a.name < b.name
        }
        return ranked.filter { !disabled.contains($0.name) }
    }
}

/// Rewrites a user's sing-box profile so its traffic uses the enabled links
/// (PLAN decision 13): one `direct` + `bind_interface` link outbound per link,
/// the user's `direct` outbounds replaced by aggregate outbounds of the same
/// tag (sing-box rejects `detour` on direct, card 环境假设), and proxy nodes
/// without a detour pointed at the aggregate.
public enum ProfileComposer {
    public static let aggregateTag = "parallux-links"
    /// The user's direct outbounds go through the bond too (feat-bond-direct,
    /// author 2026-11-20); the core keeps LAN and the server itself off it.
    public static let bondCarriesDirect = true
    public static func linkTag(_ interface: String) -> String { "link-\(interface)" }

    /// Outbound types that carry their own server connection and can take a detour.
    static let proxyTypes: Set<String> = ["shadowsocks", "vmess", "vless", "trojan", "hysteria", "hysteria2", "tuic",
                                          "socks", "http", "shadowtls", "ssh", "anytls", "wireguard", "naive"]

    public struct Bond: Equatable, Sendable {
        /// A multipath outbound JSON object without `outbounds` (filled with the link tags).
        public var outbound: [String: AnyCodableValue]
        public var tag: String
        public init(tag: String, outbound: [String: AnyCodableValue]) {
            self.tag = tag
            self.outbound = outbound
        }
    }

    /// One relay link's outbound (feat-relay-links). stub
    public struct Relay: Equatable, Sendable {
        /// The LinkInterface name of the relay link ("relay-1a2b3c4d").
        public var name: String
        /// The interface name of the physical link that reaches the relay host.
        public var carrier: String
        /// The outbound JSON object without `tag` and `detour`.
        public var outbound: [String: AnyCodableValue]
        public init(name: String, carrier: String, outbound: [String: AnyCodableValue]) {
            self.name = name
            self.carrier = carrier
            self.outbound = outbound
        }
    }

    public enum Failure: Error, Equatable {
        case notJSON
    }

    /// nil links (fewer than two enabled) returns the profile unchanged.
    public static func compose(_ profile: String, links: [LinkInterface], backup: Set<String>, mode: AggregationMode,
                               bond: Bond? = nil, relays: [Relay] = []) throws -> String {
        guard var root = (try? JSONSerialization.jsonObject(with: Data(profile.utf8))) as? [String: Any] else {
            throw Failure.notJSON
        }
        guard links.count >= 2 else { return profile }
        var outbounds = (root["outbounds"] as? [[String: Any]]) ?? []
        let linkTags = links.map { linkTag($0.name) }
        let taken = Set(outbounds.compactMap { $0["tag"] as? String })

        // Dial options of the user's first direct outbound carry over to every
        // link (domain_resolver, tcp_fast_open…); bind_interface is ours.
        var linkBase = (outbounds.first { $0["type"] as? String == "direct" }) ?? [:]
        for key in ["tag", "type", "bind_interface", "detour", "inet4_bind_address", "inet6_bind_address", "routing_mark"] {
            linkBase.removeValue(forKey: key)
        }
        let linkOutbounds: [[String: Any]] = links.map { link in
            var outbound = linkBase
            outbound["type"] = "direct"
            outbound["tag"] = linkTag(link.name)
            outbound["bind_interface"] = link.name
            return outbound
        }

        let useBond = mode == .bond && bond != nil
        /// `carriesBond`: whether this aggregate goes through the aggregation
        /// server in 叠加. Both the nodes' detour and the direct replacements
        /// do (bondCarriesDirect); `bond_bypass` names the server so the core
        /// does not send connections to it through itself.
        func aggregate(tag: String, carriesBond: Bool) -> [String: Any] {
            let bonded = useBond && carriesBond
            var outbound: [String: Any] = [
                "type": "aggregate", "tag": tag,
                "mode": mode == .bond && !bonded ? AggregationMode.failover.rawValue : mode.rawValue,
                "links": linkTags,
            ]
            let backupTags = links.filter { backup.contains($0.name) }.map { linkTag($0.name) }
            if !backupTags.isEmpty { outbound["backup"] = backupTags }
            if bonded, let bond {
                outbound["bond"] = bond.tag
                if case let .string(host)? = bond.outbound["server"], !host.isEmpty { outbound["bond_bypass"] = [host] }
            }
            return outbound
        }

        // Replace each user direct with an aggregate of the same tag, so rules
        // and selectors that say "direct" now use the links.
        outbounds = outbounds.map { outbound in
            guard outbound["type"] as? String == "direct", let tag = outbound["tag"] as? String,
                  outbound["bind_interface"] == nil else { return outbound }
            return aggregate(tag: tag, carriesBond: bondCarriesDirect)
        }
        // Nodes without a detour dial their server through the links.
        outbounds = outbounds.map { outbound in
            guard let type = outbound["type"] as? String, proxyTypes.contains(type), outbound["detour"] == nil else { return outbound }
            var copy = outbound
            copy["detour"] = aggregateTag
            return copy
        }
        var added = linkOutbounds.filter { !taken.contains($0["tag"] as! String) }
        if !taken.contains(aggregateTag) { added.append(aggregate(tag: aggregateTag, carriesBond: true)) }
        if useBond, let bond, !taken.contains(bond.tag) {
            var multipath = bond.outbound.mapValues(\.foundation)
            multipath["tag"] = bond.tag
            // A bond fragment may name its legs (AggregationServer.bond picks two).
            if multipath["outbounds"] == nil { multipath["outbounds"] = linkTags }
            added.append(multipath)
        }
        outbounds.append(contentsOf: added)
        root["outbounds"] = outbounds
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}

/// A JSON value that round-trips through Codable, for outbound fragments.
public enum AnyCodableValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), array([AnyCodableValue]), object([String: AnyCodableValue]), null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([AnyCodableValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: AnyCodableValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    /// Foundation form for JSONSerialization.
    public var foundation: Any {
        switch self {
        case let .string(value): value
        case let .number(value): value
        case let .bool(value): value
        case let .array(value): value.map(\.foundation)
        case let .object(value): value.mapValues(\.foundation)
        case .null: NSNull()
        }
    }
}
