import Foundation

/// What the system extension exports on its Mach service (PLAN decision 11).
///
/// The extension runs as root, so its command.sock sits in root's home and the
/// app cannot open it; instead the extension opens the socket and hands the
/// connected descriptor over XPC (SFM's CommandXPC.swift does the same).
@objc public protocol TunnelXPCProtocol {
    /// Replies with a FileHandle connected to libbox's command server.
    func connectToCommandServer(reply: @escaping (FileHandle?, NSError?) -> Void)
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
