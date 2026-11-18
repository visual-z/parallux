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

    /// The multipath outbound over the two highest-priority links (the
    /// transport has exactly two legs, feat-bond). nil with fewer than two.
    public func bond(links: [LinkInterface], psk: String) -> ProfileComposer.Bond? { nil }
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
        throw Failure.notAParalluxLink
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
    }

    public func add(_ server: AggregationServer, psk: String) throws {}
    public func remove(_ id: UUID) {}
    public func psk(for id: UUID) -> String? { nil }
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

    /// "叠加是最快单线路的 1.9 倍（达标）", or nil when it cannot be compared.
    public static func summary(_ results: [Result]) -> String? { nil }
}
