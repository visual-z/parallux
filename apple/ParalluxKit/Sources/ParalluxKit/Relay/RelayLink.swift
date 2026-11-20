import Foundation

/// One relay link (glossary: 中继线路, PLAN decision 24): a relay host on the
/// LAN that dials out on the Mac's behalf, so it adds its own egress quota.
/// The key lives in a SecretStore, never here.
public struct RelayLink: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var host: String
    public var port: UInt16
    public var method: String
    /// The interface name of the physical link that reaches the relay host
    /// (glossary: 承载线路); nil until the app has found one. Not part of
    /// the import link: interface names belong to this Mac and change when
    /// an adapter is replugged.
    public var carrier: String?

    public init(id: UUID = UUID(), name: String, host: String, port: UInt16, method: String, carrier: String? = nil) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.method = method
        self.carrier = carrier
    }

    /// The relay's name as a link ("relay-1a2b3c4d"): what LinkPreferences
    /// orders and disables, and what ProfileComposer.linkTag turns into the
    /// outbound tag. The id's first eight digits keep it stable across
    /// renames and short enough to read in a log.
    public var linkName: String { "relay-" + id.uuidString.prefix(8).lowercased() }

    /// The relay as the rest of the app sees links.
    public var link: LinkInterface {
        LinkInterface(name: linkName, kind: .relay, displayName: name, address: host)
    }

    /// The relay's outbound for the composer; nil until a carrier is known.
    /// Field names are sing-box's shadowsocks outbound
    /// (docs/research/relay-link.md).
    public func composed(key: String) -> ProfileComposer.Relay? {
        guard let carrier else { return nil }
        return ProfileComposer.Relay(name: linkName, carrier: carrier, outbound: [
            "type": .string("shadowsocks"),
            "server": .string(host),
            "server_port": .number(Double(port)),
            "method": .string(method),
            "password": .string(key),
        ])
    }
}

/// docs/research/relay-link.md, version 1.
public enum RelayLinkURL {
    public enum Failure: Error, Equatable {
        case notAParalluxLink
        case notARelayLink
        case unsupportedVersion(String?)
        case unsupportedMethod(String?)
        case missing(String)
        case duplicate(String)
        case badPort(String)
        case badKey
    }

    /// A failure with the 1-based line it came from.
    public struct LineFailure: Error, Equatable {
        public var line: Int
        public var failure: Failure
    }

    /// The only cipher version 1 knows (server: RelayMethod).
    public static let method = "2022-blake3-aes-128-gcm"
    /// The key length `method` requires.
    static let keyBytes = 16

    public static func parse(_ link: String) throws -> (relay: RelayLink, key: String) {
        guard let components = URLComponents(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "parallux" else { throw Failure.notAParalluxLink }
        guard components.host?.lowercased() == "relay" else { throw Failure.notARelayLink }
        // percentEncodedQueryItems + removingPercentEncoding: "+" stays "+"
        // (the spec says it is not a space).
        var values: [String: String] = [:]
        for item in components.percentEncodedQueryItems ?? [] {
            guard values[item.name] == nil else { throw Failure.duplicate(item.name) }
            values[item.name] = item.value?.removingPercentEncoding ?? ""
        }
        guard values["v"] == "1" else { throw Failure.unsupportedVersion(values["v"]) }
        guard let host = values["host"], !host.isEmpty else { throw Failure.missing("host") }
        guard let portText = values["port"] else { throw Failure.missing("port") }
        guard let port = Int(portText), (1...65535).contains(port) else { throw Failure.badPort(portText) }
        // No downgrade: a method this build does not know is refused.
        guard values["method"] == method else { throw Failure.unsupportedMethod(values["method"]) }
        guard let key = values["key"], !key.isEmpty else { throw Failure.missing("key") }
        guard isKey(key) else { throw Failure.badKey }
        let name = components.percentEncodedFragment?.removingPercentEncoding.flatMap { $0.isEmpty ? nil : $0 } ?? host
        return (RelayLink(name: name, host: host, port: UInt16(port), method: method), key)
    }

    /// Exactly what the relay's shadowsocks accepts: padded standard base64
    /// of `keyBytes` bytes. Data(base64Encoded:) with no options refuses the
    /// URL-safe alphabet and missing padding.
    static func isKey(_ key: String) -> Bool {
        Data(base64Encoded: key)?.count == keyBytes
    }

    /// One link per line; blank lines are skipped. Throws LineFailure for
    /// the first line that is not a relay link, so nothing is half-added.
    public static func parseAll(_ text: String) throws -> [(relay: RelayLink, key: String)] {
        var result: [(relay: RelayLink, key: String)] = []
        for (index, line) in text.components(separatedBy: .newlines).enumerated() {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            do {
                result.append(try parse(line))
            } catch let failure as Failure {
                throw LineFailure(line: index + 1, failure: failure)
            }
        }
        return result
    }
}

/// The relay list in UserDefaults; keys go to the SecretStore.
@MainActor
public final class RelayLinkStore {
    public enum Failure: Error, Equatable {
        case full(Int)
    }

