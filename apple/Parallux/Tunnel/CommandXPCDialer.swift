import Foundation
import Libbox
import ParalluxKit

/// libbox calls this when its command client connects: ask the extension
/// over XPC for a socket to its command server (PLAN decision 11).
final class CommandXPCDialer: NSObject, LibboxXPCDialerProtocol, @unchecked Sendable {
    static let shared = CommandXPCDialer()

    func dialXPC(_ ret0_: UnsafeMutablePointer<Int32>?) throws {
        let connection = try Self.connection()
        defer { connection.invalidate() }
        ret0_?.pointee = try TunnelXPC.dialCommandSocket(over: connection)
    }

    /// Probes every link from inside the extension (research-sysext-bind-interface).
    static func probeLinks() throws -> [LinkProbeResult] {
        let connection = try connection()
        defer { connection.invalidate() }
        return try TunnelXPC.probeLinks(over: connection)
    }

    /// Per-link counters; "[]" when the extension is unreachable.
    static func linkStats() -> String {
        guard let connection = try? connection() else { return "[]" }
        defer { connection.invalidate() }
        return TunnelXPC.linkStats(over: connection)
    }

    private static func connection() throws -> NSXPCConnection {
        guard let service = MachService.name(in: .main) else {
            throw NSError(domain: "Parallux.XPC", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "未签名的构建没有 App Group，无法连接网络扩展",
            ])
        }
        return NSXPCConnection(machServiceName: service)
    }
}
