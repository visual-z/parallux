import Foundation

/// One probe of one network interface: can a socket bound to it (IP_BOUND_IF,
/// the option sing-box's `bind_interface` uses) reach the target, and which
/// public address does the far end see?
public struct LinkProbeResult: Codable, Equatable, Sendable {
    public var interface: String
    public var index: UInt32
    public var connected: Bool
    /// errno of the failing call; nil on success.
    public var errno: Int32?
    public var failedCall: String?
    public var millis: Int
    public var egressIP: String?
}

public enum LinkProbe {
    /// Why: a dead link must not stall the diagnostics page; 3 s is above any
    /// sane RTT to 1.1.1.1 and below the 5 s XPC dial bound. Assumed value.
    public static let timeout: TimeInterval = 3
    /// Cloudflare's trace endpoint echoes the client address as `ip=`.
    public static let traceHost = "1.1.1.1"
    public static let tracePort: UInt16 = 80

    public static func probe(interface: String, host: String = traceHost, port: UInt16 = tracePort,
                             timeout: TimeInterval = timeout, readTrace: Bool = true) -> LinkProbeResult {
        LinkProbeResult(interface: interface, index: 0, connected: false, errno: nil, failedCall: nil, millis: 0, egressIP: nil)
    }

    /// Extracts the `ip=` line of a /cdn-cgi/trace body.
    public static func parseTrace(_ text: String) -> String? { nil }

    /// Physical interfaces worth probing (see D2 of the research card).
    public static func candidateInterfaces() -> [String] { [] }

    static func isCandidate(name: String, flags: UInt32, hasIPv4: Bool) -> Bool { true }
}
