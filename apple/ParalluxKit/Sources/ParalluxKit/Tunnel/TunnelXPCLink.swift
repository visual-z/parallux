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
///
/// Why one connection: the app asked for the extension's descriptor on every
/// status tick (1 s), notification tick (2 s) and command dial, and each ask
/// built and cancelled its own `NSXPCConnection` — several mach lookups and a
/// fresh exported object in the extension every second, forever, including
/// while the extension was down (fix-tunnel-xpc-connection-churn).
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

    private var transport: (any TunnelXPCTransport)?
    /// Failures since the last answer; drives the poll cooldown.
    private var failures = 0
    /// Until then a poll returns its neutral value without dialing.
    private var reopenAt: Duration?

    // MARK: polls (skipped while the extension is not answering)

    /// Per-link counters; "[]" when the extension does not answer.
    public func linkStats() -> String {
        poll { try $0.linkStats(timeout: TunnelXPC.dialTimeout) } ?? "[]"
    }

    /// Queued core notifications; empty when the extension does not answer.
    public func notifications() -> [CoreNotification] {
        poll { try $0.drainNotifications(timeout: TunnelXPC.dialTimeout) } ?? []
    }

    // MARK: on-demand calls (a user or the core asked now, not on a timer)

    /// Which rule a target matches; "" when the extension does not answer.
    public func explainRoute(_ target: String) -> String {
        call { try $0.explainRoute(target, timeout: TunnelXPC.dialTimeout) } ?? ""
    }

    /// Probes every link from inside the extension; throws when it does not answer.
    public func probeLinks() throws -> [LinkProbeResult] {
        try requireCall { try $0.probeLinks(timeout: TunnelXPC.probeTimeout) }
    }

    /// A descriptor for libbox's command client; throws when the extension is unreachable.
    public func dialCommandSocket() throws -> Int32 {
        try requireCall { try $0.dialCommandSocket(timeout: TunnelXPC.dialTimeout) }
    }

    // MARK: lifecycle

    /// The connection to use now: the kept one while it lives, else a new one.
    /// Returns nil only when there is no connection to be had.
    private func connection() -> (any TunnelXPCTransport)? {
        lock.lock()
        defer { lock.unlock() }
        if let transport, transport.isAlive { return transport }
        transport = nil
        guard let fresh = try? open() else { return nil }
        transport = fresh
        return fresh
    }

    private func poll<T>(_ body: (any TunnelXPCTransport) throws -> T) -> T? {
        lock.lock()
        let cooling = reopenAt.map { now() < $0 } ?? false
        lock.unlock()
        guard !cooling else { return nil }
        return call(body)
    }

    private func call<T>(_ body: (any TunnelXPCTransport) throws -> T) -> T? {
        guard let connection = connection() else { return nil }
        do {
            let value = try body(connection)
            succeeded()
            return value
        } catch {
            failed()
            return nil
        }
    }

    private func requireCall<T>(_ body: (any TunnelXPCTransport) throws -> T) throws -> T {
        guard let connection = connection() else { throw TunnelXPC.DialError.remote("no connection to the extension") }
        do {
            let value = try body(connection)
            succeeded()
            return value
        } catch {
            failed()
            throw error
        }
    }

    private func succeeded() {
        lock.lock()
        defer { lock.unlock() }
        failures = 0
        reopenAt = nil
    }

    private func failed() {
        lock.lock()
        failures += 1
        let wait = TunnelXPCPollRetry.delay(after: failures) ?? TunnelXPCPollRetry.delayLimit
        reopenAt = now() + wait
        let dead = transport
        transport = nil
        lock.unlock()
        // A silent connection may still answer later; dropping it keeps the
        // next attempt on a connection the system is willing to watch.
        dead?.invalidate()
    }
}

/// How long a poll waits before trying an extension that just failed to answer.
public enum TunnelXPCPollRetry {
    /// Why 250 ms: one status tick, and a starting extension answers within it.
    public static let baseDelay: Duration = .milliseconds(250)
    /// Why 4 s: replacing the extension takes tens of seconds, and the tunnel
    /// can stay down for minutes; the cap keeps the app from hammering it while
    /// polls still recover by themselves once it answers again.
    public static let delayLimit: Duration = .seconds(4)

    /// nil for no failure (no wait); otherwise 250 ms doubling up to the cap.
    public static func delay(after failures: Int) -> Duration? {
        guard failures > 0 else { return nil }
        let doublings = min(failures - 1, 16)
        let wait = baseDelay * (1 << doublings)
        return min(wait, delayLimit)
    }

    /// Monotonic time since boot; the link only ever compares two readings.
    public static let now: @Sendable () -> Duration = {
        .nanoseconds(Int64(DispatchTime.now().uptimeNanoseconds))
    }
}

/// The real connection: one `NSXPCConnection`, resumed once, dead once the
/// system invalidates it (the extension was replaced or quit).
public final class NSXPCLinkTransport: TunnelXPCTransport, @unchecked Sendable {
    public init(service: String) {
        let connection = NSXPCConnection(machServiceName: service)
        self.connection = connection
        connection.remoteObjectInterface = TunnelXPC.makeInterface()
        connection.interruptionHandler = { [weak self] in self?.markDead() }
        connection.invalidationHandler = { [weak self] in self?.markDead() }
        connection.resume()
    }

    private let connection: NSXPCConnection
    private let lock = NSLock()
    private var alive = true

    public var isAlive: Bool { lock.withLock { alive } }

    private func markDead() {
        lock.withLock { alive = false }
    }

    public func invalidate() {
        connection.invalidate()
        markDead()
    }

    public func dialCommandSocket(timeout: TimeInterval) throws -> Int32 {
        try TunnelXPC.dialCommandSocket(over: connection, timeout: timeout, resume: false)
    }

    public func linkStats(timeout: TimeInterval) throws -> String {
        try TunnelXPC.fetchLinkStats(over: connection, timeout: timeout, resume: false)
    }

    public func drainNotifications(timeout: TimeInterval) throws -> [CoreNotification] {
        try TunnelXPC.fetchNotifications(over: connection, timeout: timeout, resume: false)
    }

    public func explainRoute(_ target: String, timeout: TimeInterval) throws -> String {
        try TunnelXPC.fetchRouteExplanation(target, over: connection, timeout: timeout, resume: false)
    }

    public func probeLinks(timeout: TimeInterval) throws -> [LinkProbeResult] {
        try TunnelXPC.probeLinks(over: connection, timeout: timeout, resume: false)
    }
}