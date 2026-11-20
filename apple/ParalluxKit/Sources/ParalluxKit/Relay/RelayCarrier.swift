import Foundation

/// Finds a relay link's carrier (glossary: 承载线路): the physical link over
/// which the relay host answers. The import link cannot say, because it is
/// written on the relay host, which knows nothing of this Mac's interfaces.
public enum RelayCarrier {
    /// Why 2 s per interface: a relay host on the LAN answers in
    /// milliseconds, and over the wrong interface the SYN simply goes
    /// nowhere, so the wait is spent only on wrong guesses. Assumed value;
    /// raise it if a relay host across a slow site link is ever missed.
    public static let timeout: TimeInterval = 2

    /// Why 4: a name with many addresses must not multiply the wait above.
    static let addressLimit = 4

    /// The first of `interfaces` (priority order) over which `host:port`
    /// accepts a TCP connection from a socket bound to that interface — the
    /// same binding the core's link outbounds use (LinkProbe). nil when none
    /// does, or when the host has no IPv4 address (LinkProbe is IPv4-only).
    public static func find(host: String, port: UInt16, interfaces: [String], timeout: TimeInterval = timeout) -> String? {
        let addresses = ipv4Addresses(of: host)
        return interfaces.first { interface in
            addresses.contains { LinkProbe.probe(interface: interface, host: $0, port: port, timeout: timeout, readTrace: false).connected }
        }
    }

    /// `host` itself when it is an IPv4 address, otherwise what the system
    /// resolver says, at most `addressLimit`.
    static func ipv4Addresses(of host: String) -> [String] {
        var literal = in_addr()
        if inet_pton(AF_INET, host, &literal) == 1 { return [host] }
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var head: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &head) == 0, let first = head else { return [] }
        defer { freeaddrinfo(head) }
        var result: [String] = []
        for entry in sequence(first: first, next: { $0.pointee.ai_next }) where result.count < addressLimit {
            var name = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(entry.pointee.ai_addr, entry.pointee.ai_addrlen, &name, socklen_t(name.count), nil, 0, NI_NUMERICHOST) == 0 {
                let address = String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                if !result.contains(address) { result.append(address) }
            }
        }
        return result
    }
}

extension RelayLink {
    /// Why a relay link cannot be used right now.
    public enum Blocker: Equatable, Sendable {
        /// No physical link reaches the relay host (yet).
        case noCarrier
        /// Its carrier (interface name) is switched off or unplugged.
        case carrierOff(String)
        /// Its key is missing from the Keychain.
        case noKey
    }

    /// nil when the relay can be composed: it has a key, and its carrier is
    /// one of the enabled physical links.
    public func blocker(hasKey: Bool, enabledPhysical: [String]) -> Blocker? {
        guard hasKey else { return .noKey }
        guard let carrier else { return .noCarrier }
        return enabledPhysical.contains(carrier) ? nil : .carrierOff(carrier)
    }
}
