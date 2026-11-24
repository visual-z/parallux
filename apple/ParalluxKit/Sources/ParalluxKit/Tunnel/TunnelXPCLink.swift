import Foundation

/// One live connection to the extension's Mach service (PLAN decision 11).
/// The link owns the lifecycle; a transport only knows how to talk over the
/// connection it wraps and whether that connection is still usable.
public protocol TunnelXPCTransport: AnyObject, Sendable {
    /// False once the remote side or the system invalidated the connection.
    var isAlive: Bool { get }
    func dialCommandSocket(timeout: TimeInterval) throws -> Int32
    func linkStats(timeout: TimeInterval) throws -> String
    func drainNotifications(timeout: TimeInterval) throws -> [CoreNotification]
    func explainRoute(_ target: String, timeout: TimeInterval) throws -> String
    func probeLinks(timeout: TimeInterval) throws -> [LinkProbeResult]
    func invalidate()
}

/// The one place that reaches the extension's Mach service: one connection,
/// reused until it dies, and a bounded wait after the extension fails to answer.
public final class TunnelXPCLink: @unchecked Sendable {
    public init(
        open: @escaping @Sendable () throws -> any TunnelXPCTransport,
        now: @escaping @Sendable () -> Duration = TunnelXPCPollRetry.now
    ) {
        self.open = open
        self.now = now
    }

    private let open: @Sendable () throws -> any TunnelXPCTransport
    private let now: @Sendable () -> Duration
    private let lock = NSLock()

    public func linkStats() -> String {
        guard let transport = try? open() else { return "[]" }
        return (try? transport.linkStats(timeout: TunnelXPC.dialTimeout)) ?? "[]"
    }

    public func notifications() -> [CoreNotification] {
        guard let transport = try? open() else { return [] }
        return (try? transport.drainNotifications(timeout: TunnelXPC.dialTimeout)) ?? []
    }

    public func explainRoute(_ target: String) -> String {
        guard let transport = try? open() else { return "" }
        return (try? transport.explainRoute(target, timeout: TunnelXPC.dialTimeout)) ?? ""
    }

    public func probeLinks() throws -> [LinkProbeResult] {
        try open().probeLinks(timeout: TunnelXPC.probeTimeout)
    }

    public func dialCommandSocket() throws -> Int32 {
        try open().dialCommandSocket(timeout: TunnelXPC.dialTimeout)
    }
}

/// How long a poll waits before trying an extension that just failed to answer.
public enum TunnelXPCPollRetry {
    /// Why: 250 ms is one status tick; a starting extension answers within it.
    public static let baseDelay: Duration = .milliseconds(250)
    /// Why 4 s: the extension may be replaced (tens of seconds); the cap keeps
    /// the app from hammering it while the pollers still recover on their own.
    public static let delayLimit: Duration = .seconds(4)

    public static func delay(after failures: Int) -> Duration? {
        .milliseconds(250)
    }

    public static let now: @Sendable () -> Duration = {
        .nanoseconds(Int64(DispatchTime.now().uptimeNanoseconds))
    }
}