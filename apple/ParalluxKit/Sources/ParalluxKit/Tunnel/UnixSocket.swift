import Foundation

/// Connects to a unix stream socket; the extension uses it to open libbox's
/// command.sock before handing the descriptor to the app.
public enum UnixSocket {
    public struct Failure: Error, Equatable, CustomStringConvertible {
        public let call: String
        public let code: Int32
        public var description: String { "\(call): \(String(cString: strerror(code)))" }
    }

    public static func connect(path: String) throws -> FileHandle {
        throw Failure(call: "connect", code: ENOSYS)
    }
}
