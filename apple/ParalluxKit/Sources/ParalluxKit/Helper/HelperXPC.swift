import Foundation

/// What the root helper exports on its Mach service (PLAN decision 12).
/// Replies carry JSON so the protocol needs no NSSecureCoding classes.
@objc public protocol HelperXPCProtocol {
    func version(reply: @escaping (String) -> Void)
    /// Replies with a JSON `HelperConnectionOwner`, or an error.
    func findConnectionOwner(proto: Int32, sourceAddress: String, sourcePort: Int32,
                             destinationAddress: String, destinationPort: Int32,
                             reply: @escaping (Data?, NSError?) -> Void)
    /// Replies with a JSON `HelperWorkingDirectory.Info`.
    func workingDirectoryInfo(reply: @escaping (Data?, NSError?) -> Void)
    /// Empties the working directory; refuses unless `token` is
    /// `HelperWorkingDirectory.destroyToken`.
    func destroyWorkingDirectory(token: String, reply: @escaping (NSError?) -> Void)
    /// Replies with a JSON `[CrashReportCatalog.Entry]`.
    func listCrashReports(reply: @escaping (Data?, NSError?) -> Void)
    /// Replies with a JSON `CrashReportCatalog.Report`.
    func readCrashReport(name: String, reply: @escaping (Data?, NSError?) -> Void)
}

public struct HelperConnectionOwner: Codable, Equatable, Sendable {
    public var pid: Int32
    public var userID: UInt32
    public var userName: String
    public var processPath: String
    public init(pid: Int32, userID: UInt32, userName: String, processPath: String) {
        self.pid = pid
        self.userID = userID
        self.userName = userName
        self.processPath = processPath
    }
}

public enum HelperWorkingDirectory {
    /// Guards the one destructive call against a stray or replayed message.
    public static let destroyToken = "parallux.destroy-working-directory.v1"

    public struct Info: Codable, Equatable, Sendable {
        public var path: String
        public var exists: Bool
        public var sizeBytes: Int64
        public init(path: String, exists: Bool, sizeBytes: Int64) {
            self.path = path
            self.exists = exists
            self.sizeBytes = sizeBytes
        }
    }

    /// The system extension runs sandboxed as root; its home resolves to
    /// root's container for its bundle id (SFM WorkingDirectoryManager).
    public static func extensionHome(extensionBundleID: String) -> URL {
        URL(fileURLWithPath: "/var/root/Library/Containers/\(extensionBundleID)/Data", isDirectory: true)
    }
}

public enum HelperXPC {
    /// Why 3 s for app calls: sizing walks the working directory; rule sets
    /// of a few hundred MB take well under a second. Assumed value.
    public static let defaultTimeout: TimeInterval = 3
    /// Why 1 s: the extension asks while a connection is being set up; a slow
    /// helper must not hold the connection longer. Assumed value.
    public static let ownerLookupTimeout: TimeInterval = 1

    public enum CallError: Error, Equatable {
        case timedOut
        case remote(String)
        case badReply
    }

    public static func makeInterface() -> NSXPCInterface {
        NSXPCInterface(with: HelperXPCProtocol.self)
    }
}

/// Calls the helper with a bounded wait per call; a new connection per call
/// keeps a dead helper from poisoning later calls.
public final class HelperXPCClient: @unchecked Sendable {
    private let makeConnection: @Sendable () -> NSXPCConnection

    public init(makeConnection: @escaping @Sendable () -> NSXPCConnection) {
        self.makeConnection = makeConnection
    }

    /// The helper is a launchd daemon in the system domain, hence `.privileged`.
    public convenience init(machServiceName: String) {
        self.init { NSXPCConnection(machServiceName: machServiceName, options: .privileged) }
    }

    public func version(timeout: TimeInterval = HelperXPC.defaultTimeout) throws -> String {
        try call(timeout) { proxy, finish in
            proxy.version { finish(.success($0)) }
        }
    }

    public func findConnectionOwner(proto: Int32, sourceAddress: String, sourcePort: Int32,
                                    destinationAddress: String, destinationPort: Int32,
                                    timeout: TimeInterval = HelperXPC.ownerLookupTimeout) throws -> HelperConnectionOwner {
        try decode(try call(timeout) { proxy, finish in
            proxy.findConnectionOwner(proto: proto, sourceAddress: sourceAddress, sourcePort: sourcePort,
                                      destinationAddress: destinationAddress, destinationPort: destinationPort) {
                finish(Self.result($0, $1))
            }
        })
    }

    public func workingDirectoryInfo(timeout: TimeInterval = HelperXPC.defaultTimeout) throws -> HelperWorkingDirectory.Info {
        try decode(try call(timeout) { proxy, finish in
            proxy.workingDirectoryInfo { finish(Self.result($0, $1)) }
        })
    }

    public func destroyWorkingDirectory(token: String, timeout: TimeInterval = HelperXPC.defaultTimeout) throws {
        let _: Bool = try call(timeout) { proxy, finish in
            proxy.destroyWorkingDirectory(token: token) { error in
                finish(error.map { .failure(.remote($0.localizedDescription)) } ?? .success(true))
            }
        }
    }

    public func listCrashReports(timeout: TimeInterval = HelperXPC.defaultTimeout) throws -> [CrashReportCatalog.Entry] {
        try decode(try call(timeout) { proxy, finish in
            proxy.listCrashReports { finish(Self.result($0, $1)) }
        })
    }

    public func readCrashReport(name: String, timeout: TimeInterval = HelperXPC.defaultTimeout) throws -> CrashReportCatalog.Report {
        try decode(try call(timeout) { proxy, finish in
            proxy.readCrashReport(name: name) { finish(Self.result($0, $1)) }
        })
    }

    // MARK: plumbing

    private static func result(_ data: Data?, _ error: NSError?) -> Result<Data, HelperXPC.CallError> {
        if let error { return .failure(.remote(error.localizedDescription)) }
        guard let data else { return .failure(.badReply) }
        return .success(data)
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw HelperXPC.CallError.badReply }
    }

    /// Runs one request on a fresh connection and waits at most `timeout`.
    private func call<T>(_ timeout: TimeInterval,
                         _ body: (HelperXPCProtocol, @escaping @Sendable (Result<T, HelperXPC.CallError>) -> Void) -> Void) throws -> T {
        let connection = makeConnection()
        connection.remoteObjectInterface = HelperXPC.makeInterface()
        connection.resume()
        defer { connection.invalidate() }
        let outcome = Outcome<T>()
        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            outcome.finish(.failure(.remote(error.localizedDescription)))
        } as? HelperXPCProtocol
        guard let proxy else { throw HelperXPC.CallError.remote("the connection does not export HelperXPCProtocol") }
        body(proxy) { outcome.finish($0) }
        guard let result = outcome.wait(timeout) else { throw HelperXPC.CallError.timedOut }
        return try result.get()
    }

    /// First answer wins; later ones (after a timeout) are dropped.
    private final class Outcome<T>: @unchecked Sendable {
        private let lock = NSLock()
        private let done = DispatchSemaphore(value: 0)
        private var value: Result<T, HelperXPC.CallError>?

        func finish(_ new: Result<T, HelperXPC.CallError>) {
            lock.lock()
            defer { lock.unlock() }
            guard value == nil else { return }
            value = new
            done.signal()
        }

        func wait(_ timeout: TimeInterval) -> Result<T, HelperXPC.CallError>? {
            _ = done.wait(timeout: .now() + timeout)
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }
}
