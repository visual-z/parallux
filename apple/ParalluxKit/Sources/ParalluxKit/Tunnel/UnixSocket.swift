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
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        let bytes = Array(path.utf8)
        // sun_path is a fixed 104-byte array; strncpy would silently truncate
        // and connect to a different path.
        guard bytes.count < capacity else { throw Failure(call: "path", code: ENAMETOOLONG) }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure(call: "socket", code: errno) }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let code = errno
            close(fd)
            throw Failure(call: "connect", code: code)
        }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }
}
