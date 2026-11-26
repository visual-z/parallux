import Foundation

/// One live connection to the extension's Mach service (PLAN decision 11).
/// The link owns the lifecycle; a transport only knows how to talk over the
/// connection it wraps and whether that connection is still usable.
///
/// Every request suspends while it waits, except the command-socket dial:
/// libbox calls that from a Go thread and needs the descriptor before it
/// returns. A request that blocked would hold a thread of Swift's cooperative
/// pool, which is about one thread per core and is not topped up, so a silent
/// extension made every other `async` task in the app queue behind its
/// timeouts (refactor-xpc-polls-suspend).
public protocol TunnelXPCTransport: AnyObject, Sendable {
    /// False once the remote side or the system invalidated the connection.
    var isAlive: Bool { get }
    /// Blocks: the only caller is libbox's dialer on a Go thread.
    func dialCommandSocket(timeout: TimeInterval) throws -> Int32
    func linkStats(timeout: TimeInterval) async throws -> String
    func drainNotifications(timeout: TimeInterval) async throws -> [CoreNotification]
    func explainRoute(_ target: String, timeout: TimeInterval) async throws -> String
    func probeLinks(timeout: TimeInterval) async throws -> [LinkProbeResult]
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
    /// Held only for the synchronous bookkeeping below, never across an await.
    private let lock = NSLock()

    private var transport: (any TunnelXPCTransport)?
    /// Failures since the last answer; drives the poll cooldown.
    private var failures = 0
    /// Until then a poll returns its neutral value without dialing.
    private var reopenAt: Duration?

    // MARK: polls (skipped while the extension is not answering)

    /// Per-link counters; "[]" when the extension does not answer.
    public func linkStats() async -> String {
        await poll { try await $0.linkStats(timeout: TunnelXPC.dialTimeout) } ?? "[]"
    }

    /// Queued core notifications; empty when the extension does not answer.
    public func notifications() async -> [CoreNotification] {
        await poll { try await $0.drainNotifications(timeout: TunnelXPC.dialTimeout) } ?? []
    }

    // MARK: on-demand calls (a user or the core asked now, not on a timer)

    /// Which rule a target matches; "" when the extension does not answer.
    public func explainRoute(_ target: String) async -> String {
        (try? await call { try await $0.explainRoute(target, timeout: TunnelXPC.dialTimeout) }) ?? ""
    }

    /// Probes every link from inside the extension; throws when it does not answer.
    public func probeLinks() async throws -> [LinkProbeResult] {
        try await call { try await $0.probeLinks(timeout: TunnelXPC.probeTimeout) }
    }

    /// A descriptor for libbox's command client; throws when the extension is
    /// unreachable. Blocks: see `TunnelXPCTransport`.
    public func dialCommandSocket() throws -> Int32 {
        let connection = try requireConnection()
        return try settle(Result { try connection.dialCommandSocket(timeout: TunnelXPC.dialTimeout) }).get()
    }

    // MARK: lifecycle

    /// The connection to use now: the kept one while it lives, else a new one.
    private func requireConnection() throws -> any TunnelXPCTransport {
        lock.lock()
        defer { lock.unlock() }
        if let transport, transport.isAlive { return transport }
        transport = nil
        guard let fresh = try? open() else { throw TunnelXPC.DialError.remote("no connection to the extension") }
        transport = fresh
        return fresh
    }

    private func poll<T>(_ body: (any TunnelXPCTransport) async throws -> T) async -> T? {
        let cooling = lock.withLock { reopenAt.map { now() < $0 } ?? false }
        guard !cooling else { return nil }
        return try? await call(body)
    }

    private func call<T>(_ body: (any TunnelXPCTransport) async throws -> T) async throws -> T {
        let connection = try requireConnection()
        do {
            return try settle(.success(try await body(connection))).get()
        } catch {
            return try settle(.failure(error)).get()
        }
    }

    /// Books one call's outcome. A cancelled call says nothing about the
    /// extension, so it neither clears nor starts a cooldown.
    private func settle<T>(_ outcome: Result<T, Error>) -> Result<T, Error> {
        switch outcome {
        case .success: succeeded()
        case let .failure(error) where error is CancellationError: break
        case .failure: failed()
        }
        return outcome
    }

    private func succeeded() {
        lock.withLock {
            failures = 0
            reopenAt = nil
        }
    }

