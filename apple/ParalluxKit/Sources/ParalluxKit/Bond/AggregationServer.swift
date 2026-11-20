import Foundation

/// One aggregation server (glossary: 聚合服务器). The psk lives in a SecretStore, never here.
public struct AggregationServer: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var host: String
    public var port: UInt16

    public init(id: UUID = UUID(), name: String, host: String, port: UInt16) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
    }

    public static let bondTag = "parallux-bond"

    /// The multipath outbound over the two highest-priority physical links
    /// (the transport has exactly two legs; relay links are never
    /// legs). nil with fewer than two.
    public func bond(links: [LinkInterface], psk: String) -> ProfileComposer.Bond? {
        let legs = links.filter { $0.kind != .relay }
        guard legs.count >= 2 else { return nil }
        return ProfileComposer.Bond(tag: Self.bondTag, outbound: [
            "type": .string("multipath"),
            "outbounds": .array(legs.prefix(2).map { .string(ProfileComposer.linkTag($0.name)) }),
            "server": .string(host),
            "server_port": .number(Double(port)),
            "psk": .string(psk),
        ])
    }
}

/// docs/research/aggregation-server-link.md, version 1.
public enum AggregationServerLink {
    public enum Failure: Error, Equatable {
        case notAParalluxLink
        case notAnAggregationServerLink
        case unsupportedVersion(String?)
        case missing(String)
        case duplicate(String)
        case badPort(String)
        case pskTooShort
    }

    /// Why 16: install.sh makes 43; anything under 16 is a typo or a test value.
    public static let minimumPSKLength = 16

    public static func parse(_ link: String) throws -> (server: AggregationServer, psk: String) {
        guard let components = URLComponents(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "parallux" else { throw Failure.notAParalluxLink }
        guard components.host?.lowercased() == "aggregation-server" else { throw Failure.notAnAggregationServerLink }
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
        guard let psk = values["psk"], !psk.isEmpty else { throw Failure.missing("psk") }
        guard psk.count >= minimumPSKLength else { throw Failure.pskTooShort }
        let name = components.percentEncodedFragment?.removingPercentEncoding.flatMap { $0.isEmpty ? nil : $0 } ?? host
        return (AggregationServer(name: name, host: host, port: UInt16(port)), psk)
    }
}

/// Where secrets live: the Keychain in the app, memory in tests.
public protocol SecretStore: Sendable {
    func secret(for id: UUID) -> String?
    func setSecret(_ secret: String, for id: UUID) throws
    func removeSecret(for id: UUID)
}

/// The server list in UserDefaults; psks go to the SecretStore.
@MainActor
public final class AggregationServerStore {
    public private(set) var servers: [AggregationServer] = []
    private let defaults: UserDefaults
    private let secrets: any SecretStore
    public static let defaultsKey = "parallux.aggregation-servers"

    public init(defaults: UserDefaults, secrets: any SecretStore) {
        self.defaults = defaults
        self.secrets = secrets
        if let data = defaults.data(forKey: Self.defaultsKey),
           let servers = try? JSONDecoder().decode([AggregationServer].self, from: data) {
            self.servers = servers
        }
    }

    /// Adds or replaces (same id) a server; the psk goes to the SecretStore first,
    /// so a failure there leaves no server without its secret.
    public func add(_ server: AggregationServer, psk: String) throws {
        try secrets.setSecret(psk, for: server.id)
        servers.removeAll { $0.id == server.id }
        servers.append(server)
        save()
    }

    public func update(_ server: AggregationServer) {
        guard let index = servers.firstIndex(where: { $0.id == server.id }) else { return }
        servers[index] = server
        save()
    }

    public func remove(_ id: UUID) {
        servers.removeAll { $0.id == id }
        save()
        secrets.removeSecret(for: id)
    }

    public func psk(for id: UUID) -> String? { secrets.secret(for: id) }

    private func save() {
        if let data = try? JSONEncoder().encode(servers) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}

/// 单线程下载测速 (diagnostics): one connection per path, then the bond.
public enum SpeedTest {
    public struct Result: Equatable, Sendable {
        public var label: String
        /// Bytes per second; nil when the test failed.
        public var rate: Int64?
        public var isBond: Bool
        public init(label: String, rate: Int64?, isBond: Bool) {
            self.label = label
            self.rate = rate
            self.isBond = isBond
        }
    }

    /// PLAN §1: two links, one connection ≥ 1.6 × the fastest single link.
    public static let target = 1.6

    /// Each result's bar length as a share of the fastest one, 0...1 (design
    /// v0.2, diagnostics). A failed or empty measurement has no bar.
    public static func fractions(_ results: [Result]) -> [Double] {
        let fastest = results.compactMap(\.rate).max() ?? 0
        guard fastest > 0 else { return results.map { _ in 0 } }
        return results.map { result in
            guard let rate = result.rate, rate > 0 else { return 0 }
            return min(1, Double(rate) / Double(fastest))
        }
    }

    /// "叠加是最快单线路的 1.9 倍（达标）", or nil when it cannot be compared.
    public static func summary(_ results: [Result]) -> String? {
        guard let bond = results.first(where: \.isBond)?.rate, bond > 0,
              let fastest = results.filter({ !$0.isBond }).compactMap(\.rate).max(), fastest > 0 else { return nil }
        let ratio = Double(bond) / Double(fastest)
        let verdict = ratio >= target ? "达标" : "未达标，目标 \(String(format: "%.1f", target)) 倍"
        return "叠加是最快单线路的 \(String(format: "%.1f", ratio)) 倍（\(verdict)）"
    }
}
