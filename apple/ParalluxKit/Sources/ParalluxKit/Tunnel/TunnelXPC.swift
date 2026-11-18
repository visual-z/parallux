import Foundation

/// What the system extension exports on its Mach service (PLAN decision 11).
///
/// The extension runs as root, so its command.sock sits in root's home and the
/// app cannot open it; instead the extension opens the socket and hands the
/// connected descriptor over XPC (SFM's CommandXPC.swift does the same).
@objc public protocol TunnelXPCProtocol {
    /// Replies with a FileHandle connected to libbox's command server.
    func connectToCommandServer(reply: @escaping (FileHandle?, NSError?) -> Void)
    /// Runs LinkProbe on every candidate interface from inside the extension
    /// and replies with a JSON array of LinkProbeResult.
    func probeLinks(reply: @escaping (Data?, NSError?) -> Void)
}

public enum TunnelXPC {
    /// How long the app waits for the extension to answer a dial.
    /// Why: libbox calls the dialer synchronously from Go and a missing reply
    /// (extension crashed, listener not resumed) would hang that goroutine
    /// forever. 5 s is assumed: SFM's local probe timeout is a few seconds and
    /// an XPC round trip to a running extension takes milliseconds; measure
    /// with `log stream` on the dial if this ever fires spuriously.
    public static let dialTimeout: TimeInterval = 5

    public enum DialError: Error, Equatable {
        case timedOut
        case noHandle
        case remote(String)
    }

    /// Bound for a whole probeLinks round: probes run in parallel, each
    /// capped at LinkProbe.timeout, plus slack for XPC. Derived, not measured.
    public static let probeTimeout: TimeInterval = LinkProbe.timeout + 2

    /// Asks the extension to probe every link; see TunnelXPCProtocol.probeLinks.
    public static func probeLinks(over connection: NSXPCConnection, timeout: TimeInterval = probeTimeout) throws -> [LinkProbeResult] {
        connection.remoteObjectInterface = makeInterface()
        connection.resume()
        let done = DispatchSemaphore(value: 0)
        let box = ReplyBox()
        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            box.set(.failure(.remote(error.localizedDescription)))
            done.signal()
        } as? TunnelXPCProtocol
        guard let proxy else { throw DialError.remote("the connection does not export TunnelXPCProtocol") }
        proxy.probeLinks { data, error in
            if let error {
                box.set(.failure(.remote(error.localizedDescription)))
            } else {
                box.set(.success(data ?? Data()))
            }
            done.signal()
        }
        guard done.wait(timeout: .now() + timeout) == .success, let result = box.get() else {
            throw DialError.timedOut
        }
        return try JSONDecoder().decode([LinkProbeResult].self, from: result.get())
    }

    /// Runs the probes concurrently; used by the extension's XPC handler.
    public static func runProbes(interfaces: [String] = LinkProbe.candidateInterfaces()) -> [LinkProbeResult] {
        let results = ResultsBox(count: interfaces.count)
        DispatchQueue.concurrentPerform(iterations: interfaces.count) { index in
            results.set(index, LinkProbe.probe(interface: interfaces[index]))
        }
        return results.values
    }

    private final class ReplyBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Result<Data, DialError>?
        func set(_ new: Result<Data, DialError>) { lock.withLock { if value == nil { value = new } } }
        func get() -> Result<Data, DialError>? { lock.withLock { value } }
    }

    private final class ResultsBox: @unchecked Sendable {
        private let lock = NSLock()
        private var slots: [LinkProbeResult?]
        init(count: Int) { slots = Array(repeating: nil, count: count) }
        func set(_ index: Int, _ value: LinkProbeResult) { lock.withLock { slots[index] = value } }
        var values: [LinkProbeResult] { lock.withLock { slots.compactMap { $0 } } }
    }

    /// Whitelists FileHandle in the reply; NSXPC refuses classes it was not told about.
    public static func makeInterface() -> NSXPCInterface {
        let interface = NSXPCInterface(with: TunnelXPCProtocol.self)
        interface.setClasses(
            NSSet(object: FileHandle.self) as! Set<AnyHashable>,
            for: #selector(TunnelXPCProtocol.connectToCommandServer(reply:)),
            argumentIndex: 0,
            ofReply: true
        )
        return interface
    }

    /// Asks the extension behind `connection` for a command-server socket and
    /// returns a descriptor the caller owns. Never waits longer than `timeout`.
    public static func dialCommandSocket(over connection: NSXPCConnection, timeout: TimeInterval = dialTimeout) throws -> Int32 {
        connection.remoteObjectInterface = makeInterface()
        connection.resume()
        let outcome = Outcome()
        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            outcome.finish(.failure(.remote(error.localizedDescription)))
        } as? TunnelXPCProtocol
        guard let proxy else {
            throw DialError.remote("the connection does not export TunnelXPCProtocol")
        }
        proxy.connectToCommandServer { handle, error in
            if let error {
                outcome.finish(.failure(.remote(error.localizedDescription)))
            } else if let handle {
                // dup: the handle closes its descriptor when XPC releases it,
                // and libbox takes ownership of the one we return.
                let fd = dup(handle.fileDescriptor)
                outcome.finish(fd >= 0 ? .success(fd) : .failure(.noHandle))
            } else {
                outcome.finish(.failure(.noHandle))
            }
        }
        guard let result = outcome.wait(timeout: timeout) else {
            throw DialError.timedOut
        }
        return try result.get()
    }

    /// First answer wins; a late reply after a timeout closes its descriptor
    /// instead of leaking it.
    private final class Outcome: @unchecked Sendable {
        private let lock = NSLock()
        private let done = DispatchSemaphore(value: 0)
        private var result: Result<Int32, DialError>?
        private var abandoned = false

        func finish(_ value: Result<Int32, DialError>) {
            lock.lock()
            defer { lock.unlock() }
            if result != nil || abandoned {
                if case let .success(fd) = value { close(fd) }
                return
            }
            result = value
            done.signal()
        }

        func wait(timeout: TimeInterval) -> Result<Int32, DialError>? {
            _ = done.wait(timeout: .now() + timeout)
            lock.lock()
            defer { lock.unlock() }
            if result == nil { abandoned = true }
            return result
        }
    }
}