    private func failed() {
        let dead: (any TunnelXPCTransport)? = lock.withLock {
            failures += 1
            let wait = TunnelXPCPollRetry.delay(after: failures) ?? TunnelXPCPollRetry.delayLimit
            reopenAt = now() + wait
            defer { transport = nil }
            return transport
        }
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
        let reply = Reply<Int32>(discard: { close($0) })
        guard let proxy = proxy(answering: reply) else { throw Self.noProtocol }
        proxy.connectToCommandServer { handle, error in
            if let error {
                reply.finish(.failure(TunnelXPC.DialError.remote(error.localizedDescription)))
            } else if let handle {
                // dup: the handle closes its descriptor when XPC releases it,
                // and libbox takes ownership of the one we return.
                let fd = dup(handle.fileDescriptor)
                reply.finish(fd >= 0 ? .success(fd) : .failure(TunnelXPC.DialError.noHandle))
            } else {
                reply.finish(.failure(TunnelXPC.DialError.noHandle))
            }
        }
        // A descriptor that arrives after we stop waiting is closed, not leaked.
        guard let result = reply.wait(timeout: timeout) else { throw TunnelXPC.DialError.timedOut }
        return try result.get()
    }

    public func linkStats(timeout: TimeInterval) async throws -> String {
        try await request(timeout: timeout) { proxy, finish in
            proxy.linkStats { finish(.success($0)) }
        }
    }

    public func drainNotifications(timeout: TimeInterval) async throws -> [CoreNotification] {
        let data: Data = try await request(timeout: timeout) { proxy, finish in
            proxy.drainNotifications { finish(.success($0)) }
        }
        return NotificationQueue.decode(data)
    }

    public func explainRoute(_ target: String, timeout: TimeInterval) async throws -> String {
        try await request(timeout: timeout) { proxy, finish in
            proxy.explainRoute(target) { finish(.success($0)) }
        }
    }

    public func probeLinks(timeout: TimeInterval) async throws -> [LinkProbeResult] {
        let data: Data = try await request(timeout: timeout) { proxy, finish in
            proxy.probeLinks { data, error in
                if let error {
                    finish(.failure(TunnelXPC.DialError.remote(error.localizedDescription)))
                } else {
                    finish(.success(data ?? Data()))
                }
            }
        }
        return try JSONDecoder().decode([LinkProbeResult].self, from: data)
    }

    private static let noProtocol = TunnelXPC.DialError.remote("the connection does not export TunnelXPCProtocol")

    /// A proxy whose connection errors settle `reply`.
    private func proxy<Value: Sendable>(answering reply: Reply<Value>) -> (any TunnelXPCProtocol)? {
        connection.remoteObjectProxyWithErrorHandler { error in
            reply.finish(.failure(TunnelXPC.DialError.remote(error.localizedDescription)))
        } as? TunnelXPCProtocol
    }

    /// Sends one message and suspends until the first of: its reply, a
    /// connection error, `timeout`, or the caller's cancellation (INV-20).
    /// The timeout is a dispatch timer, so nothing holds a thread meanwhile.
    private func request<Value: Sendable>(
        timeout: TimeInterval,
        _ send: (any TunnelXPCProtocol, @escaping @Sendable (Result<Value, Error>) -> Void) -> Void
    ) async throws -> Value {
        let reply = Reply<Value>(discard: { _ in })
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                reply.attach(continuation)
                guard let proxy = proxy(answering: reply) else {
                    reply.finish(.failure(Self.noProtocol))
                    return
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    reply.finish(.failure(TunnelXPC.DialError.timedOut))
                }
                send(proxy, reply.finish)
            }
        } onCancel: {
            reply.finish(.failure(CancellationError()))
        }
    }

    /// The first outcome wins and is delivered once, to whichever waiter is
    /// there: a suspended task (`attach`) or a blocked dial (`wait`). Later
    /// outcomes are dropped; a late value goes to `discard` so it can release
    /// what it owns.
    private final class Reply<Value: Sendable>: @unchecked Sendable {
        init(discard: @escaping (Value) -> Void) { self.discard = discard }

        private let discard: (Value) -> Void
        private let lock = NSLock()
        private let done = DispatchSemaphore(value: 0)
        private var result: Result<Value, Error>?
        private var continuation: CheckedContinuation<Value, Error>?
        private var abandoned = false

        @Sendable func finish(_ value: Result<Value, Error>) {
            lock.lock()
            guard result == nil, !abandoned else {
                lock.unlock()
                if case let .success(late) = value { discard(late) }
                return
            }
            result = value
            let waiting = continuation
            continuation = nil
            lock.unlock()
            done.signal()
            waiting?.resume(with: value)
        }

        /// Resumes at once when the outcome is already in (the caller was
        /// cancelled before the message went out).
        func attach(_ waiting: CheckedContinuation<Value, Error>) {
            lock.lock()
            guard let result else {
                continuation = waiting
                lock.unlock()
                return
            }
            lock.unlock()
            waiting.resume(with: result)
        }

        func wait(timeout: TimeInterval) -> Result<Value, Error>? {
            _ = done.wait(timeout: .now() + timeout)
            lock.lock()
            defer { lock.unlock() }
            if result == nil { abandoned = true }
            return result
        }
    }
}
