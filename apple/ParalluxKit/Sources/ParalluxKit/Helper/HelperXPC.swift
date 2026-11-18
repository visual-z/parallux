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
        throw HelperXPC.CallError.timedOut
    }

    public func findConnectionOwner(proto: Int32, sourceAddress: String, sourcePort: Int32,
                                    destinationAddress: String, destinationPort: Int32,
                                    timeout: TimeInterval = HelperXPC.ownerLookupTimeout) throws -> HelperConnectionOwner {
        throw HelperXPC.CallError.timedOut
    }

    public func workingDirectoryInfo(timeout: TimeInterval = HelperXPC.defaultTimeout) throws -> HelperWorkingDirectory.Info {
        throw HelperXPC.CallError.timedOut
    }

    public func destroyWorkingDirectory(token: String, timeout: TimeInterval = HelperXPC.defaultTimeout) throws {
        throw HelperXPC.CallError.timedOut
    }

    public func listCrashReports(timeout: TimeInterval = HelperXPC.defaultTimeout) throws -> [CrashReportCatalog.Entry] {
        throw HelperXPC.CallError.timedOut
    }

    public func readCrashReport(name: String, timeout: TimeInterval = HelperXPC.defaultTimeout) throws -> CrashReportCatalog.Report {
        throw HelperXPC.CallError.timedOut
    }
}
