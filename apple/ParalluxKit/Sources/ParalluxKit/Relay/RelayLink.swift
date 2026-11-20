import Foundation

// Relay links (中继线路, PLAN decision 24). stubs: feat-relay-links

/// One relay link: a relay host on the LAN that dials out on the Mac's
/// behalf. The key lives in a SecretStore, never here.
public struct RelayLink: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var host: String
    public var port: UInt16
    public var method: String
    /// The interface name of the physical link that reaches the relay host
    /// (承载线路); nil until the app has found one.
    public var carrier: String?

    public init(id: UUID = UUID(), name: String, host: String, port: UInt16, method: String, carrier: String? = nil) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.method = method
        self.carrier = carrier
    }

    public var linkName: String { "" }
    public var link: LinkInterface { LinkInterface(name: linkName, kind: .other, displayName: "") }
    public func composed(key: String) -> ProfileComposer.Relay? { nil }
}

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

    public static let method = "2022-blake3-aes-128-gcm"

    public static func parse(_ link: String) throws -> (relay: RelayLink, key: String) {
        throw Failure.notARelayLink
    }

    public static func parseAll(_ text: String) throws -> [(relay: RelayLink, key: String)] { [] }
}

@MainActor
public final class RelayLinkStore {
    public enum Failure: Error, Equatable {
        case full(Int)
    }

    public static let limit = 16
    public static let defaultsKey = "parallux.relay-links"
    public private(set) var relays: [RelayLink] = []

    public init(defaults: UserDefaults, secrets: any SecretStore) {}

    @discardableResult
    public func add(_ relay: RelayLink, key: String) throws -> RelayLink { relay }
    public func setCarrier(_ carrier: String?, for id: UUID) {}
    public func rename(_ id: UUID, to name: String) {}
    public func remove(_ id: UUID) {}
    public func key(for id: UUID) -> String? { nil }
}

public enum RelayRates {
    public static func merge(interface: [String: LinkRates.Rate], counted: [String: LinkRates.Rate],
                             carriers: [String: String]) -> [String: LinkRates.Rate] {
        interface
    }
}
