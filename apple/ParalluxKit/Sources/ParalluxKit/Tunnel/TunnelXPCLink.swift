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

/// The real connection: one `NSXPCConnection`, configured and resumed once,
/// dead once the system invalidates it (the extension was replaced or quit).
///
/// This is the only code that touches an `NSXPCConnection`'s configuration,
/// and it does so only in `init`, before anyone else can see the connection.
/// The link hands one transport to every poller at once, and
/// `NSXPCConnection` promises nothing about changing its configuration while
/// other threads send over it: re-setting `remoteObjectInterface` on each
/// call freed the interface another call's proxy was still reading
/// (fix-tunnel-xpc-interface-race).
public final class NSXPCLinkTransport: TunnelXPCTransport, @unchecked Sendable {
    public convenience init(service: String) {
        self.init(connection: NSXPCConnection(machServiceName: service))
    }

    /// Takes a connection nobody has resumed yet; tests pass one to an anonymous listener.
    init(connection: NSXPCConnection) {
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
        // A descriptor that arrives after the caller gave up is closed, not leaked.
        try request(timeout: timeout, discard: { close($0) }) { proxy, finish in
            proxy.connectToCommandServer { handle, error in
                if let error {
                    finish(.failure(.remote(error.localizedDescription)))
                } else if let handle {
                    // dup: the handle closes its descriptor when XPC releases it,
                    // and libbox takes ownership of the one we return.
                    let fd = dup(handle.fileDescriptor)
                    finish(fd >= 0 ? .success(fd) : .failure(.noHandle))
                } else {
                    finish(.failure(.noHandle))
                }
            }
        }
    }

    public func linkStats(timeout: TimeInterval) throws -> String {
        try request(timeout: timeout) { proxy, finish in
            proxy.linkStats { finish(.success($0)) }
        }
    }

    public func drainNotifications(timeout: TimeInterval) throws -> [CoreNotification] {
        let data: Data = try request(timeout: timeout) { proxy, finish in
            proxy.drainNotifications { finish(.success($0)) }
        }
        return NotificationQueue.decode(data)
    }

    public func explainRoute(_ target: String, timeout: TimeInterval) throws -> String {
        try request(timeout: timeout) { proxy, finish in
            proxy.explainRoute(target) { finish(.success($0)) }
        }
    }

    /// Freeze-point stub (refactor-xpc-polls-suspend): an async face over the
    /// blocking call, so the card's tests measure today's behaviour.
    public func explainRoute(_ target: String, timeout: TimeInterval) async throws -> String {
        let blocking: (String, TimeInterval) throws -> String = explainRoute
        return try blocking(target, timeout)
    }

    public func probeLinks(timeout: TimeInterval) throws -> [LinkProbeResult] {
        let data: Data = try request(timeout: timeout) { proxy, finish in
            proxy.probeLinks { data, error in
                if let error {
                    finish(.failure(.remote(error.localizedDescription)))
                } else {
                    finish(.success(data ?? Data()))
                }
            }
        }
        return try JSONDecoder().decode([LinkProbeResult].self, from: data)
    }

    /// Sends one message and blocks at most `timeout` for its answer. The
    /// connection's error handler and the reply race; the first one wins.
    private func request<Value>(
        timeout: TimeInterval,
        discard: @escaping (Value) -> Void = { _ in },
        _ send: (any TunnelXPCProtocol, @escaping (Result<Value, TunnelXPC.DialError>) -> Void) -> Void
    ) throws -> Value {
        let reply = Reply<Value>(discard: discard)
        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            reply.finish(.failure(.remote(error.localizedDescription)))
        } as? TunnelXPCProtocol
        guard let proxy else {
            throw TunnelXPC.DialError.remote("the connection does not export TunnelXPCProtocol")
        }
        send(proxy, reply.finish)
        guard let result = reply.wait(timeout: timeout) else {
            throw TunnelXPC.DialError.timedOut
        }
        return try result.get()
    }

    /// First answer wins; an answer after the caller stopped waiting goes to
    /// `discard` so it can release what it owns.
    private final class Reply<Value>: @unchecked Sendable {
        init(discard: @escaping (Value) -> Void) { self.discard = discard }

        private let discard: (Value) -> Void
        private let lock = NSLock()
        private let done = DispatchSemaphore(value: 0)
        private var result: Result<Value, TunnelXPC.DialError>?
        private var abandoned = false

        func finish(_ value: Result<Value, TunnelXPC.DialError>) {
            lock.lock()
            defer { lock.unlock() }
            guard result == nil, !abandoned else {
                if case let .success(late) = value { discard(late) }
                return
            }
            result = value
            done.signal()
        }

        func wait(timeout: TimeInterval) -> Result<Value, TunnelXPC.DialError>? {
            _ = done.wait(timeout: .now() + timeout)
            lock.lock()
            defer { lock.unlock() }
            if result == nil { abandoned = true }
            return result
        }
    }
}
