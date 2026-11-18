import Foundation

/// Picks the process that owns a socket, given every socket the helper saw.
///
/// The rules mirror sing-box's matchDarwinConnectionEntry
/// (common/process/searcher_darwin_shared.go) so process rules behave as they
/// do in sing-box on macOS: same local port and address family; exact match on
/// local and remote endpoints; without a remote endpoint, the local address;
/// for UDP only, fall back to a socket on the same local address, then to one
/// bound to the wildcard address. IPv4-mapped IPv6 addresses compare as IPv4.
public enum SocketOwnerMatcher {
    public enum Proto: Int32, Sendable {
        case tcp = 6
        case udp = 17
    }

    /// An address normalised to 16 bytes; IPv4 is stored IPv4-mapped.
    public struct Address: Hashable, Sendable {
        public let bytes: [UInt8]
        public let isIPv4: Bool

        public init?(_ text: String) { return nil }

        /// For tests that need an address no parser produces.
        init(testBytes: [UInt8], isIPv4: Bool) {
            bytes = testBytes
            self.isIPv4 = isIPv4
        }

        public var isUnspecified: Bool { false }
    }

    public struct Endpoint: Hashable, Sendable {
        public var address: Address
        public var port: UInt16
        public init(_ address: Address, _ port: UInt16) {
            self.address = address
            self.port = port
        }
    }

    public struct SocketEntry: Equatable, Sendable {
        public var pid: Int32
        public var uid: UInt32
        public var proto: Proto
        public var local: Endpoint
        /// nil for an unconnected socket.
        public var remote: Endpoint?
        public init(pid: Int32, uid: UInt32, proto: Proto, local: Endpoint, remote: Endpoint?) {
            self.pid = pid
            self.uid = uid
            self.proto = proto
            self.local = local
            self.remote = remote
        }
    }

    public enum MatchKind: Equatable, Sendable {
        case exact, localFallback, wildcardFallback
    }

    /// `source` is the connection's local side (the app's socket);
    /// `destination` its remote side, nil when unknown.
    public static func match(_ entries: [SocketEntry], proto: Proto, source: Endpoint, destination: Endpoint?) -> (entry: SocketEntry, kind: MatchKind)? {
        nil
    }
}