    /// Why 16: every relay link costs one health round trip a second per
    /// aggregate outbound and one row in the panel, and balance gains
    /// nothing once the office egress itself is the limit (the author
    /// measured ≥ 77 Mbps total at 20–30 per machine: about four). Assumed
    /// value; revisit when someone has more useful relay hosts than this.
    public static let limit = 16
    public static let defaultsKey = "parallux.relay-links"
    public private(set) var relays: [RelayLink] = []
    private let defaults: UserDefaults
    private let secrets: any SecretStore

    public init(defaults: UserDefaults, secrets: any SecretStore) {
        self.defaults = defaults
        self.secrets = secrets
        if let data = defaults.data(forKey: Self.defaultsKey),
           let relays = try? JSONDecoder().decode([RelayLink].self, from: data) {
            self.relays = Array(relays.prefix(Self.limit))
        }
    }

    /// Adds a relay, or replaces the one with the same host and port (a
    /// reinstalled relay host): the old entry keeps its id, so its place in
    /// the links order and its on/off state survive, and its carrier is
    /// kept. The key goes to the SecretStore first, so a failure there
    /// leaves no relay without its secret. Returns the stored entry.
    @discardableResult
    public func add(_ relay: RelayLink, key: String) throws -> RelayLink {
        var stored = relay
        if let index = relays.firstIndex(where: { $0.host.lowercased() == relay.host.lowercased() && $0.port == relay.port }) {
            stored.id = relays[index].id
            stored.carrier = relay.carrier ?? relays[index].carrier
            try secrets.setSecret(key, for: stored.id)
            relays[index] = stored
        } else {
            guard relays.count < Self.limit else { throw Failure.full(Self.limit) }
            try secrets.setSecret(key, for: stored.id)
            relays.append(stored)
        }
        save()
        return stored
    }

    public func setCarrier(_ carrier: String?, for id: UUID) {
        guard let index = relays.firstIndex(where: { $0.id == id }), relays[index].carrier != carrier else { return }
        relays[index].carrier = carrier
        save()
    }

    public func rename(_ id: UUID, to name: String) {
        guard let index = relays.firstIndex(where: { $0.id == id }) else { return }
        relays[index].name = name
        save()
    }

    public func remove(_ id: UUID) {
        relays.removeAll { $0.id == id }
        save()
        secrets.removeSecret(for: id)
    }

    public func key(for id: UUID) -> String? { secrets.secret(for: id) }

    private func save() {
        if let data = try? JSONEncoder().encode(relays) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}

/// Per-link rates when some links are relay links.
///
/// A relay link's bytes travel over its carrier's interface, so the
/// interface counters (InterfaceRates) show them on the carrier and nowhere
/// else. The core counts them per relay link; this moves them to where the
/// user expects to see them.
public enum RelayRates {
    /// - Parameters:
    ///   - interface: rates from the interfaces' counters, by link tag.
    ///   - counted: rates from the aggregate outbounds' counters (LinkRates), by link tag.
    ///   - carriers: relay link tag → its carrier's link tag.
    /// - Returns: `interface`, with every relay link added at its counted
    ///   rate (0 when not counted yet) and that rate taken off its carrier.
    ///   The carrier never goes below 0: the two are sampled at different
    ///   instants, and the relay's bytes are counted before encryption.
    public static func merge(interface: [String: LinkRates.Rate], counted: [String: LinkRates.Rate],
                             carriers: [String: String]) -> [String: LinkRates.Rate] {
        var result = interface
        for (relay, carrier) in carriers {
            let rate = counted[relay] ?? LinkRates.Rate(upload: 0, download: 0)
            result[relay] = rate
            guard var carried = result[carrier] else { continue }
            carried.upload = max(0, carried.upload - rate.upload)
            carried.download = max(0, carried.download - rate.download)
            result[carrier] = carried
        }
        return result
    }
}
