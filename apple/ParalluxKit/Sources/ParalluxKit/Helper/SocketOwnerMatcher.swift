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

        public init?(_ text: String) {
            var v4 = in_addr()
            if inet_pton(AF_INET, text, &v4) == 1 {
                self.init(ipv4: withUnsafeBytes(of: v4.s_addr) { Array($0) })
                return
            }
            var v6 = in6_addr()
            guard inet_pton(AF_INET6, text, &v6) == 1 else { return nil }
            self.init(ipv6: withUnsafeBytes(of: v6) { Array($0) })
        }

        /// Four bytes in network order.
        public init(ipv4: [UInt8]) {
            bytes = [UInt8](repeating: 0, count: 10) + [0xFF, 0xFF] + ipv4
            isIPv4 = true
        }

        /// Sixteen bytes in network order; IPv4-mapped input counts as IPv4
        /// (sing-box's normalizeDarwinAddrPort unmaps the same way).
        public init(ipv6: [UInt8]) {
            bytes = ipv6
            isIPv4 = ipv6.count == 16 && ipv6[0..<10].allSatisfy { $0 == 0 } && ipv6[10] == 0xFF && ipv6[11] == 0xFF
        }

        /// For tests that need an address no parser produces.
        init(testBytes: [UInt8], isIPv4: Bool) {
            bytes = testBytes
            self.isIPv4 = isIPv4
        }

        public var isUnspecified: Bool {
            guard bytes.count == 16 else { return false }
            return isIPv4 ? bytes[12...].allSatisfy { $0 == 0 } : bytes.allSatisfy { $0 == 0 }
        }
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
        var localFallback: SocketEntry?
        var wildcardFallback: SocketEntry?
        for entry in entries where entry.proto == proto {
            guard entry.local.port == source.port, entry.local.address.isIPv4 == source.address.isIPv4 else { continue }
            let sameLocal = entry.local.address == source.address
            if let destination {
                if sameLocal, entry.remote == destination { return (entry, .exact) }
            } else if sameLocal {
                return (entry, .exact)
            }
            guard proto == .udp else { continue }
            if localFallback == nil, sameLocal { localFallback = entry }
            if wildcardFallback == nil, entry.local.address.isUnspecified { wildcardFallback = entry }
        }
        if let localFallback { return (localFallback, .localFallback) }
        if let wildcardFallback { return (wildcardFallback, .wildcardFallback) }
        return nil
    }
}
